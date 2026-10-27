#' Отправить событие в хук приложения
#'
#' Пакет сам ничего не пишет в логи приложения: о каждом событии он сообщает
#' функции `on_event(event, user, session_id, value)`, а приложение решает, что
#' с ним делать. Ошибка в хуке никогда не прерывает действие пакета: она только
#' выводится сообщением.
#'
#' @param on_event Функция-хук или `NULL` (тогда ничего не происходит).
#' @param event Ключ события, например `"access_denied"`.
#' @param user Логин пользователя или `NULL` (запишется `"anonymous"`).
#' @param session_id Идентификатор сессии Shiny или `NULL`.
#' @param value Дополнительное значение события (строка) или `NULL`.
#'
#' @returns Невидимо `TRUE`, если хук вызван без ошибки, иначе `FALSE`.
#' @noRd
aa_emit <- function(on_event, event, user = NULL, session_id = NULL, value = NULL) {
  if (!is.function(on_event)) {
    return(invisible(FALSE))
  }

  ok <- tryCatch(
    {
      on_event(
        event = event,
        user = if (aa_is_string(user)) user else "anonymous",
        session_id = if (aa_is_string(session_id)) session_id else "",
        value = if (is.null(value)) "" else as.character(value)[1]
      )
      TRUE
    },
    error = function(e) {
      message("appauth: ошибка в on_event (", event, "): ", conditionMessage(e))
      FALSE
    }
  )

  invisible(ok)
}

#' Каталог событий авторизации
#'
#' Пакет сообщает о событиях хуку `on_event(event, user, session_id, value)`,
#' который задаёт приложение (запись в лог, уведомление в Telegram и т.д.).
#' Функция возвращает полный список событий, которые пакет может отправить.
#'
#' Поле `user` в хуке это логин, от имени которого происходит событие (для
#' неудачного входа это введённый логин, а если логина нет, то `"anonymous"`),
#' в `value` лежит уточнение из колонки `value`. Пароли и токены в события
#' не попадают никогда.
#'
#' @returns Таблица с колонками `event` (ключ), `description` (что произошло) и
#'   `value` (что лежит в поле `value`).
#' @export
#'
#' @examples
#' aa_events()
#' aa_events()$event
aa_events <- function() {
  catalog <- list(
    c("login_success",        "Успешный вход (по паролю или по cookie автовхода)",              "cookie, если вход по автовходу"),
    c("login_failed",         "Неверный логин или пароль",                                     ""),
    c("login_locked",         "Попытка входа в логин, заблокированный после неудачных попыток", "секунд до конца блокировки"),
    c("login_blocked_user",   "Попытка входа пользователя, заблокированного администратором",   ""),
    c("login_throttled",      "Отказ из-за общего лимита неудачных попыток в минуту",          ""),
    c("login_unlocked",       "Администратор снял блокировку по попыткам входа",               "логин, с которого снята блокировка"),
    c("logout",               "Пользователь вышел сам",                                        ""),
    c("session_forced_logout","Сессия завершена принудительно",                                "причина: deleted, blocked, role_changed, token_revoked"),
    c("first_admin_created",  "Создан первый администратор",                                   ""),
    c("user_added",           "Администратор добавил пользователя",                            "логин нового пользователя и роль"),
    c("user_removed",         "Администратор удалил пользователя",                             "логин удалённого пользователя"),
    c("user_role_changed",    "Администратор сменил роль пользователя",                        "логин и новая роль"),
    c("password_changed",     "Пользователь сам сменил пароль",                                 ""),
    c("sessions_revoked",     "Администратор завершил все сессии пользователя",                "логин пользователя"),
    c("password_reset",       "Администратор сменил пароль пользователя",                      "логин пользователя"),
    c("user_blocked",         "Администратор заблокировал пользователя",                       "логин пользователя"),
    c("user_unblocked",       "Администратор разблокировал пользователя",                      "логин пользователя"),
    c("access_denied",        "Отказ в доступе: у роли нет нужного права",                     "название права"),
    c("password_reset_requested", "Запрос восстановления пароля по email (пользователю ответ всегда одинаковый)", "результат: sent, no_user, no_email, blocked, throttled, send_failed"),
    c("password_reset_done",  "Пароль изменён по ссылке из письма",                             ""),
    c("password_reset_failed","Неверная или просроченная ссылка восстановления пароля",         ""),
    c("email_changed",        "Администратор указал, сменил или удалил email пользователя",     "логин пользователя"),
    c("weak_password_set",    "Принят слабый пароль (режим password_policy = \"warn\")",        "логин и причина: password_common, password_equals_login, password_repeated")
  )

  data.frame(
    event = vapply(catalog, `[`, character(1), 1),
    description = vapply(catalog, `[`, character(1), 2),
    value = vapply(catalog, `[`, character(1), 3),
    stringsAsFactors = FALSE
  )
}
