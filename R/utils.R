#' Проверка числового параметра настроек
#'
#' @param x Значение.
#' @param name Название параметра для сообщения об ошибке.
#' @param whole Требовать целое число.
#' @param call Окружение для сообщения об ошибке.
#'
#' @returns Значение (невидимо), либо ошибка класса `appauth_error_settings`.
#' @noRd
aa_check_positive <- function(x, name, whole = TRUE, call = rlang::caller_env()) {
  ok <- is.numeric(x) && length(x) == 1 && is.finite(x) && x > 0 &&
    (!whole || x == round(x))

  if (!ok) {
    rlang::abort(
      paste0(
        "Параметр `", name, "` должен быть ",
        if (whole) "целым " else "",
        "положительным числом."
      ),
      class = "appauth_error_settings",
      call = call
    )
  }

  invisible(x)
}

#' Проверка логического параметра настроек
#'
#' @inheritParams aa_check_positive
#'
#' @returns Значение (невидимо), либо ошибка класса `appauth_error_settings`.
#' @noRd
aa_check_flag <- function(x, name, call = rlang::caller_env()) {
  if (!(is.logical(x) && length(x) == 1 && !is.na(x))) {
    rlang::abort(
      paste0("Параметр `", name, "` должен быть TRUE или FALSE."),
      class = "appauth_error_settings",
      call = call
    )
  }

  invisible(x)
}

#' Дата из базы в местном времени для показа
#'
#' В базе даты хранятся по UTC текстом `"ГГГГ-ММ-ДД ЧЧ:ММ:СС"`.
#'
#' @param x Вектор дат из базы (текст или `NA`).
#' @param missing Текст для пустых значений.
#'
#' @returns Вектор строк `"ГГГГ-ММ-ДД ЧЧ:ММ"` в часовом поясе сервера.
#' @noRd
aa_format_db_time <- function(x, missing = "") {
  x <- as.character(x)
  parsed <- as.POSIXct(x, tz = "UTC", format = "%Y-%m-%d %H:%M:%S")
  tz <- Sys.timezone()
  out <- format(parsed, "%Y-%m-%d %H:%M", tz = if (is.na(tz)) "" else tz)
  out[is.na(parsed)] <- missing
  out
}

#' Одна ли это непустая строка
#'
#' @param x Значение.
#'
#' @returns `TRUE` или `FALSE`.
#' @noRd
aa_is_string <- function(x) {
  is.character(x) && length(x) == 1 && !is.na(x) && nzchar(x)
}
