#' Sign-in module: UI
#'
#' The sign-in form (or the creation of the first administrator if there are
#' no users yet). When the user is signed in, the module shows nothing. Styles are attached
#' through [aa_app_head()].
#'
#' @param id Module id.
#'
#' @returns A Shiny UI element.
#' @seealso [aa_auth_server()]
#' @export
#'
#' @examples
#' ui <- shiny::fluidPage(aa_app_head(), aa_auth_ui("auth"))
aa_auth_ui <- function(id) {
  shiny::uiOutput(shiny::NS(id, "form"))
}

#' Sign-in module: server
#'
#' Sign-in with login and password protected against guessing ([aa_login_gate()]), creation of the
#' first administrator on an empty database, auto-login by cookie (if enabled in the
#' settings) and sign-out. The module reports all events to the `on_event` hook
#' (catalog in [aa_events()]) and writes nothing to logs itself.
#'
#' If the password was set by an administrator (`must_change`), the password change form
#' is shown after the correct password is entered, and the user gets into the app
#' only after the change.
#'
#' @section Two-factor authentication:
#' With `totp_enabled = TRUE` in the settings ([aa_settings()]), a user who has
#' 2FA enabled ([aa_totp_server()]) enters, after the correct password, a code from the
#' authenticator app or a recovery code. Until then no auto-login token is
#' issued and the successful login attempt is not recorded: wrong codes count as
#' failed login attempts, and the login is locked by the same rules as for
#' password guessing. Auto-login by cookie does not ask for the second factor (the cookie
#' was issued after it was passed). The module reports the events `totp_failed` and
#' `recovery_code_used`.
#'
#' @section Password recovery by email:
#' With `reset_enabled = TRUE` in the settings ([aa_settings()]), a "Forgot password?"
#' link appears on the sign-in form. The user enters a login or email and is
#' sent an email with a link `<reset_base_url>/?reset=<token>`, and the on-screen answer is
#' always the same, whether or not the user was found. The module itself
#' reads the `reset` parameter from the address bar, removes it from the address and shows
#' the new password form if the link works. After the password is changed the user signs in
#' as usual: they are not signed in automatically. The module reports the events
#' `password_reset_requested`, `password_reset_done` and `password_reset_failed`.
#' Logic without UI: [aa_request_password_reset()] and
#' [aa_reset_password_with_token()].
#'
#' @section Sign-in with Google:
#' With `google_enabled = TRUE` in the settings ([aa_settings()]), a "Sign in with Google"
#' button appears on the sign-in form. The user confirms the sign-in with Google and returns
#' to `google_redirect_uri`; the package checks the signature and contents of the Google token, the organization
#' domain (`google_domains`) and finds the user **by email among already created ones**:
#' sign-in does not create new users, the role is taken from the database, a blocked
#' user does not get in. The two-factor code is not asked for in this case
#' (Google does the confirmation). `state` from the address is compared with a short cookie
#' of the browser that started the sign-in, so someone else's return link cannot be slipped in. With
#' `password_login = FALSE` the password form is hidden and password sign-in attempts are rejected
#' on the server. The module reports `login_success` with the value `google` and
#' `google_login_failed` (reason and email in `value`); on refusal the user
#' sees a generic text. If the page is opened not at the
#' `google_redirect_uri` address (for example, the app is opened by IP while the return is configured for a
#' domain), the button sends the user to the return address and sign-in starts there on its own
#' (parameter `?google=1`): `state` is stored in the cookie of the site address, and cookies for an IP and for a domain
#' are different. Password sign-in and cookie auto-login work independently at each address.
#'
#' The role and login are taken from the database, not from the entered string. The `conn`
#' connection belongs to the app: close it when the session ends.
#'
#' @param id Module id, the same as in [aa_auth_ui()].
#' @param conn Database connection with the [aa_init_db()] schema.
#' @param settings Settings, the result of [aa_settings()].
#' @param on_event Event hook `function(event, user, session_id, value)` or `NULL`.
#' @param title Sign-in form title. Defaults to the `login_title` text.
#' @param logo Address of an image above the title (for example `"logo.png"` from the
#'   `www` folder) or `NULL`.
#' @param cookie_name Auto-login cookie name. Cookies are not isolated by port,
#'   so apps on the same host need different names.
#'
#' @returns A list: `user` (reactive value, a list with `login` and `role` or
#'   `NULL`), `logged_in` (reactive logical), `role` (reactive role or
#'   `NULL`), a `token()` function (the auto-login token of this session or `NULL`, needed by
#'   [aa_session_guard()]), a `logout(reason = NULL, reload = FALSE)` function and
#'   a `logout_all(reload = TRUE)` function. Without `reason`
#'   this is an ordinary sign-out (event `logout`); with `reason` (`"blocked"`, `"deleted"`,
#'   `"role_changed"`, `"token_revoked"`) it is forced (`session_forced_logout`). With
#'   `reload = TRUE` the page is reloaded so that the modules of the previous user
#'   disappear.
#'
#'   `logout_all()` is "sign out on all devices": it revokes all tokens of the
#'   user (event `sessions_revoked`) and signs out immediately; open sessions on
#'   other devices are closed by [aa_session_guard()] at the next check. Show the user a
#'   confirmation dialog before calling it: the button kicks them out everywhere.
#' @seealso [aa_auth_ui()]
#' @export
#'
#' @examples
#' \dontrun{
#' server <- function(input, output, session) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), "app.db")
#'   aa_init_db(conn)
#'   session$onSessionEnded(function() DBI::dbDisconnect(conn))
#'
#'   auth <- aa_auth_server("auth", conn, on_event = log_event)
#'   output$app <- shiny::renderUI(if (auth$logged_in()) main_ui())
#' }
#' }
aa_auth_server <- function(id, conn, settings = aa_settings(), on_event = NULL,
                           title = NULL, logo = NULL, cookie_name = "appauth_token") {
  aa_check_conn(conn)

  shiny::moduleServer(id, function(input, output, session) {
    user <- shiny::reactiveVal(NULL)
    message_text <- shiny::reactiveVal("")
    current_token <- NULL
    # signed in with a password set by an administrator: not let into the app until it is changed
    pending <- shiny::reactiveVal(NULL)
    # the password is correct, waiting for the second factor code: list(login, role, must_change, old)
    second_factor <- shiny::reactiveVal(NULL)
    # which form is shown before sign-in: "login" or "forgot" (link request)
    mode <- shiny::reactiveVal("login")
    # token from the recovery link for which the new password form is shown
    reset_pending <- shiny::reactiveVal(NULL)
    # Google return parameters (code, state) while waiting for the browser cookie to compare
    google_callback <- shiny::reactiveVal(NULL)
    google_on <- isTRUE(settings$google_enabled)
    # settings are built by aa_settings(), but just in case a missing field does not disable the password
    password_on <- !identical(settings$password_login, FALSE)
    oauth_cookie <- paste0(cookie_name, "_oauth")

    users_exist <- shiny::reactiveVal(
      tryCatch(aa_users_exist(conn), error = function(e) TRUE)
    )

    emit <- function(event, login = NULL, value = NULL) {
      aa_emit(on_event, event, login, session$token, value)
    }

    # with password_policy = "warn" a weak password is accepted, but we report it
    warn_weak <- function(password, login) {
      weak <- aa_password_warning(password, settings, login)

      if (!is.null(weak)) {
        emit("weak_password_set", login, paste0(login, ": ", weak$reason))
        shiny::showNotification(weak$text, type = "warning")
      }
    }

    finish_login <- function(login, role, issue_token = TRUE) {
      message_text("")
      user(list(login = login, role = role))

      if (issue_token) {
        # password sign-in (including after a mandatory password change and creation of the
        # first administrator); cookie sign-in does not update the date
        aa_touch_last_login(conn, login)

        token <- tryCatch(
          aa_issue_token(conn, login, settings),
          error = function(e) {
            message("appauth: could not issue an auto-login token: ", conditionMessage(e))
            NULL
          }
        )

        if (!is.null(token)) {
          current_token <<- token
          session$sendCustomMessage(
            "appauth_set_cookie",
            list(name = cookie_name, token = token, days = settings$session_days)
          )
        }
      }
    }

    # password recovery link from the email: ?reset=<token>
    if (isTRUE(settings$reset_enabled) && password_on) {
      shiny::observeEvent(aa_url_search(session), {
        token <- shiny::parseQueryString(aa_url_search(session))[["reset"]]

        if (!aa_is_string(token) || !is.null(shiny::isolate(user()))) {
          return()
        }

        # the token must not stay in the address: it would end up in history and bookmarks
        shiny::updateQueryString("?", mode = "replace", session = session)

        login <- tryCatch(aa_reset_token_login(conn, token), error = function(e) NULL)

        if (is.null(login)) {
          message_text(aa_text(settings, "reset_link_invalid"))
          emit("password_reset_failed")
        } else {
          message_text("")
          reset_pending(token)
        }
      }, once = TRUE)
    }

    # auto-login by cookie
    if (isTRUE(settings$autologin)) {
      session$onFlushed(function() {
        session$sendCustomMessage(
          "appauth_read_cookie",
          list(name = cookie_name, input = session$ns("cookie"))
        )
      }, once = TRUE)

      shiny::observeEvent(input$cookie, {
        if (!is.null(shiny::isolate(user())) || !aa_is_string(input$cookie)) {
          return()
        }

        found <- tryCatch(aa_find_session_user(conn, input$cookie), error = function(e) NULL)

        if (is.null(found)) {
          # the token is expired, revoked or belongs to a blocked user: remove the cookie
          session$sendCustomMessage("appauth_clear_cookie", list(name = cookie_name))
          return()
        }

        current_token <<- input$cookie
        finish_login(found$login, found$role, issue_token = FALSE)
        emit("login_success", found$login, "cookie")
      })
    }

    # sign-in with Google ------------------------------------------------------------
    google_fail <- function(reason, email = NULL) {
      message_text(aa_text(settings, aa_google_text_key(reason)))
      emit("google_login_failed", NULL, paste(c(reason, if (aa_is_string(email)) email), collapse = " "))
    }

    if (google_on) {
      # remember state in this browser's cookie and send it to Google
      start_google <- function() {
        if (!is.null(shiny::isolate(user()))) {
          return()
        }

        started <- tryCatch(
          aa_google_start(conn, settings),
          error = function(e) {
            message("appauth: could not start sign-in with Google: ", conditionMessage(e))
            NULL
          }
        )

        if (is.null(started)) {
          google_fail("start_failed")
          return()
        }

        message_text("")
        session$sendCustomMessage(
          "appauth_set_cookie",
          list(name = oauth_cookie, token = started$state, days = 600 / 86400)
        )
        aa_redirect(session, started$url, "https://accounts.google.com")
      }

      # the button. state is stored in the cookie of the address the page is opened from, and Google returns
      # the user to google_redirect_uri: from a page at another address (for example, by IP) sign-in
      # must be started at the return address, and the button sends the user there (sign-in starts there on its own)
      shiny::observeEvent(input$google_btn, {
        if (!is.null(shiny::isolate(user()))) {
          return()
        }

        if (!aa_page_matches(session, settings$google_redirect_uri)) {
          message_text("")
          aa_redirect(
            session, aa_google_hop_url(settings),
            aa_origin_string(aa_url_origin(settings$google_redirect_uri))
          )
          return()
        }

        start_google()
      })

      # return from Google: ?code=...&state=... (or ?error=... if the user refused)
      shiny::observeEvent(aa_url_search(session), {
        query <- shiny::parseQueryString(aa_url_search(session))
        code <- query[["code"]]
        state <- query[["state"]]

      # redirect from the button at another address (by IP): start sign-in at once, without a second click.
      # The address is not compared here, otherwise a wrong address detection would cause an endless redirect
        if (identical(query[["google"]], "1") && !aa_is_string(code) && !aa_is_string(state) &&
            is.null(shiny::isolate(user()))) {
          shiny::updateQueryString("?", mode = "replace", session = session)
          start_google()
          return()
        }

        if (!is.null(shiny::isolate(user())) || !aa_is_string(state) ||
            !(aa_is_string(code) || aa_is_string(query[["error"]]))) {
          return()
        }

        # code and state must not stay in the address bar
        shiny::updateQueryString("?", mode = "replace", session = session)

        if (!aa_is_string(code)) {
          google_fail("cancelled")
          return()
        }

        google_callback(list(code = code, state = state))
        session$sendCustomMessage("appauth_read_cookie", list(name = oauth_cookie, input = session$ns("oauth_cookie")))
      }, once = TRUE)

      # the browser cookie must match state from the address: this way sign-in finishes
      # only in the browser that started it
      shiny::observeEvent(input$oauth_cookie, {
        callback <- shiny::isolate(google_callback())
        shiny::req(callback)
        google_callback(NULL)
        session$sendCustomMessage("appauth_clear_cookie", list(name = oauth_cookie))

        if (!is.null(shiny::isolate(user()))) {
          return()
        }

        if (!aa_is_string(input$oauth_cookie) || !identical(input$oauth_cookie, callback$state)) {
          google_fail("bad_browser")
          return()
        }

        res <- aa_google_complete(conn, settings, callback$code, callback$state)

        if (!isTRUE(res$ok)) {
          google_fail(res$reason, res$email)
          return()
        }

        finish_login(res$login, res$role)
        emit("login_success", res$login, "google")
      }, ignoreNULL = FALSE, ignoreInit = TRUE)
    }

    logout <- function(reason = NULL, reload = FALSE) {
      login <- shiny::isolate(user())$login

      if (!is.null(current_token)) {
        try(aa_revoke_token(conn, current_token), silent = TRUE)
      }
      current_token <<- NULL
      session$sendCustomMessage("appauth_clear_cookie", list(name = cookie_name))

      if (is.null(reason)) {
        emit("logout", login)
      } else {
        emit("session_forced_logout", login, reason)
      }

      message_text("")
      user(NULL)
      users_exist(tryCatch(aa_users_exist(conn), error = function(e) TRUE))

      if (isTRUE(reload)) {
        session$reload()
      }

      invisible(TRUE)
    }

    # sign out on all devices: all tokens of the user are revoked (the other
    # sessions are closed by the aa_session_guard() guard at the next check) and the
    # current session signs out at once
    logout_all <- function(reload = TRUE) {
      login <- shiny::isolate(user())$login

      if (!aa_is_string(login)) {
        return(invisible(FALSE))
      }

      try(aa_revoke_sessions(conn, login), silent = TRUE)
      emit("sessions_revoked", login, login)

      logout(reload = reload)
    }

    output$form <- shiny::renderUI({
      if (!is.null(user())) {
        return(NULL)
      }

      ns <- session$ns
      hint <- NULL

      fields <- if (!is.null(second_factor())) {
        heading <- aa_text(settings, "totp_title")
        hint <- shiny::tags$p(class = "aa-login-hint", aa_text(settings, "totp_hint"))
        shiny::tagList(
          shiny::textInput(ns("totp_code"), aa_text(settings, "totp_code_label")),
          shiny::actionButton(ns("totp_btn"), aa_text(settings, "totp_button"), class = "aa-login-button"),
          shiny::div(class = "aa-login-message", shiny::textOutput(ns("message"))),
          shiny::div(class = "aa-login-hint", shiny::actionLink(ns("back_link"), aa_text(settings, "back_to_login")))
        )
      } else if (!is.null(pending())) {
        heading <- aa_text(settings, "must_change_title")
        hint <- shiny::tags$p(class = "aa-login-hint", aa_text(settings, "must_change_hint"))
        shiny::tagList(
          shiny::passwordInput(ns("change_password"), aa_text(settings, "password_new_label")),
          shiny::passwordInput(ns("change_confirm"), aa_text(settings, "password_confirm_label")),
          shiny::actionButton(ns("change_btn"), aa_text(settings, "password_change_button"), class = "aa-login-button"),
          shiny::div(class = "aa-login-message", shiny::textOutput(ns("message")))
        )
      } else if (!is.null(reset_pending())) {
        heading <- aa_text(settings, "reset_title")
        hint <- shiny::tags$p(class = "aa-login-hint", aa_text(settings, "reset_hint"))
        shiny::tagList(
          shiny::passwordInput(ns("reset_password"), aa_text(settings, "password_new_label")),
          shiny::passwordInput(ns("reset_confirm"), aa_text(settings, "password_confirm_label")),
          shiny::actionButton(ns("reset_btn"), aa_text(settings, "reset_save_button"), class = "aa-login-button"),
          shiny::div(class = "aa-login-message", shiny::textOutput(ns("message"))),
          shiny::div(class = "aa-login-hint", shiny::actionLink(ns("back_link"), aa_text(settings, "back_to_login")))
        )
      } else if (users_exist() && identical(mode(), "forgot") && isTRUE(settings$reset_enabled)) {
        heading <- aa_text(settings, "forgot_title")
        hint <- shiny::tags$p(class = "aa-login-hint", aa_text(settings, "forgot_hint"))
        shiny::tagList(
          shiny::textInput(ns("forgot_identifier"), aa_text(settings, "forgot_identifier_label")),
          shiny::actionButton(ns("forgot_btn"), aa_text(settings, "forgot_button"), class = "aa-login-button"),
          shiny::div(class = "aa-login-message", shiny::textOutput(ns("message"))),
          shiny::div(class = "aa-login-hint", shiny::actionLink(ns("back_link"), aa_text(settings, "back_to_login")))
        )
      } else if (users_exist()) {
        heading <- title %||% aa_text(settings, "login_title")
        shiny::tagList(
          if (password_on) {
            shiny::tagList(
              shiny::textInput(ns("login"), aa_text(settings, "login_label")),
              shiny::passwordInput(ns("password"), aa_text(settings, "password_label")),
              shiny::actionButton(ns("login_btn"), aa_text(settings, "login_button"), class = "aa-login-button")
            )
          },
          if (google_on) {
            shiny::tagList(
              if (password_on) shiny::div(class = "aa-login-or", aa_text(settings, "google_or")),
              shiny::actionButton(
                ns("google_btn"),
                shiny::tagList(aa_google_icon(), aa_text(settings, "google_button")),
                class = "aa-login-button aa-google-button"
              )
            )
          },
          shiny::div(class = "aa-login-message", shiny::textOutput(ns("message"))),
          if (isTRUE(settings$reset_enabled) && password_on) {
            shiny::div(class = "aa-login-hint", shiny::actionLink(ns("forgot_link"), aa_text(settings, "forgot_link")))
          }
        )
      } else {
        heading <- aa_text(settings, "setup_title")
        hint <- shiny::tags$p(class = "aa-login-hint", aa_text(settings, "setup_hint", settings$admin_role))
        shiny::tagList(
          shiny::textInput(ns("setup_login"), aa_text(settings, "login_label")),
          shiny::passwordInput(ns("setup_password"), aa_text(settings, "password_label")),
          shiny::passwordInput(ns("setup_confirm"), aa_text(settings, "password_confirm_label")),
          shiny::actionButton(ns("setup_btn"), aa_text(settings, "setup_button"), class = "aa-login-button"),
          shiny::div(class = "aa-login-message", shiny::textOutput(ns("message")))
        )
      }

      shiny::div(
        class = "aa-login",
        shiny::div(
          class = "aa-login-card",
          if (!is.null(logo)) shiny::tags$img(src = logo, class = "aa-login-logo"),
          shiny::tags$h2(class = "aa-login-title", heading),
          hint,
          fields
        )
      )
    })

    output$message <- shiny::renderText(message_text())
    shiny::outputOptions(output, "message", suspendWhenHidden = FALSE)

    shiny::observeEvent(input$login_btn, {
      login <- input$login
      password <- input$password

      # server-side protection: a hidden form is not a substitute for a check
      if (!password_on) {
        message_text(aa_text(settings, "password_login_disabled"))
        emit("login_failed", NULL, "password_disabled")
        return()
      }

      if (!aa_is_string(login) || !aa_is_string(password)) {
        message_text(aa_text(settings, "bad_credentials"))
        return()
      }

      # blocked login and the general limit: the password is not checked and the attempt is not
      # recorded, so that the block is not extended
      gate <- aa_login_gate(conn, login, settings)
      if (!gate$allowed) {
        message_text(gate$message)
        emit(if (gate$reason == "throttled") "login_throttled" else "login_locked", login, gate$seconds)
        return()
      }

      res <- aa_authenticate(conn, login, password)

      if (!is.null(res) && isTRUE(res$blocked[1] == 1)) {
        # the password is correct but the account is blocked: this is reported only
        # to someone who knows the password, so as not to reveal the list of logins
        message_text(aa_text(settings, "blocked_user"))
        emit("login_blocked_user", login)
        return()
      }

      if (!is.null(res) && isTRUE(settings$totp_enabled) && aa_totp_enabled(conn, res$login[1])) {
        # the password is correct but a code is needed: the successful attempt is not recorded (it would reset
        # the failure counter and the code could be guessed endlessly), no token is issued
        message_text("")
        second_factor(list(
          login = res$login[1], role = res$role[1],
          must_change = isTRUE(res$must_change[1] == 1), old = password
        ))
        return()
      }

      if (!is.null(res)) {
        try(aa_record_attempt(conn, login, success = TRUE, settings = settings), silent = TRUE)

        if (isTRUE(res$must_change[1] == 1)) {
          # the password is correct but it was set by an administrator: password change first
          message_text("")
          pending(list(login = res$login[1], role = res$role[1], old = password))
          return()
        }

        finish_login(res$login[1], res$role[1])
        emit("login_success", res$login[1])
        return()
      }

      try(aa_record_attempt(conn, login, success = FALSE, settings = settings), silent = TRUE)

      # this attempt could have led to a block
      gate <- aa_login_gate(conn, login, settings)
      if (!gate$allowed && gate$reason == "locked") {
        message_text(gate$message)
        emit("login_locked", login, gate$seconds)
      } else {
        message_text(aa_text(settings, "bad_credentials"))
        emit("login_failed", login)
      }
    })

    shiny::observeEvent(input$change_btn, {
      waiting <- pending()
      shiny::req(waiting)

      if (!identical(input$change_password, input$change_confirm)) {
        message_text(aa_text(settings, "passwords_mismatch"))
        return()
      }

      changed <- tryCatch(
        {
          aa_change_own_password(conn, waiting$login, waiting$old, input$change_password, settings)
          TRUE
        },
        appauth_error_user = function(e) {
          message_text(conditionMessage(e))
          FALSE
        }
      )

      if (changed) {
        pending(NULL)
        emit("password_changed", waiting$login)
        warn_weak(input$change_password, waiting$login)
        finish_login(waiting$login, waiting$role)
        emit("login_success", waiting$login)
      }
    })

    shiny::observeEvent(input$forgot_link, {
      shiny::req(isTRUE(settings$reset_enabled), password_on)
      message_text("")
      mode("forgot")
    })

    shiny::observeEvent(input$back_link, {
      message_text("")
      second_factor(NULL)
      reset_pending(NULL)
      mode("login")
    })

    shiny::observeEvent(input$forgot_btn, {
      shiny::req(isTRUE(settings$reset_enabled), password_on)

      res <- tryCatch(
        aa_request_password_reset(conn, input$forgot_identifier, settings),
        error = function(e) {
          message("appauth: could not process the password recovery request: ", conditionMessage(e))
          list(reason = "error", login = NA_character_)
        }
      )

      # the journal gets the reason, the user always gets the same answer
      emit("password_reset_requested", if (is.na(res$login)) NULL else res$login, res$reason)
      message_text(aa_text(settings, "forgot_done", as.integer(round(settings$reset_ttl_minutes))))
    })

    shiny::observeEvent(input$reset_btn, {
      token <- reset_pending()
      shiny::req(token)

      if (!identical(input$reset_password, input$reset_confirm)) {
        message_text(aa_text(settings, "passwords_mismatch"))
        return()
      }

      login <- tryCatch(
        aa_reset_password_with_token(conn, token, input$reset_password, settings),
        appauth_error_user = function(e) {
          message_text(conditionMessage(e))

          # the link no longer works: a weak password does not spend the token, anything else does
          if (identical(e$reason, "reset_link_invalid")) {
            reset_pending(NULL)
            mode("login")
            emit("password_reset_failed")
            message_text(conditionMessage(e))
          }

          NULL
        }
      )

      if (!is.null(login)) {
        reset_pending(NULL)
        mode("login")
        emit("password_reset_done", login)
        warn_weak(input$reset_password, login)
        message_text(aa_text(settings, "reset_done"))
      }
    })

    shiny::observeEvent(input$totp_btn, {
      waiting <- second_factor()
      shiny::req(waiting)

      gate <- aa_login_gate(conn, waiting$login, settings)
      if (!gate$allowed) {
        message_text(gate$message)
        emit(if (gate$reason == "throttled") "login_throttled" else "login_locked", waiting$login, gate$seconds)
        return()
      }

      checked <- tryCatch(
        aa_verify_second_factor(conn, waiting$login, input$totp_code, settings),
        error = function(e) {
          message("appauth: could not verify the second factor: ", conditionMessage(e))
          list(ok = FALSE, method = NA_character_)
        }
      )

      if (!isTRUE(checked$ok)) {
        try(aa_record_attempt(conn, waiting$login, success = FALSE, settings = settings), silent = TRUE)
        emit("totp_failed", waiting$login)

        gate <- aa_login_gate(conn, waiting$login, settings)
        if (!gate$allowed && gate$reason == "locked") {
          # block: the user has to start over with the password (when it ends)
          second_factor(NULL)
          message_text(gate$message)
          emit("login_locked", waiting$login, gate$seconds)
        } else {
          message_text(aa_text(settings, "totp_wrong"))
        }
        return()
      }

      try(aa_record_attempt(conn, waiting$login, success = TRUE, settings = settings), silent = TRUE)
      if (identical(checked$method, "recovery")) {
        emit("recovery_code_used", waiting$login)
      }
      second_factor(NULL)

      if (isTRUE(waiting$must_change)) {
        message_text("")
        pending(list(login = waiting$login, role = waiting$role, old = waiting$old))
        return()
      }

      finish_login(waiting$login, waiting$role)
      emit("login_success", waiting$login)
    })

    shiny::observeEvent(input$setup_btn, {
      # the user could have been created in another tab or session
      if (tryCatch(aa_users_exist(conn), error = function(e) FALSE)) {
        users_exist(TRUE)
        return()
      }

      login <- input$setup_login
      password <- input$setup_password

      if (!identical(password, input$setup_confirm)) {
        message_text(aa_text(settings, "passwords_mismatch"))
        return()
      }

      created <- tryCatch(
        aa_create_first_admin(conn, login, password, settings),
        appauth_error_user = function(e) {
          message_text(conditionMessage(e))
          NULL
        }
      )

      if (is.null(created)) {
        return()
      }

      users_exist(TRUE)

      if (isTRUE(created)) {
        emit("first_admin_created", login)
        warn_weak(password, login)
        finish_login(login, settings$admin_role)
      }
    })

    list(
      user = shiny::reactive(user()),
      logged_in = shiny::reactive(!is.null(user())),
      role = shiny::reactive(user()$role),
      logout = logout,
      logout_all = logout_all,
      token = function() current_token
    )
  })
}

#' Google icon for the sign-in button
#'
#' @returns A Shiny UI element (inline SVG).
#' @noRd
aa_google_icon <- function() {
  shiny::HTML(paste0(
    '<svg viewBox="0 0 48 48" aria-hidden="true">',
    '<path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>',
    '<path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>',
    '<path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>',
    '<path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>',
    '</svg>'
  ))
}

#' Page address parameters string
#'
#' Wrapped in a function so that tests can substitute the address: the mock Shiny
#' session does not have a configurable address bar.
#'
#' @param session Module session.
#'
#' @returns A string like `"?reset=abc"` (may be empty).
#' @noRd
aa_url_search <- function(session) {
  session$clientData$url_search
}
