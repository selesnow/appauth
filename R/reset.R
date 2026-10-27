# Восстановление пароля по email и email пользователей.
#
# Правила, которые держат эти функции:
#  - в базе хранится только sha256 токена восстановления, как у токенов автовхода;
#    сам токен существует только в письме;
#  - токен одноразовый и живёт `reset_ttl_minutes` минут; новый запрос гасит
#    предыдущие неиспользованные токены этого пользователя;
#  - запрос восстановления никогда не раскрывает, существует ли логин или email:
#    результат aa_request_password_reset() предназначен для журнала, а не для
#    показа пользователю;
#  - письма ограничены по числу на пользователя за час и по общему числу за минуту;
#  - после смены пароля по ссылке отзываются все токены автовхода, гасятся все
#    токены восстановления и снимается блокировка по неудачным попыткам входа.

#' Привести email к хранимому виду
#'
#' @param email Строка или `NULL`.
#'
#' @returns Адрес без пробелов по краям в нижнем регистре, `""` для пустого
#'   значения (`NULL`, `NA`, пустая строка).
#' @noRd
aa_normalize_email <- function(email) {
  if (is.null(email) || length(email) != 1 || is.na(email)) {
    return("")
  }

  tolower(trimws(as.character(email)))
}

#' Допустимый ли формат email
#'
#' @param email Нормализованный адрес.
#'
#' @returns `TRUE` или `FALSE`.
#' @noRd
aa_email_is_valid <- function(email) {
  is.character(email) && length(email) == 1 && nchar(email) <= 254 &&
    grepl("^[^@[:space:]]+@[^@[:space:].][^@[:space:]]*\\.[^@[:space:].]+$", email)
}

#' Найти проблему в email пользователя
#'
#' @param conn Подключение к базе SQLite.
#' @param email Нормализованный адрес (не пустой).
#' @param login Логин, которому адрес принадлежит (его собственный адрес не
#'   считается занятым), либо `NULL`.
#'
#' @returns `NULL` или список `reason` и `args`.
#' @noRd
aa_email_problem <- function(conn, email, login = NULL) {
  if (!aa_email_is_valid(email)) {
    return(list(reason = "email_invalid", args = list()))
  }

  owner <- DBI::dbGetQuery(
    conn, "SELECT login FROM users WHERE email = ?", params = list(email)
  )$login

  if (length(owner) > 0 && !identical(owner[1], login)) {
    return(list(reason = "email_exists", args = list()))
  }

  NULL
}

#' Email пользователя
#'
#' @inheritParams aa_get_user
#'
#' @returns Адрес в нижнем регистре или `NA_character_`, если адрес не указан или
#'   пользователя нет. Если схема не достроена до версии 7, тоже `NA_character_`.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_set_email(conn, "boss", "Boss@Example.com")
#'   aa_get_email(conn, "boss")
#'   DBI::dbDisconnect(conn)
#' }
aa_get_email <- function(conn, login) {
  aa_check_sqlite(conn)

  if (!aa_is_string(login)) {
    return(NA_character_)
  }

  email <- tryCatch(
    DBI::dbGetQuery(conn, "SELECT email FROM users WHERE login = ?", params = list(login))$email,
    error = function(e) character()
  )

  if (length(email) == 0) NA_character_ else as.character(email[1])
}

#' Указать, сменить или удалить email пользователя
#'
#' Адрес нужен для восстановления пароля ([aa_request_password_reset()]).
#' Хранится в нижнем регистре, у двух пользователей один адрес быть не может.
#' Пустое значение (`NULL`, `NA` или `""`) удаляет адрес. Ошибки (неверный формат,
#' адрес занят, пользователя нет) имеют класс `appauth_error_user` и текст на
#' языке настроек.
#'
#' @inheritParams aa_get_user
#' @param email Адрес или пустое значение для удаления.
#' @param settings Настройки, результат [aa_settings()].
#'
#' @returns `TRUE`, если адрес сохранён, и `FALSE`, если он удалён (невидимо).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_set_email(conn, "boss", "boss@example.com")
#'   aa_set_email(conn, "boss", NULL)
#'   DBI::dbDisconnect(conn)
#' }
aa_set_email <- function(conn, login, email, settings = aa_settings()) {
  aa_check_sqlite(conn)

  if (is.null(aa_get_user(conn, login))) {
    aa_abort_user(settings, "user_not_found")
  }

  email <- aa_normalize_email(email)

  if (!nzchar(email)) {
    DBI::dbExecute(conn, "UPDATE users SET email = NULL WHERE login = ?", params = list(login))
    return(invisible(FALSE))
  }

  problem <- aa_email_problem(conn, email, login)
  if (!is.null(problem)) aa_abort_problem(settings, problem)

  tryCatch(
    DBI::dbExecute(conn, "UPDATE users SET email = ? WHERE login = ?", params = list(email, login)),
    error = function(e) {
      # при одновременной записи сработает ограничение уникальности адреса
      if (grepl("UNIQUE", conditionMessage(e), fixed = TRUE)) {
        aa_abort_user(settings, "email_exists")
      }

      stop(e)
    }
  )

  invisible(TRUE)
}

#' Погасить токены восстановления пароля пользователя
#'
#' Таблицы может не быть (схема не достроена), это не должно мешать вызывающему.
#'
#' @param conn Подключение к базе SQLite.
#' @param login Логин пользователя.
#'
#' @returns Число погашенных токенов (невидимо).
#' @noRd
aa_invalidate_resets <- function(conn, login) {
  n <- tryCatch(
    DBI::dbExecute(
      conn,
      "UPDATE password_resets SET used = 1 WHERE user_login = ? AND used = 0",
      params = list(login)
    ),
    error = function(e) 0L
  )

  invisible(n)
}

#' Удалить токены восстановления пароля пользователя
#'
#' @inheritParams aa_invalidate_resets
#'
#' @returns Число удалённых токенов (невидимо).
#' @noRd
aa_delete_user_resets <- function(conn, login) {
  n <- tryCatch(
    DBI::dbExecute(conn, "DELETE FROM password_resets WHERE user_login = ?", params = list(login)),
    error = function(e) 0L
  )

  invisible(n)
}

#' Ссылка для смены пароля
#'
#' @param settings Настройки, результат [aa_settings()].
#' @param token Токен восстановления.
#'
#' @returns Строка со ссылкой.
#' @noRd
aa_reset_link <- function(settings, token) {
  base <- sub("/+$", "", settings$reset_base_url)
  paste0(base, if (grepl("?", base, fixed = TRUE)) "&" else "/?", "reset=", token)
}

#' Запросить восстановление пароля
#'
#' Находит пользователя по логину или email, создаёт одноразовый токен и вызывает
#' `settings$send_reset(email, link, login)`, чтобы отправить письмо со ссылкой.
#' В базе остаётся только хеш токена. Предыдущие неиспользованные ссылки этого
#' пользователя перестают работать.
#'
#' Письмо не отправляется, если пользователя нет, у него не указан email, он
#' заблокирован администратором или превышен лимит (`reset_max_per_hour` на
#' пользователя, `reset_max_per_minute` общий). Результат функции предназначен
#' для журнала: пользователю нужно показывать один и тот же ответ в любом из
#' случаев, чтобы нельзя было узнать, какие логины и адреса существуют.
#'
#' Ошибка в `send_reset` не прерывает функцию, а возвращается как `send_failed`:
#' токен при этом гасится.
#'
#' @inheritParams aa_get_user
#' @param identifier Логин или email, который ввёл пользователь.
#' @param settings Настройки, результат [aa_settings()] с `reset_enabled = TRUE`.
#'
#' @returns Список (невидимо): `sent` (`TRUE`, если письмо отправлено), `reason`
#'   (`"sent"`, `"disabled"`, `"no_user"`, `"no_email"`, `"blocked"`,
#'   `"throttled"` или `"send_failed"`) и `login` (найденный логин или `NA`).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_set_email(conn, "boss", "boss@example.com")
#'
#'   settings <- aa_settings(
#'     reset_enabled  = TRUE,
#'     reset_base_url = "https://apps.example.com/my_app",
#'     send_reset     = function(email, link, login) message("Ссылка для ", login, ": ", link)
#'   )
#'   aa_request_password_reset(conn, "boss", settings)$reason
#'   aa_request_password_reset(conn, "nobody", settings)$reason
#'   DBI::dbDisconnect(conn)
#' }
aa_request_password_reset <- function(conn, identifier, settings = aa_settings()) {
  aa_check_sqlite(conn)

  result <- function(reason, login = NA_character_) {
    invisible(list(sent = identical(reason, "sent"), reason = reason, login = login))
  }

  if (!isTRUE(settings$reset_enabled)) {
    return(result("disabled"))
  }

  identifier <- if (aa_is_string(identifier)) trimws(identifier) else ""
  if (!nzchar(identifier)) {
    return(result("no_user"))
  }

  # логин сравнивается точно, адрес без учёта регистра; оба запроса выполняются всегда
  by_login <- DBI::dbGetQuery(
    conn, "SELECT login, blocked, email FROM users WHERE login = ?", params = list(identifier)
  )
  by_email <- DBI::dbGetQuery(
    conn, "SELECT login, blocked, email FROM users WHERE email = ?",
    params = list(aa_normalize_email(identifier))
  )
  user <- if (nrow(by_login) == 1) by_login else if (nrow(by_email) == 1) by_email else NULL

  if (is.null(user)) {
    return(result("no_user"))
  }

  login <- user$login[1]

  if (isTRUE(as.logical(user$blocked[1]))) {
    return(result("blocked", login))
  }

  email <- user$email[1]
  if (is.na(email) || !nzchar(email)) {
    return(result("no_email", login))
  }

  per_user <- DBI::dbGetQuery(
    conn,
    "SELECT COUNT(*) AS n FROM password_resets
     WHERE user_login = ? AND created_at > datetime('now', '-1 hours')",
    params = list(login)
  )$n
  overall <- DBI::dbGetQuery(
    conn,
    "SELECT COUNT(*) AS n FROM password_resets WHERE created_at > datetime('now', '-1 minutes')"
  )$n

  if (per_user >= settings$reset_max_per_hour || overall >= settings$reset_max_per_minute) {
    return(result("throttled", login))
  }

  token <- paste(as.character(openssl::rand_bytes(32)), collapse = "")
  ttl <- sprintf("+%d seconds", as.integer(round(settings$reset_ttl_minutes * 60)))

  aa_invalidate_resets(conn, login)

  DBI::dbExecute(
    conn,
    "INSERT INTO password_resets (user_login, token_hash, expires_at)
     VALUES (?, ?, datetime('now', ?))",
    params = list(login, aa_token_hash(token), ttl)
  )

  sent <- tryCatch(
    {
      settings$send_reset(email = email, link = aa_reset_link(settings, token), login = login)
      TRUE
    },
    error = function(e) {
      message("appauth: не удалось отправить письмо восстановления пароля: ", conditionMessage(e))
      FALSE
    }
  )

  if (!sent) {
    aa_invalidate_resets(conn, login)
    return(result("send_failed", login))
  }

  result("sent", login)
}

#' Пользователь, которому принадлежит ссылка восстановления
#'
#' Проверяет токен из ссылки, ничего не меняя: он должен существовать, быть
#' неиспользованным и непросроченным, а пользователь не должен быть заблокирован
#' или удалён. Нужна, чтобы показать форму нового пароля только по рабочей ссылке.
#'
#' @inheritParams aa_get_user
#' @param token Токен из ссылки (параметр `reset` адресной строки).
#'
#' @returns Логин пользователя или `NULL`.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_reset_token_login(conn, "not-a-token")
#'   DBI::dbDisconnect(conn)
#' }
aa_reset_token_login <- function(conn, token) {
  aa_check_sqlite(conn)

  if (!aa_is_string(token)) {
    return(NULL)
  }

  res <- DBI::dbGetQuery(
    conn,
    "SELECT r.user_login AS login
     FROM password_resets r
     JOIN users u ON u.login = r.user_login
     WHERE r.token_hash = ?
       AND r.used = 0
       AND r.expires_at > datetime('now')
       AND u.blocked = 0",
    params = list(aa_token_hash(token))
  )

  if (nrow(res) != 1) NULL else res$login[1]
}

#' Задать новый пароль по ссылке из письма
#'
#' Проверяет токен ([aa_reset_token_login()]), проверяет новый пароль по правилам
#' из настроек и записывает его. Токен одноразовый: слабый пароль ошибкой
#' отклоняется и токен не тратит, а после успешной смены ссылка перестаёт
#' работать. Вместе с паролем отзываются все токены автовхода пользователя, гасятся
#' остальные ссылки восстановления, снимается требование смены пароля и
#' блокировка по неудачным попыткам входа.
#'
#' Неверная, просроченная или использованная ссылка даёт ошибку класса
#' `appauth_error_user` с `reason = "reset_link_invalid"`, слабый пароль ошибку
#' того же класса с причиной пароля.
#'
#' @inheritParams aa_reset_token_login
#' @param password Новый пароль.
#' @param settings Настройки, результат [aa_settings()].
#'
#' @returns Логин пользователя, чей пароль изменён (невидимо).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   tryCatch(
#'     aa_reset_password_with_token(conn, "not-a-token", "new-password"),
#'     appauth_error_user = function(e) conditionMessage(e)
#'   )
#'   DBI::dbDisconnect(conn)
#' }
aa_reset_password_with_token <- function(conn, token, password, settings = aa_settings()) {
  aa_check_sqlite(conn)

  login <- aa_reset_token_login(conn, token)

  if (is.null(login)) {
    aa_abort_user(settings, "reset_link_invalid")
  }

  problem <- aa_password_problem(password, settings, login)
  if (!is.null(problem)) aa_abort_problem(settings, problem)

  # токен занимает тот, кто успел первым: из двух одновременных запросов сработает один
  claimed <- DBI::dbExecute(
    conn,
    "UPDATE password_resets SET used = 1
     WHERE token_hash = ? AND used = 0 AND expires_at > datetime('now')",
    params = list(aa_token_hash(token))
  )

  if (claimed != 1) {
    aa_abort_user(settings, "reset_link_invalid")
  }

  aa_set_password(conn, login, password, settings, must_change = FALSE)
  aa_invalidate_resets(conn, login)
  tryCatch(aa_clear_attempts(conn, login, settings), error = function(e) NULL)

  invisible(login)
}
