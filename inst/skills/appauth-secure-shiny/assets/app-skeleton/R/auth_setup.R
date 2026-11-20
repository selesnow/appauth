# Glue between the app and the appauth authentication package.
#
# The file lives in the R/ folder, which app.R sources into the GLOBAL environment.
# Therefore auth_settings, referenced by the functions below, must be created in app.R
# globally (auth_settings <<- ...): under runApp() app.R itself is loaded into its own
# environment, and an ordinary assignment is not visible to these functions (tabs stay empty).

#' Authentication settings from the security section of config.yaml
#'
#' Unset values are taken from the package. A typo in the config (a zero limit, text instead of a number)
#' must not crash the app: a warning is written and the default settings are applied.
build_auth_settings <- function(security) {
  tryCatch(
    aa_settings_from_list(security, texts = aa_texts("en")),
    error = function(e) {
      message(
        "WARNING: invalid security section in config.yaml (",
        conditionMessage(e),
        "), defaults used"
      )
      aa_settings(texts = aa_texts("en"))
    }
  )
}

# --- package events -> action log entries ------------------------------------------
# Action names are set by the app. Every package event must be either here or in
# AUTH_EVENTS_IGNORED (the test in tests/test_auth_smoke.R watches this).
AUTH_EVENT_ACTIONS <- c(
  login_failed = "Login failed",
  login_locked = "Login locked",
  login_blocked_user = "Blocked login attempt",
  login_throttled = "Login throttled",
  login_unlocked = "Login unlock",
  first_admin_created = "User add",
  user_added = "User add",
  user_removed = "User remove",
  user_role_changed = "User change role",
  password_reset = "User password reset",
  password_changed = "Password change",
  sessions_revoked = "Sessions revoke",
  user_blocked = "User block",
  user_unblocked = "User unblock",
  session_forced_logout = "Forced logout",
  access_denied = "Access denied",
  weak_password_set = "Weak password", # a weak password was accepted (password_policy = "warn"), value is "login: reason"
  # password reset by email
  password_reset_requested = "Password reset request",
  password_reset_done = "Password reset done",
  password_reset_failed = "Password reset failed",
  email_changed = "Email change",
  # two-factor authentication (TOTP)
  totp_enabled = "2FA enable",
  totp_disabled = "2FA disable",
  totp_failed = "2FA failed",
  totp_reset = "2FA reset",
  recovery_code_used = "2FA recovery code used",
  # sign-in with Google
  google_login_failed = "Google login failed"
)
AUTH_EVENTS_IGNORED <- c("login_success", "logout")

# the package puts details in value ("login (role)", "login: role"), the log needs only the login
auth_event_log_value <- function(event, user, value) {
  switch(
    event,
    login_failed = ,
    login_locked = ,
    login_blocked_user = ,
    login_throttled = ,
    first_admin_created = user,
    user_added = sub(" \\(.*\\)$", "", value),
    user_role_changed = sub(":.*$", "", value),
    value
  )
}

#' Authentication event hook: the single place where the app decides what to do with events
log_auth_event <- function(event, user, session_id, value) {
  func <- AUTH_EVENT_ACTIONS[event]
  if (is.na(func)) {
    return(invisible(NULL))
  }

  if (exists("write_action_log", mode = "function")) {
    try(
      write_action_log(
        user = user,
        func = unname(func),
        session_id = session_id,
        value = auth_event_log_value(event, user, value)
      ),
      silent = TRUE
    )
  } else {
    message(sprintf("[auth] %s user=%s value=%s", event, user, value))
  }
  invisible(NULL)
}

# --- permissions -----------------------------------------------------------------------

#' Permission source from the config.yaml matrix (access_matrix section)
#'
#' The matrix is read on every check, so edits in the permission editor take effect immediately.
conf_permissions <- function(conf_rv) {
  aa_permissions_from_matrix(function() conf_rv()$access_matrix)
}

#' "Administrator role only" permission source: for tabs whose access must not depend on the matrix
admin_only_provider <- function(user) {
  if (identical(user$role, auth_settings$admin_role)) "Access" else character(0)
}

#' Whether a role holds a permission (for showing tabs and buttons; it is not protection)
user_can <- function(role, permission, conf) {
  aa_can(
    list(login = "", role = role),
    permission,
    aa_permissions_from_matrix(conf$access_matrix %||% list())
  )
}

#' Permission check in an action handler: the FIRST line of every handler
require_permission <- function(auth, conf_rv, permission, session_id = "x0") {
  aa_require(
    auth,
    permission,
    conf_permissions(conf_rv),
    on_event = log_auth_event,
    settings = auth_settings,
    session_id = session_id
  )
}
