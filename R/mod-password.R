#' Own password change module: UI
#'
#' A form with "current password, new password, confirmation". Shown only to a
#' signed-in user. Place it wherever the app has an account page or
#' settings (in a tab or a modal window). Styles are attached through
#' [aa_app_head()].
#'
#' @param id Module id.
#'
#' @returns A Shiny UI element.
#' @seealso [aa_password_server()]
#' @export
#'
#' @examples
#' ui <- shiny::fluidPage(aa_app_head(), aa_password_ui("password"))
aa_password_ui <- function(id) {
  shiny::uiOutput(shiny::NS(id, "form"))
}

#' Own password change module: server
#'
#' The user confirms the current password and sets a new one
#' ([aa_change_own_password()]).
#' Auto-login tokens of the other sessions are revoked, the current session
#' keeps
#' working. The module reports the change to the `on_event` hook with the
#' `password_changed` event.
#'
#' @param id Module id, the same as in [aa_password_ui()].
#' @param conn Database connection.
#' @param auth Authentication object, the result of [aa_auth_server()].
#' @param settings Settings, the result of [aa_settings()].
#' @param on_event Event hook `function(event, user, session_id, value)` or
#' `NULL`.
#'
#' @returns A list with the reactive value `changed`: the number of successful
#' password changes in
#'   this session (can be used to close a window or show a message).
#' @seealso [aa_password_ui()]
#' @export
#'
#' @examples
#' \dontrun{
#' auth <- aa_auth_server("auth", conn)
#' aa_password_server("password", conn, auth, on_event = log_event)
#' }
aa_password_server <- function(
  id,
  conn,
  auth,
  settings = aa_settings(),
  on_event = NULL
) {
  aa_check_conn(conn)

  shiny::moduleServer(id, function(input, output, session) {
    changed <- shiny::reactiveVal(0)
    message_text <- shiny::reactiveVal("")
    # form redraw counter: fields are cleared after a successful change
    form_version <- shiny::reactiveVal(0)

    output$form <- shiny::renderUI({
      form_version()
      shiny::req(auth$user())
      ns <- session$ns

      shiny::div(
        class = "aa-password",
        shiny::h4(aa_text(settings, "password_change_title")),
        shiny::passwordInput(
          ns("old"),
          aa_text(settings, "password_old_label")
        ),
        shiny::passwordInput(
          ns("new"),
          aa_text(settings, "password_new_label")
        ),
        shiny::passwordInput(
          ns("confirm"),
          aa_text(settings, "password_confirm_label")
        ),
        shiny::actionButton(
          ns("change"),
          aa_text(settings, "password_change_button"),
          class = "btn btn-primary"
        ),
        shiny::div(class = "aa-login-message", shiny::textOutput(ns("message")))
      )
    })

    output$message <- shiny::renderText(message_text())
    shiny::outputOptions(output, "message", suspendWhenHidden = FALSE)

    shiny::observeEvent(input$change, {
      user <- shiny::isolate(auth$user())
      shiny::req(user)

      if (!identical(input$new, input$confirm)) {
        message_text(aa_text(settings, "passwords_mismatch"))
        return()
      }

      token <- if (is.function(auth$token)) auth$token() else NULL
      new_password <- input$new

      ok <- tryCatch(
        {
          aa_change_own_password(
            conn,
            user$login,
            input$old,
            input$new,
            settings,
            keep_token = token
          )
          TRUE
        },
        appauth_error_user = function(e) {
          message_text(conditionMessage(e))
          FALSE
        }
      )

      if (ok) {
        aa_emit(on_event, "password_changed", user$login, session$token)
        message_text("")
        form_version(form_version() + 1)
        changed(changed() + 1)
        shiny::showNotification(
          aa_text(settings, "done_password_changed"),
          type = "message"
        )

        # with password_policy = "warn" a weak password is accepted, but we report it
        weak <- aa_password_warning(new_password, settings, user$login)
        if (!is.null(weak)) {
          aa_emit(
            on_event,
            "weak_password_set",
            user$login,
            session$token,
            paste0(user$login, ": ", weak$reason)
          )
          shiny::showNotification(weak$text, type = "warning")
        }
      }
    })

    list(changed = shiny::reactive(changed()))
  })
}
