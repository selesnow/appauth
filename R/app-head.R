#' Attach appauth styles and scripts
#'
#' Call it once in the application UI (inside `fluidPage()` or `tagList()`).
#' Adds the CSS of the sign-in form and the users tab, and the JS that handles
#' the server-side auto sign-in cookie tickets (plus legacy cookie handlers).
#'
#' The look is changed with `--aa-*` CSS variables (for example `--aa-primary`),
#' which you override in your own CSS after `aa_app_head()`. The light theme is
#' enabled with the `aa-theme-light` class on `<body>` or a parent element.
#'
#' With `cookie_mode = "httponly"` the cookie is written by the server with
#' `HttpOnly`, `SameSite=Lax` and `Secure` on HTTPS. The legacy mode uses the
#' same flags except for `HttpOnly`.
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
  aa_register_cookie_handler()

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
