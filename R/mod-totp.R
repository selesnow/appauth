#' Two-factor authentication module: UI
#'
#' A block for the account page: the two-factor authentication status, enabling
#' (secret, QR code and confirmation with a code) and disabling. Shows nothing
#' until `totp_enabled` is set in the settings. Styles are attached through
#' [aa_app_head()].
#'
#' @param id Module id.
#'
#' @returns A Shiny UI element.
#' @seealso [aa_totp_server()]
#' @export
#'
#' @examples
#' ui <- shiny::fluidPage(aa_app_head(), aa_totp_ui("totp"))
aa_totp_ui <- function(id) {
  shiny::uiOutput(shiny::NS(id, "main"))
}

# QR code for an otpauth link
#
# Needs the optional `qrcode` package. If it is missing or the code could not
# be built, `NULL` is returned and the user enters the key manually.
#
# @param uri An `otpauth://` link.
#
# @returns HTML with SVG or `NULL`.
# @noRd
aa_totp_qr_html <- function(uri) {
  if (!requireNamespace("qrcode", quietly = TRUE)) {
    return(NULL)
  }

  tryCatch(
    {
      path <- tempfile(fileext = ".svg")
      on.exit(unlink(path), add = TRUE)
      qrcode::generate_svg(qrcode::qr_code(uri), path)
      htmltools::HTML(paste(readLines(path, warn = FALSE), collapse = ""))
    },
    error = function(e) NULL
  )
}

# Button that copies text to the clipboard
#
# The text is stored in the `data-copy` attribute and copied by the script from
# [aa_app_head()] (over
# HTTPS through the browser clipboard, otherwise through a hidden field). The
# text is already visible on the page,
# so the button reveals nothing new.
#
# @param text What to copy.
# @param settings Settings (button texts).
#
# @returns A Shiny UI element.
# @noRd
aa_copy_button <- function(text, settings) {
  shiny::tags$button(
    type = "button",
    class = "btn btn-default btn-sm aa-copy",
    `data-copy` = text,
    `data-done` = aa_text(settings, "copy_done"),
    shiny::icon("copy"),
    " ",
    aa_text(settings, "copy_button")
  )
}

#' Two-factor authentication module: server
#'
#' The user enables and disables two-factor authentication (TOTP) on their own:
#'
#' * **enabling**: a button creates a secret ([aa_totp_setup()]), shows a QR
#' code
#'   (if the `qrcode` package is installed) and a key for manual entry, and
#'   after a code
#'   from the authenticator app is entered ([aa_totp_enable()]) turns protection
#'   on and shows
#'   10 recovery codes **once**. The user's other sessions are ended on
#'   enabling;
#' * **disabling**: needs the password and a code (or a recovery code),
#' otherwise whoever
#'   took over an open session could remove the protection.
#'
#' Wrong codes count as failed login attempts ([aa_record_attempt()]),
#' so guessing a code on the account page locks the login the same way as
#' guessing
#' a password. Events: `totp_enabled`, `totp_disabled`, `totp_failed`.
#'
#' @param id Module id, the same as in [aa_totp_ui()].
#' @param conn Database connection.
#' @param auth Authentication object, the result of [aa_auth_server()].
#' @param settings Settings, the result of [aa_settings()] with `totp_enabled =
#' TRUE`.
#' @param on_event Event hook `function(event, user, session_id, value)` or
#' `NULL`.
#'
#' @returns A list with a `refresh()` function that redraws the block.
#' @seealso [aa_totp_ui()], [aa_auth_server()]
#' @export
#'
#' @examples
#' \dontrun{
#' auth <- aa_auth_server("auth", conn, settings)
#' shiny::observe({
#'   if (auth$logged_in()) aa_totp_server("totp", conn, auth, settings, on_event
#'   = log_event)
#' })
#' }
aa_totp_server <- function(
  id,
  conn,
  auth,
  settings = aa_settings(),
  on_event = NULL
) {
  aa_check_conn(conn)

  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    version <- shiny::reactiveVal(0)
    enrolling <- shiny::reactiveVal(NULL)
    message_text <- shiny::reactiveVal("")

    acting_login <- function() shiny::isolate(auth$user())$login

    emit <- function(event, value = NULL) {
      aa_emit(on_event, event, acting_login(), session$token, value)
    }

    notify <- function(text, type = "message") {
      shiny::showNotification(text, type = type)
    }

    # guessing a code on the account page locks the login the same way as guessing a password
    gate_open <- function(login) {
      gate <- aa_login_gate(conn, login, settings)

      if (!gate$allowed) {
        message_text(gate$message)
      }

      gate$allowed
    }

    wrong <- function(login) {
      try(
        aa_record_attempt(conn, login, success = FALSE, settings = settings),
        silent = TRUE
      )
      emit("totp_failed")
    }

    output$main <- shiny::renderUI({
      auth$user() # dependency: the UI is redrawn after sign-in or sign-out
      version()

      login <- acting_login()

      if (!isTRUE(settings$totp_enabled) || !aa_is_string(login)) {
        return(NULL)
      }

      enabled <- aa_totp_enabled(conn, login)

      body <- if (enabled) {
        shiny::tagList(
          shiny::p(
            shiny::span(
              aa_text(settings, "totp_status_on"),
              class = "aa-status-ok"
            ),
            ". ",
            aa_text(
              settings,
              "totp_recovery_left",
              aa_recovery_codes_left(conn, login)
            )
          ),
          shiny::h5(aa_text(settings, "totp_disable_title")),
          shiny::passwordInput(
            ns("disable_password"),
            aa_text(settings, "password_label")
          ),
          shiny::textInput(
            ns("disable_code"),
            aa_text(settings, "totp_code_label")
          ),
          shiny::actionButton(
            ns("disable_btn"),
            aa_text(settings, "totp_disable_button"),
            class = "btn btn-danger"
          )
        )
      } else if (is.null(enrolling())) {
        shiny::tagList(
          shiny::p(aa_text(settings, "totp_status_off")),
          shiny::actionButton(
            ns("start"),
            aa_text(settings, "totp_enable_button"),
            class = "btn btn-success"
          )
        )
      } else {
        setup <- enrolling()
        qr <- aa_totp_qr_html(setup$uri)

        shiny::tagList(
          shiny::p(
            class = "aa-login-hint",
            aa_text(settings, "totp_setup_hint")
          ),
          if (!is.null(qr)) {
            shiny::div(class = "aa-totp-qr", style = "max-width: 220px;", qr)
          },
          shiny::p(
            aa_text(settings, "totp_secret_label"),
            ": ",
            shiny::tags$code(gsub("(.{4})", "\\1 ", setup$secret)),
            " ",
            aa_copy_button(setup$secret, settings)
          ),
          shiny::textInput(ns("code"), aa_text(settings, "totp_code_label")),
          shiny::actionButton(
            ns("confirm"),
            aa_text(settings, "totp_confirm_button"),
            class = "btn btn-success"
          ),
          " ",
          shiny::actionButton(
            ns("cancel"),
            aa_text(settings, "button_cancel"),
            class = "btn btn-default"
          )
        )
      }

      shiny::div(
        class = "aa-totp",
        shiny::h4(aa_text(settings, "totp_section")),
        body,
        shiny::div(class = "aa-login-message", shiny::textOutput(ns("message")))
      )
    })

    output$message <- shiny::renderText(message_text())
    shiny::outputOptions(output, "message", suspendWhenHidden = FALSE)

    shiny::observeEvent(input$start, {
      login <- acting_login()
      shiny::req(aa_is_string(login))
      message_text("")

      setup <- tryCatch(
        aa_totp_setup(conn, login, settings),
        appauth_error_user = function(e) {
          message_text(conditionMessage(e))
          NULL
        }
      )

      enrolling(setup)
      version(version() + 1)
    })

    shiny::observeEvent(input$cancel, {
      enrolling(NULL)
      message_text("")
      version(version() + 1)
    })

    shiny::observeEvent(input$confirm, {
      login <- acting_login()
      shiny::req(aa_is_string(login), enrolling())
      message_text("")

      if (!gate_open(login)) {
        return()
      }

      codes <- tryCatch(
        aa_totp_enable(conn, login, input$code, settings),
        appauth_error_user = function(e) {
          if (identical(e$reason, "totp_wrong")) {
            wrong(login)
          }
          message_text(conditionMessage(e))
          NULL
        }
      )

      if (is.null(codes)) {
        return()
      }

      # enabling 2FA ends the other sessions: the current token stays
      keep <- auth$token()
      aa_revoke_user_tokens(
        conn,
        login,
        keep_hash = if (aa_is_string(keep)) aa_token_hash(keep) else NULL
      )

      enrolling(NULL)
      emit("totp_enabled")
      notify(aa_text(settings, "done_totp_enabled"))
      version(version() + 1)

      shiny::showModal(shiny::modalDialog(
        title = aa_text(settings, "totp_recovery_title"),
        size = "s",
        easyClose = FALSE,
        footer = shiny::modalButton(aa_text(settings, "button_close")),
        shiny::p(aa_text(settings, "totp_recovery_hint")),
        shiny::tags$pre(class = "aa-totp-codes", paste(codes, collapse = "\n")),
        aa_copy_button(paste(codes, collapse = "\n"), settings)
      ))
    })

    shiny::observeEvent(input$disable_btn, {
      login <- acting_login()
      shiny::req(aa_is_string(login))
      message_text("")

      if (!gate_open(login)) {
        return()
      }

      # the code is checked only with the right password: otherwise someone else's attempt would burn recovery codes
      password_ok <- !is.null(aa_authenticate(
        conn,
        login,
        input$disable_password
      ))
      code_ok <- password_ok &&
        isTRUE(
          aa_verify_second_factor(conn, login, input$disable_code, settings)$ok
        )

      if (!code_ok) {
        wrong(login)
        message_text(aa_text(settings, "totp_disable_wrong"))
        return()
      }

      aa_totp_disable(conn, login)
      emit("totp_disabled")
      notify(aa_text(settings, "done_totp_disabled"))
      version(version() + 1)
    })

    list(refresh = function() version(shiny::isolate(version()) + 1))
  })
}
