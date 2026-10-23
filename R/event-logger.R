#' Готовый обработчик событий для записи в журнал
#'
#' Пакет сообщает о событиях функции `on_event(event, user, session_id, value)`
#' (каталог: [aa_events()]). Эта функция собирает такой обработчик из функции
#' записи `writer`, чтобы приложению не нужно было каждый раз писать одно и то
#' же: отбор нужных событий, названия действий для вашего журнала, включение и
#' выключение записи и преобразование значения.
#'
#' Что делает обработчик на каждое событие:
#'
#' 1. пропускает событие, которого нет в `events` (если `events` задан) или у
#'    которого нет названия в `actions` (если `actions` задан);
#' 2. спрашивает `enabled`: если запись выключена, ничего не пишет;
#' 3. определяет название действия: из `actions`, а если `actions` не задан, это
#'    ключ события;
#' 4. вызывает `writer(action, user, session_id, value)`, где `value` прошло через
#'    `format_value(event, user, value)`, если функция задана.
#'
#' Ошибка в `writer` не прерывает действие пакета (её перехватывает пакет и
#' выводит сообщением), поэтому сбой журнала не мешает входу и работе
#' пользователей.
#'
#' @param writer Функция записи `function(action, user, session_id, value)`:
#'   пишет строку в вашу базу, файл, Telegram и т.д. Все четыре аргумента строки.
#' @param actions Именованный вектор строк: имя это ключ события из
#'   [aa_events()], значение это название действия в вашем журнале. Если задан,
#'   пишутся только перечисленные события. Если `NULL`, пишутся все события, а
#'   названием действия служит ключ события.
#' @param events Вектор ключей событий, которые нужно писать. Если `NULL`, берутся
#'   все (или перечисленные в `actions`).
#' @param enabled Включена ли запись: `TRUE`, `FALSE` или функция
#'   `function(event)`, которая решает по событию (например, по переключателям из
#'   конфига). Функция вызывается при каждом событии, поэтому изменения
#'   конфига действуют сразу.
#' @param format_value Необязательная функция `function(event, user, value)`,
#'   которая возвращает значение для записи (например, оставляет в `value` только
#'   логин). По умолчанию `value` записывается как есть.
#'
#' @returns Функция `function(event, user, session_id, value)`, которую нужно
#'   передать в `on_event` модулей пакета.
#' @export
#'
#' @examples
#' # все события в память
#' rows <- list()
#' handler <- aa_event_logger(function(action, user, session_id, value) {
#'   rows[[length(rows) + 1]] <<- c(action = action, user = user, value = value)
#' })
#' handler("login_failed", "boss", "s1", "")
#' length(rows)
#'
#' # только выбранные события со своими названиями действий и переключателем
#' log_on <- TRUE
#' handler <- aa_event_logger(
#'   function(action, user, session_id, value) message(action, " ", user),
#'   actions = c(login_failed = "Login failed", user_added = "User add"),
#'   enabled = function(event) log_on
#' )
#' handler("login_failed", "boss", "s1", "")
#' handler("logout", "boss", "s1", "")
aa_event_logger <- function(writer, actions = NULL, events = NULL, enabled = TRUE,
                            format_value = NULL) {
  known <- aa_events()$event

  if (!is.function(writer)) {
    rlang::abort("`writer` должен быть функцией.", class = "appauth_error_settings")
  }

  if (!is.null(actions)) {
    if (!(is.character(actions) && length(actions) >= 1 && !anyNA(actions) &&
          !is.null(names(actions)) && all(nzchar(names(actions))) && all(nzchar(actions)))) {
      rlang::abort(
        "`actions` должен быть именованным вектором строк: имя это ключ события, значение название действия.",
        class = "appauth_error_settings"
      )
    }

    unknown <- setdiff(names(actions), known)
    if (length(unknown) > 0) {
      rlang::abort(
        paste0("В `actions` есть неизвестные события: ", paste(unknown, collapse = ", "), ". Список: aa_events()$event."),
        class = "appauth_error_settings"
      )
    }
  }

  if (!is.null(events)) {
    if (!(is.character(events) && !anyNA(events))) {
      rlang::abort("`events` должен быть вектором строк или `NULL`.", class = "appauth_error_settings")
    }

    unknown <- setdiff(events, known)
    if (length(unknown) > 0) {
      rlang::abort(
        paste0("В `events` есть неизвестные события: ", paste(unknown, collapse = ", "), ". Список: aa_events()$event."),
        class = "appauth_error_settings"
      )
    }
  }

  if (!(is.function(enabled) || (is.logical(enabled) && length(enabled) == 1 && !is.na(enabled)))) {
    rlang::abort("`enabled` должен быть TRUE, FALSE или функцией `function(event)`.", class = "appauth_error_settings")
  }

  if (!(is.null(format_value) || is.function(format_value))) {
    rlang::abort("`format_value` должен быть функцией или `NULL`.", class = "appauth_error_settings")
  }

  function(event, user, session_id, value) {
    if (!is.null(events) && !event %in% events) {
      return(invisible(FALSE))
    }

    action <- if (is.null(actions)) event else unname(actions[event])
    if (is.na(action)) {
      return(invisible(FALSE))
    }

    on <- if (is.function(enabled)) enabled(event) else enabled
    if (!isTRUE(on)) {
      return(invisible(FALSE))
    }

    if (is.function(format_value)) {
      value <- format_value(event, user, value)
    }

    writer(action, user, session_id, value)
    invisible(TRUE)
  }
}
