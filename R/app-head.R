#' Attach appauth styles and scripts
#'
#' Call it once in the application UI (inside `fluidPage()` or `tagList()`).
#' Adds the CSS of the sign-in form and the users tab, and the JS that reads,
#' writes and deletes the auto sign-in cookie.
#'
#' The look is changed with `--aa-*` CSS variables (for example `--aa-primary`),
#' which you override in your own CSS after `aa_app_head()`. The light theme is
#' enabled with the `aa-theme-light` class on `<body>` or a parent element.
#'
#' The cookie is written with `SameSite=Lax`, and on HTTPS also with `Secure`.
#'
#' @returns A `shiny.tag.list` object that attaches the `appauth` dependency.
#' @export
#'
#' @examples
#' ui <- shiny::fluidPage(
#'   aa_app_head()
#'   # ... the rest of the application UI
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
