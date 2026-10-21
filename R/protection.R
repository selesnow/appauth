# Защита входа от подбора пароля.
#
# Неудачные попытки считаются по ТОЧНОМУ логину (с учётом регистра, как и сам
# вход), независимо от того, существует ли такой логин: поэтому по сообщениям
# нельзя узнать список пользователей. Если за окно в lockout_minutes минут
# накопилось max_failed_logins неудачных попыток, вход под этим логином
# блокируется на lockout_minutes минут с момента последней неудачи. Попытки
# во время блокировки не записываются и блокировку не продлевают. Успешный
# вход обнуляет счётчик. Дополнительно есть общий лимит неудач в минуту по всем
# логинам, он останавливает перебор по многим логинам и рост таблицы.
#
# Время хранится в UTC и сравнивается средствами SQLite. Обнуление счётчика
# после успеха считается по монотонному номеру записи, а не по времени: время
# хранится с точностью до секунды, и быстрые события теряли бы порядок.

#' Ключ логина в таблице попыток входа
#'
#' Точный логин, усечённый до `login_max` символов. Пустые и состоящие из
#' пробелов логины не записываются (ключ `""`).
#'
#' @param login Введённый логин.
#' @param settings Настройки, результат [aa_settings()].
#'
#' @returns Строка.
#' @noRd
aa_login_key <- function(login, settings) {
  if (!(is.character(login) && length(login) == 1 && !is.na(login)) || !nzchar(trimws(login))) {
    return("")
  }

  substr(login, 1, settings$login_max)
}

#' Записать попытку входа
#'
#' Сохраняет результат попытки входа для защиты от подбора. Попытки с пустым
#' логином не записываются. Вызывать нужно только для попыток, сделанных НЕ
#' во время блокировки: попытки во время блокировки не записываются, чтобы не
#' продлевать её.
#'
#' @param conn Подключение к базе SQLite (`DBI::dbConnect(RSQLite::SQLite(), ...)`).
#' @param login Введённый логин (точный, с учётом регистра).
#' @param success `TRUE` для успешного входа (обнуляет счётчик неудач), `FALSE`
#'   для неудачной попытки.
#' @param settings Настройки, результат [aa_settings()].
#'
#' @returns `TRUE`, если попытка записана, `FALSE`, если логин пустой (невидимо).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_record_attempt(conn, "alsey", success = FALSE)
#'   DBI::dbDisconnect(conn)
#' }
aa_record_attempt <- function(conn, login, success, settings = aa_settings()) {
  aa_check_sqlite(conn)
  aa_check_flag(success, "success")

  key <- aa_login_key(login, settings)

  if (!nzchar(key)) {
    return(invisible(FALSE))
  }

  DBI::dbExecute(
    conn,
    "INSERT INTO login_attempts (login, success) VALUES (?, ?)",
    params = list(key, as.integer(success))
  )

  invisible(TRUE)
}

#' Сколько секунд осталось до конца блокировки логина
#'
#' Считает неудачные попытки логина после его последнего успешного входа и
#' внутри окна `lockout_minutes`. Если их не меньше `max_failed_logins`, логин
#' заблокирован до конца окна, считая от последней неудачи.
#'
#' Логин считается **точно**: `Alsey` и `alsey` это разные логины с отдельными
#' счётчиками, как и при входе.
#'
#' @inheritParams aa_record_attempt
#'
#' @returns Целое число секунд, 0 если вход разрешён.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   for (i in 1:5) aa_record_attempt(conn, "alsey", FALSE)
#'   aa_login_lock_remaining(conn, "alsey")
#'   aa_login_lock_remaining(conn, "Alsey")
#'   DBI::dbDisconnect(conn)
#' }
aa_login_lock_remaining <- function(conn, login, settings = aa_settings()) {
  aa_check_sqlite(conn)

  key <- aa_login_key(login, settings)

  if (!nzchar(key)) {
    return(0L)
  }

  window_seconds <- as.integer(settings$lockout_minutes * 60)

  # неудачи после последнего успешного входа (по номеру записи) и внутри окна
  r <- DBI::dbGetQuery(
    conn,
    "SELECT COUNT(*) AS n,
            MAX(strftime('%s', attempted_at)) AS last_fail,
            CAST(strftime('%s', 'now') AS INTEGER) AS now_ts
     FROM login_attempts
     WHERE login = ?
       AND success = 0
       AND attempted_at > datetime('now', ?)
       AND id > COALESCE(
             (SELECT MAX(id) FROM login_attempts WHERE login = ? AND success = 1),
             0)",
    params = list(key, sprintf("-%d seconds", window_seconds), key)
  )

  if (r$n < settings$max_failed_logins) {
    return(0L)
  }

  remaining <- as.integer(r$last_fail) + window_seconds - r$now_ts

  max(0L, as.integer(remaining))
}

#' Превышен ли общий лимит неудачных попыток входа
#'
#' Считает неудачные попытки по всем логинам вместе за последнюю минуту. Если
#' их не меньше `max_failed_logins_per_minute`, вход временно закрыт для всех:
#' это останавливает перебор по многим логинам и рост таблицы попыток.
#'
#' @inheritParams aa_record_attempt
#'
#' @returns `TRUE` или `FALSE`.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_global_throttled(conn)
#'   DBI::dbDisconnect(conn)
#' }
aa_global_throttled <- function(conn, settings = aa_settings()) {
  aa_check_sqlite(conn)

  n <- DBI::dbGetQuery(
    conn,
    "SELECT COUNT(*) AS n FROM login_attempts
     WHERE success = 0 AND attempted_at > datetime('now', '-60 seconds')"
  )$n

  n >= settings$max_failed_logins_per_minute
}

#' Снять блокировку логина после неудачных попыток
#'
#' Удаляет неудачные попытки входа логина (успешные остаются), поэтому логин
#' сразу можно использовать снова. Блокировку администратором вручную
#' ([aa_set_blocked()]) эта функция не снимает.
#'
#' @inheritParams aa_record_attempt
#'
#' @returns Число удалённых записей (невидимо).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   for (i in 1:5) aa_record_attempt(conn, "alsey", FALSE)
#'   aa_clear_attempts(conn, "alsey")
#'   aa_login_lock_remaining(conn, "alsey")
#'   DBI::dbDisconnect(conn)
#' }
aa_clear_attempts <- function(conn, login, settings = aa_settings()) {
  aa_check_sqlite(conn)

  key <- aa_login_key(login, settings)

  if (!nzchar(key)) {
    return(invisible(0L))
  }

  invisible(DBI::dbExecute(
    conn,
    "DELETE FROM login_attempts WHERE login = ? AND success = 0",
    params = list(key)
  ))
}

#' Можно ли сейчас пробовать войти под логином
#'
#' Единая проверка перед проверкой пароля: сначала общий лимит неудач по всем
#' логинам, затем блокировка этого логина. Если вход закрыт, пароль проверять
#' не нужно, а попытку записывать не нужно (иначе блокировка продлевалась бы).
#'
#' Функция **не останавливает вход при ошибке**: если таблиц защиты нет или к
#' ним не удалось обратиться, вход считается разрешённым (пароль всё равно
#' проверяется), а причина пишется в лог приложения. Так недоступность таблицы
#' попыток не запирает всех пользователей.
#'
#' @inheritParams aa_record_attempt
#'
#' @returns Список: `allowed` (`TRUE` или `FALSE`), `reason` (`NA`, `"throttled"`
#'   при общем лимите или `"locked"` при блокировке логина), `seconds` (сколько
#'   секунд осталось до конца блокировки логина, иначе 0) и `message` (текст для
#'   показа пользователю на языке настроек, `NA`, если вход разрешён).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_login_gate(conn, "alsey")$allowed
#'   for (i in 1:5) aa_record_attempt(conn, "alsey", FALSE)
#'   aa_login_gate(conn, "alsey")
#'   DBI::dbDisconnect(conn)
#' }
aa_login_gate <- function(conn, login, settings = aa_settings()) {
  aa_check_sqlite(conn)

  allowed <- list(allowed = TRUE, reason = NA_character_, seconds = 0L, message = NA_character_)

  tryCatch({
    if (aa_global_throttled(conn, settings)) {
      return(list(
        allowed = FALSE, reason = "throttled", seconds = 0L,
        message = aa_text(settings, "throttled")
      ))
    }

    seconds <- aa_login_lock_remaining(conn, login, settings)

    if (seconds > 0) {
      return(list(
        allowed = FALSE, reason = "locked", seconds = seconds,
        message = aa_text(settings, "locked", max(1L, as.integer(ceiling(seconds / 60))))
      ))
    }

    allowed
  }, error = function(e) {
    message("appauth: проверка блокировки входа недоступна: ", conditionMessage(e))
    allowed
  })
}

#' Пользователи со статусами для таблицы
#'
#' Список пользователей с признаками, которые нужны для таблицы на вкладке
#' управления доступом: заблокирован ли пользователь администратором, заблокирован
#' ли вход после неудачных попыток и сколько осталось. Если таблицы попыток
#' недоступны, статус блокировки по попыткам считается отсутствующим.
#'
#' @inheritParams aa_record_attempt
#'
#' @returns Таблица с колонками `login`, `role`, `blocked`, `state` (`"blocked"`
#'   при блокировке администратором, `"locked"` при блокировке по попыткам,
#'   иначе `"ok"`), `lock_seconds` (секунд до конца блокировки по попыткам) и
#'   `status` (текст статуса на языке настроек, для `"ok"` пустая строка).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_users_overview(conn)
#'   DBI::dbDisconnect(conn)
#' }
aa_users_overview <- function(conn, settings = aa_settings()) {
  aa_check_sqlite(conn)

  users <- aa_list_users(conn)

  if (nrow(users) == 0) {
    return(data.frame(
      login = character(), role = character(), blocked = integer(),
      state = character(), lock_seconds = integer(), status = character(),
      stringsAsFactors = FALSE
    ))
  }

  lock_seconds <- vapply(users$login, function(login) {
    tryCatch(aa_login_lock_remaining(conn, login, settings), error = function(e) 0L)
  }, integer(1), USE.NAMES = FALSE)

  state <- ifelse(users$blocked == 1, "blocked", ifelse(lock_seconds > 0, "locked", "ok"))

  status <- vapply(seq_len(nrow(users)), function(i) {
    switch(
      state[i],
      blocked = aa_text(settings, "status_blocked"),
      locked  = aa_text(settings, "status_locked", max(1L, as.integer(ceiling(lock_seconds[i] / 60)))),
      ""
    )
  }, character(1))

  data.frame(
    login        = users$login,
    role         = users$role,
    blocked      = as.integer(users$blocked),
    state        = state,
    lock_seconds = lock_seconds,
    status       = status,
    stringsAsFactors = FALSE
  )
}
