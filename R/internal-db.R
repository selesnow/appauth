# Внутренние помощники для работы с таблицами авторизации. Используются
# функциями про пользователей, защиту входа и сессии, наружу не экспортируются.

#' Отозвать все токены автовхода пользователя
#'
#' Токены остаются в таблице с признаком `revoked = 1` и перестают работать.
#' Нужно при сбросе пароля и блокировке пользователя.
#'
#' @param conn Подключение к базе SQLite.
#' @param login Логин пользователя.
#'
#' @returns Число отозванных токенов.
#' @noRd
aa_revoke_user_tokens <- function(conn, login) {
  DBI::dbExecute(
    conn,
    "UPDATE auth_sessions SET revoked = 1 WHERE user_login = ?",
    params = list(login)
  )
}

#' Удалить токены автовхода пользователя
#'
#' Нужно при удалении пользователя: без этого человек, которому позже достанется
#' такой же логин, мог бы войти по cookie прежнего владельца.
#'
#' @inheritParams aa_revoke_user_tokens
#'
#' @returns Число удалённых токенов.
#' @noRd
aa_delete_user_tokens <- function(conn, login) {
  DBI::dbExecute(
    conn,
    "DELETE FROM auth_sessions WHERE user_login = ?",
    params = list(login)
  )
}

#' Число активных (не заблокированных) администраторов
#'
#' @param conn Подключение к базе SQLite.
#' @param settings Настройки, результат [aa_settings()].
#' @param excluding Логин, которого не учитывать (например, того, кого блокируют
#'   или удаляют), либо `NULL`.
#'
#' @returns Целое число.
#' @noRd
aa_active_admin_count <- function(conn, settings, excluding = NULL) {
  if (is.null(excluding)) {
    DBI::dbGetQuery(
      conn,
      "SELECT COUNT(*) AS n FROM users WHERE role = ? AND blocked = 0",
      params = list(settings$admin_role)
    )$n
  } else {
    DBI::dbGetQuery(
      conn,
      "SELECT COUNT(*) AS n FROM users WHERE role = ? AND blocked = 0 AND login <> ?",
      params = list(settings$admin_role, excluding)
    )$n
  }
}

#' Ошибка пользовательского действия
#'
#' Прерывает выполнение с сообщением на языке настроек. Приложение может
#' поймать ошибку и показать её текст пользователю, класс `appauth_error_user`
#' общий, а в поле `reason` лежит ключ причины (например, `"user_exists"`).
#'
#' @param settings Настройки, результат [aa_settings()].
#' @param reason Ключ текста из [aa_text_keys()].
#' @param ... Значения для подстановки в текст.
#' @param call Окружение для сообщения об ошибке.
#'
#' @noRd
aa_abort_user <- function(settings, reason, ..., call = rlang::caller_env()) {
  rlang::abort(
    aa_text(settings, reason, ...),
    class = "appauth_error_user",
    reason = reason,
    call = call
  )
}
