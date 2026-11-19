#' Send an event to the application hook
#'
#' The package writes nothing to the application logs itself: it reports every
#' event to the function `on_event(event, user, session_id, value)`, and the
#' application decides what to do with it. An error in the hook never
#' interrupts a package action: it is only printed as a message.
#'
#' @param on_event Hook function or `NULL` (then nothing happens).
#' @param event Event key, for example `"access_denied"`.
#' @param user User login or `NULL` (`"anonymous"` is recorded).
#' @param session_id Shiny session identifier or `NULL`.
#' @param value Additional event value (a string) or `NULL`.
#'
#' @returns Invisibly `TRUE` if the hook ran without an error, otherwise `FALSE`.
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
      message("appauth: error in on_event (", event, "): ", conditionMessage(e))
      FALSE
    }
  )

  invisible(ok)
}

#' Catalog of authorization events
#'
#' The package reports events to the `on_event(event, user, session_id, value)`
#' hook defined by the application (writing to a log, a messenger notification,
#' etc.). This function returns the full list of events the package can send.
#'
#' The `user` field in the hook is the login on whose behalf the event happens
#' (for a failed sign-in it is the entered login, and if there is no login,
#' `"anonymous"`), and `value` holds the detail described in the `value`
#' column. Passwords and tokens never appear in events.
#'
#' @param lang Language of the `description` and `value` columns: `"en"`
#'   (default) or `"ru"`.
#'
#' @returns A data frame with columns `event` (key), `description` (what
#'   happened) and `value` (what is in the `value` field).
#' @export
#'
#' @examples
#' aa_events()
#' aa_events()$event
aa_events <- function(lang = c("en", "ru")) {
  lang <- rlang::arg_match(lang)

  if (lang == "ru") {
    ev <- aa_events_ru

    return(data.frame(
      event = names(ev),
      description = vapply(ev, `[`, character(1), 1, USE.NAMES = FALSE),
      value = vapply(ev, `[`, character(1), 2, USE.NAMES = FALSE),
      stringsAsFactors = FALSE
    ))
  }

  catalog <- list(
    c("login_success",        "Successful sign-in (by password, with Google or by an auto sign-in cookie)", "cookie (auto sign-in) or google (Google sign-in)"),
    c("login_failed",         "Incorrect login or password",                                    "password_disabled if password sign-in is disabled"),
    c("login_locked",         "Sign-in attempt for a login locked after failed attempts",       "seconds until the lock ends"),
    c("login_blocked_user",   "Sign-in attempt by a user blocked by an administrator",          ""),
    c("login_throttled",      "Rejected because of the overall per-minute limit of failed attempts", ""),
    c("login_unlocked",       "An administrator removed the sign-in attempts lock",             "login the lock was removed from"),
    c("logout",               "The user signed out on their own",                               ""),
    c("session_forced_logout","The session was ended forcibly",                                 "reason: deleted, blocked, role_changed, token_revoked"),
    c("first_admin_created",  "The first administrator was created",                            ""),
    c("user_added",           "An administrator added a user",                                  "login of the new user and the role"),
    c("user_removed",         "An administrator deleted a user",                                "login of the deleted user"),
    c("user_role_changed",    "An administrator changed a user's role",                         "login and the new role"),
    c("password_changed",     "The user changed their own password",                            ""),
    c("sessions_revoked",     "An administrator ended all sessions of a user",                  "user login"),
    c("password_reset",       "An administrator changed a user's password",                     "user login"),
    c("user_blocked",         "An administrator blocked a user",                                "user login"),
    c("user_unblocked",       "An administrator unblocked a user",                              "user login"),
    c("access_denied",        "Access denied: the role lacks the required permission",          "permission name"),
    c("password_reset_requested", "Password recovery requested by email (the user always gets the same response)", "result: sent, no_user, no_email, blocked, throttled, send_failed"),
    c("password_reset_done",  "Password changed using the link from the email",                 ""),
    c("password_reset_failed","Invalid or expired password recovery link",                      ""),
    c("email_changed",        "An administrator set, changed or removed a user's email",        "user login"),
    c("totp_enabled",         "The user enabled two-factor authentication",                     ""),
    c("totp_disabled",        "The user disabled two-factor authentication",                    ""),
    c("totp_failed",          "Incorrect code when confirming sign-in or disabling 2FA",        ""),
    c("totp_reset",           "An administrator reset a user's 2FA",                            "user login"),
    c("recovery_code_used",   "Sign-in confirmed with a recovery code",                         ""),
    c("google_login_failed",  "Failed Google sign-in (the user is shown a generic text)",       "reason: start_failed, bad_state, bad_browser, bad_code, exchange_failed, bad_token, bad_nonce, email_unverified, domain, no_user, blocked, cancelled; followed by a space and the email if known"),
    c("weak_password_set",    "A weak password was accepted (password_policy = \"warn\" mode)", "login and reason: password_common, password_equals_login, password_repeated")
  )

  data.frame(
    event = vapply(catalog, `[`, character(1), 1),
    description = vapply(catalog, `[`, character(1), 2),
    value = vapply(catalog, `[`, character(1), 3),
    stringsAsFactors = FALSE
  )
}
