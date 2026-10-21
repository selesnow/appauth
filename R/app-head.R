#' Подключить стили и скрипты appauth
#'
#' Нужно вызвать один раз в интерфейсе приложения (внутри `fluidPage()` или
#' `tagList()`). Добавляет CSS формы входа и вкладки пользователей и JS, который
#' читает, пишет и удаляет cookie автовхода.
#'
#' Оформление меняется CSS-переменными `--aa-*` (например `--aa-primary`),
#' которые нужно переопределить в своём CSS после `aa_app_head()`. Светлая тема
#' включается классом `aa-theme-light` на `<body>` или родительском элементе.
#'
#' Cookie пишется с `SameSite=Lax`, а на HTTPS ещё и с `Secure`.
#'
#' @returns Объект `shiny.tag.list`, который подключает зависимость `appauth`.
#' @export
#'
#' @examples
#' ui <- shiny::fluidPage(
#'   aa_app_head()
#'   # ... остальной интерфейс приложения
#' )
aa_app_head <- function() {
  htmltools::tagList(
    htmltools::htmlDependency(
      name = "appauth",
      version = as.character(utils::packageVersion("appauth")),
      src = system.file("www", package = "appauth"),
      script = "appauth.js",
      stylesheet = "appauth.css"
    )
  )
}
