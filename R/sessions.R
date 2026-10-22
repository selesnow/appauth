#' Хеш токена автовхода
#'
#' В базе хранится только sha256 токена в виде текста (64 символа), как в
#' Server Manager, поэтому уже выданные токены продолжают работать.
#'
#' @param token Токен из cookie.
#'
#' @returns Строка из 64 символов.
#' @noRd
aa_token_hash <- function(token) {
  as.character(openssl::sha256(token))
}

#' Выдать токен автовхода
#'
#' Создаёт случайный токен (32 байта), записывает в базу его хеш и срок действия
#' (`session_days` из [aa_settings()]). Сам токен нужно передать браузеру
#' (в cookie), в базе его восстановить нельзя.
#'
#' Токен не выдаётся (возвращается `NULL`), если автовход выключен в настройках,
#' пользователя нет или он заблокирован.
#'
#' @param conn Подключение к базе SQLite.
#' @param login Логин пользователя.
#' @param settings Настройки, результат [aa_settings()].
#'
#' @returns Строка с токеном или `NULL`.
#' @export
#'
#' @examples
#' \dontrun{
#' token <- aa_issue_token(conn, "ivan")
#' if (!is.null(token)) session$sendCustomMessage("setAuthCookie", token)
#' }
aa_issue_token <- function(conn, login, settings = aa_settings()) {
  if (!isTRUE(settings$autologin) || !aa_is_string(login)) {
    return(NULL)
  }

  user <- aa_get_user(conn, login)
  if (is.null(user) || isTRUE(as.logical(user$blocked))) {
    return(NULL)
  }

  token <- openssl::base64_encode(openssl::rand_bytes(32))
  ttl <- sprintf("+%d seconds", as.integer(round(settings$session_days * 86400)))

  DBI::dbExecute(
    conn,
    "INSERT INTO auth_sessions (user_login, token_hash, expires_at)
     VALUES (?, ?, datetime('now', ?))",
    params = list(user$login, aa_token_hash(token), ttl)
  )

  token
}

#' Найти пользователя по токену автовхода
#'
#' Возвращает пользователя только если токен существует, не отозван и не истёк,
#' а сам пользователь есть, не заблокирован и не обязан сменить пароль (после
#' смены пароля войти нужно заново). Роль берётся из базы на момент проверки.
#'
#' @inheritParams aa_issue_token
#' @param token Токен из cookie.
#'
#' @returns Список с полями `login` и `role` или `NULL`.
#' @export
#'
#' @examples
#' \dontrun{
#' user <- aa_find_session_user(conn, input$auth_cookie)
#' if (!is.null(user)) { # пользователь входит без пароля }
#' }
aa_find_session_user <- function(conn, token) {
  if (!aa_is_string(token)) {
    return(NULL)
  }

  res <- DBI::dbGetQuery(
    conn,
    "SELECT u.login, u.role
     FROM auth_sessions s
     JOIN users u ON u.login = s.user_login
     WHERE s.token_hash = ?
       AND s.revoked = 0
       AND s.expires_at > datetime('now')
       AND u.blocked = 0
       AND u.must_change = 0",
    params = list(aa_token_hash(token))
  )

  if (nrow(res) != 1) {
    return(NULL)
  }

  list(login = res$login[1], role = res$role[1])
}

#' Отозвать токен автовхода
#'
#' Нужно при выходе: cookie в браузере после этого перестаёт работать.
#'
#' @inheritParams aa_find_session_user
#'
#' @returns Число отозванных токенов (0 или 1), невидимо.
#' @export
#'
#' @examples
#' \dontrun{
#' aa_revoke_token(conn, input$auth_cookie)
#' }
aa_revoke_token <- function(conn, token) {
  if (!aa_is_string(token)) {
    return(invisible(0L))
  }

  invisible(DBI::dbExecute(
    conn,
    "UPDATE auth_sessions SET revoked = 1 WHERE token_hash = ?",
    params = list(aa_token_hash(token))
  ))
}

#' Активен ли токен автовхода
#'
#' @param conn Подключение к базе SQLite.
#' @param token Токен из cookie.
#'
#' @returns `TRUE`, если токен существует, не отозван и не истёк.
#' @noRd
aa_token_active <- function(conn, token) {
  n <- DBI::dbGetQuery(
    conn,
    "SELECT COUNT(*) AS n FROM auth_sessions
     WHERE token_hash = ? AND revoked = 0 AND expires_at > datetime('now')",
    params = list(aa_token_hash(token))
  )$n

  n > 0
}

#' Проверить, что открытая сессия всё ещё действует
#'
#' Вызывается периодически (интервал `session_check_seconds`), чтобы блокировка,
#' удаление, понижение роли и завершение сессий вступали в силу у уже вошедшего
#' пользователя, а не только при следующем входе. Сессия недействительна, если
#' пользователь удалён, заблокирован, его роль в базе отличается от роли в
#' сессии или токен этой сессии отозван (сброс пароля, «завершить все сессии»).
#'
#' Если базу прочитать не удалось, сессия считается действующей
#' (`reason = "check_failed"`), чтобы сбой базы не выбросил всех пользователей;
#' доступ при этом не расширяется, так как пароль не проверяется.
#'
#' @inheritParams aa_issue_token
#' @param role Роль, с которой пользователь вошёл.
#' @param token Токен автовхода этой сессии (`auth$token()`) или `NULL`, если
#'   у сессии токена нет (например, автовход выключен): тогда токен не проверяется.
#'
#' @returns Список: `valid` (логическое), `reason` (`"ok"`, `"deleted"`,
#'   `"blocked"`, `"role_changed"`, `"token_revoked"`, `"check_failed"`) и `role`
#'   (актуальная роль из базы или `NULL`).
#' @export
#'
#' @examples
#' \dontrun{
#' check <- aa_user_session_valid(conn, auth$user()$login, auth$user()$role, auth$token())
#' if (!check$valid) auth$logout(reason = check$reason)
#' }
aa_user_session_valid <- function(conn, login, role, token = NULL) {
  user <- tryCatch(aa_get_user(conn, login), error = function(e) e)

  if (inherits(user, "error")) {
    return(list(valid = TRUE, reason = "check_failed", role = NULL))
  }
  if (is.null(user)) {
    return(list(valid = FALSE, reason = "deleted", role = NULL))
  }
  if (isTRUE(as.logical(user$blocked))) {
    return(list(valid = FALSE, reason = "blocked", role = user$role))
  }
  if (!identical(as.character(user$role), as.character(role))) {
    return(list(valid = FALSE, reason = "role_changed", role = user$role))
  }

  if (aa_is_string(token)) {
    active <- tryCatch(aa_token_active(conn, token), error = function(e) NA)

    if (isFALSE(active)) {
      return(list(valid = FALSE, reason = "token_revoked", role = user$role))
    }
  }

  list(valid = TRUE, reason = "ok", role = user$role)
}
