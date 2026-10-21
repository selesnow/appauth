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
