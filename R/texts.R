# Interface and message text sets of the package.
# The English set lives here; the Russian set (aa_texts_ru) is generated into
# R/texts-ru.R by dev/build-texts-ru.R with all non-ASCII characters escaped.
# Keys of both sets must match (checked by a test).

aa_texts_en <- list(
  # login form
  login_title = "Authorization",
  login_label = "Login",
  password_label = "Password",
  login_button = "Sign in",
  # first administrator setup
  setup_title = "Create administrator",
  setup_hint = "The application has no users yet. The first user you create gets the %s role.",
  password_confirm_label = "Confirm password",
  setup_button = "Create administrator",
  # sign-in messages
  bad_credentials = "Incorrect login or password",
  locked = "Too many failed sign-in attempts. Try again in %d min.",
  throttled = "Too many sign-in attempts. Try again in a minute.",
  blocked_user = "The account has been blocked by an administrator. Please contact the administrator.",
  # login and password validation
  passwords_mismatch = "Passwords do not match",
  password_empty = "Password cannot be empty",
  password_too_short = "Password must be at least %d characters long",
  password_too_long = "Password must be at most %d characters long",
  password_common = "The password is in the list of common weak passwords",
  password_equals_login = "The password is the same as the login",
  password_repeated = "The password is a single repeated character",
  weak_password_notice = "The password was accepted, but it is weak: %s. Consider changing it to a stronger one.",
  login_empty = "Login cannot be empty",
  login_whitespace = "Login must not start or end with a space",
  login_too_long = "Login must be at most %d characters long",
  # user statuses in the table
  status_blocked = "Blocked by an administrator",
  status_locked = "Sign-in is locked after failed attempts (%d min. left)",
  # user management
  user_not_specified = "User is not specified",
  user_not_found = "User not found",
  user_exists = "User already exists",
  user_exists_case = "A user with this login already exists (logins differ only in letter case)",
  invalid_role = "Invalid role",
  cannot_block_self = "You cannot block yourself",
  cannot_block_last_admin = "You cannot block the last active administrator",
  cannot_delete_self = "You cannot delete yourself",
  cannot_delete_last_admin = "You cannot delete the last active administrator",
  cannot_change_last_admin_role = "You cannot remove the administrator role from the last active administrator",
  # users tab
  users_title = "Users",
  users_add = "Add user",
  users_hint = "Double-click a row to open the user card. \"Auto-logins\" is the number of devices that remember the sign-in",
  col_login = "Login",
  col_role = "Role",
  col_status = "Status",
  col_created = "Created",
  col_last_login = "Last sign-in",
  col_email = "Email",
  col_totp = "2FA",
  col_autologins = "Auto-logins",
  copy_button = "Copy",
  copy_done = "Copied",
  date_unknown = "unknown",
  date_never = "never signed in",
  card_title = "User: %s",
  card_account = "Account",
  card_active = "active",
  card_blocked = "blocked by an administrator",
  card_signin = "Sign-in",
  card_signin_ok = "not locked",
  card_signin_locked = "locked for %d more min.",
  button_block = "Block",
  button_unblock = "Unblock",
  button_unlock = "Remove lock",
  button_close = "Close",
  role_section = "Change role",
  role_label = "Role",
  role_button = "Change role",
  reset_section = "Reset password",
  reset_new_label = "New password",
  reset_button = "Reset password",
  delete_section = "Delete user",
  delete_warning = "Warning: this cannot be undone!",
  delete_button = "Delete account",
  delete_confirm_title = "Delete the user?",
  delete_confirm_text = "User %s will be deleted together with their sessions. This cannot be undone.",
  delete_confirm_button = "Yes, delete",
  button_cancel = "Cancel",
  delete_unavailable = "This user cannot be deleted: %s.",
  add_title = "New user",
  add_button = "Add",
  done_user_added = "User %s added",
  done_role_changed = "Role of user %s changed",
  done_password_reset = "Password of user %s changed",
  done_blocked = "User %s blocked",
  done_unblocked = "User %s unblocked",
  done_unlocked = "Sign-in lock removed: %s",
  done_deleted = "User %s deleted",
  # password change
  password_old_label = "Current password",
  password_new_label = "New password",
  password_change_title = "Change password",
  password_change_button = "Change password",
  password_wrong = "The current password is incorrect",
  password_same = "The new password must differ from the current one",
  done_password_changed = "Password changed",
  must_change_title = "Change your password",
  must_change_hint = "The password was set by an administrator. Set your own password to sign in.",
  sso_change_expired = "This sign-in can no longer change the password. Sign in again.",
  must_change_label = "Require a password change at next sign-in",
  # password recovery by email
  forgot_link = "Forgot your password?",
  forgot_title = "Password recovery",
  forgot_hint = "Enter your login or email. If the user is found and has an email set, we will send a message with a link to change the password.",
  forgot_identifier_label = "Login or email",
  forgot_button = "Send link",
  forgot_done = "If the user is found and has an email set, a message with the link has been sent. The link is valid for %d min.",
  back_to_login = "Back to sign in",
  reset_title = "New password",
  reset_hint = "Set a new password to sign in.",
  reset_save_button = "Save password",
  reset_link_invalid = "The link is invalid or has expired. Request password recovery again.",
  reset_done = "Password changed. Sign in with the new password.",
  # Google sign-in
  google_button = "Sign in with Google",
  google_or = "or",
  google_failed = "Could not sign in with Google. Please try again.",
  google_cancelled = "Google sign-in was cancelled.",
  google_no_user = "This Google account has not been granted access. Contact an administrator.",
  google_domain = "This Google account does not belong to the allowed organization domains.",
  password_login_disabled = "Password sign-in is disabled. Use Google sign-in.",
  # self-registration
  registration_link = "Create an account",
  registration_title = "Create an account",
  registration_hint = "Enter a login, an email address and a password. A confirmation link will be sent to the address.",
  registration_email_label = "Email",
  registration_button = "Create account",
  registration_done = "If the address is available, a confirmation link has been sent. It is valid for %d min.",
  registration_confirmed = "Account created. Sign in with your password.",
  registration_link_invalid = "The registration link is invalid or has expired. Request registration again.",
  registration_domain = "Registration is allowed only for these email domains: %s",
  registration_throttled = "Too many registration requests. Please try again later.",
  registration_failed = "Could not create the account. Please try again.",
  google_signup_login_taken = "An account with this login already belongs to another address. Contact an administrator.",
  # user email
  email_section = "Email for password recovery",
  email_label = "Email",
  email_button = "Save email",
  email_not_set = "not set",
  email_invalid = "Invalid email address",
  email_exists = "This email is already set for another user",
  done_email_saved = "Email of user %s saved",
  done_email_cleared = "Email of user %s removed",
  # two-factor authentication
  totp_title = "Confirm sign-in",
  totp_hint = "Enter the code from your authenticator app or a recovery code.",
  totp_code_label = "Code",
  totp_button = "Confirm",
  totp_wrong = "Incorrect code",
  totp_already_enabled = "Two-factor authentication is already enabled",
  totp_section = "Two-factor authentication",
  totp_status_on = "enabled",
  totp_status_off = "disabled",
  totp_enable_button = "Enable",
  totp_setup_hint = "Scan the QR code with an authenticator app (Google Authenticator, Microsoft Authenticator, 2FAS) or enter the key manually, then enter the code from the app.",
  totp_secret_label = "Key for manual entry",
  totp_confirm_button = "Confirm and enable",
  totp_enroll_title = "Set up two-factor authentication",
  totp_enroll_hint = "Your role requires two-factor authentication. Scan the QR code or enter the key manually, then enter the code from the app to continue.",
  totp_required_hint = "Two-factor authentication is required for your role and cannot be disabled here.",
  totp_recovery_title = "Recovery codes",
  totp_recovery_hint = "Store these codes in a safe place. Each works once and they are not shown again.",
  totp_recovery_left = "Recovery codes left: %d",
  totp_disable_title = "Disable two-factor authentication",
  totp_disable_button = "Disable",
  totp_disable_wrong = "Incorrect password or code",
  totp_reset_button = "Reset 2FA",
  card_totp = "2FA",
  done_totp_enabled = "Two-factor authentication enabled",
  done_totp_disabled = "Two-factor authentication disabled",
  done_totp_reset = "2FA of user %s reset",
  # sessions
  button_revoke = "End all sessions",
  done_sessions_revoked = "Sessions of user %s ended",
  # access control
  access_denied = "You do not have permission to perform this action"
)

#' Interface and message texts
#'
#' Returns the set of texts for the chosen language. Any string can be replaced
#' with your own by passing its key and the new value. Texts with substituted
#' values contain `%d` (number) and `%s` (string) placeholders, the values are
#' filled in by [aa_text()].
#'
#' Available keys are listed by [aa_text_keys()].
#'
#' @param lang Language of the texts: `"en"` (default) or `"ru"`.
#' @param ... Your own texts as `key = "string"`, they replace the default ones.
#'
#' @returns A named list of strings of class `aa_texts`.
#' @export
#'
#' @examples
#' # English texts (default)
#' texts <- aa_texts()
#'
#' # English texts with a custom sign-in button label
#' texts <- aa_texts("en", login_button = "Log in")
#' texts$login_button
#'
#' # Russian texts
#' texts <- aa_texts("ru")
aa_texts <- function(lang = c("en", "ru"), ...) {
  lang <- rlang::arg_match(lang)
  base <- if (lang == "ru") aa_texts_ru else aa_texts_en

  overrides <- list(...)

  if (length(overrides) > 0) {
    nms <- names(overrides)

    if (is.null(nms) || any(is.na(nms) | !nzchar(nms))) {
      rlang::abort(
        "Custom texts must be named: `aa_texts(login_button = \"...\")`.",
        class = "appauth_error_texts"
      )
    }

    unknown <- setdiff(nms, names(base))
    if (length(unknown) > 0) {
      rlang::abort(
        paste0(
          "Unknown text keys: ",
          paste(unknown, collapse = ", "),
          ". The list of available keys is returned by `aa_text_keys()`."
        ),
        class = "appauth_error_texts"
      )
    }

    not_string <- !vapply(overrides, aa_is_string, logical(1))
    if (any(not_string)) {
      rlang::abort(
        paste0(
          "Text values must be non-empty strings, check: ",
          paste(nms[not_string], collapse = ", "),
          "."
        ),
        class = "appauth_error_texts"
      )
    }

    base[nms] <- overrides
  }

  structure(base, class = "aa_texts", lang = lang)
}

#' Interface text keys
#'
#' @returns A vector of key names that can be overridden in [aa_texts()].
#' @export
#'
#' @examples
#' aa_text_keys()
aa_text_keys <- function() {
  names(aa_texts_en)
}

#' Get a text by key
#'
#' Returns a string from a set of texts. If values are passed, they are
#' substituted into the string following the rules of [sprintf()].
#'
#' @param x A set of texts (result of [aa_texts()]) or settings (result of
#'   [aa_settings()]).
#' @param key Text key, see [aa_text_keys()].
#' @param ... Values for the `%d` and `%s` placeholders.
#'
#' @returns A string.
#' @export
#'
#' @examples
#' texts <- aa_texts("en")
#' aa_text(texts, "login_button")
#' aa_text(texts, "locked", 15)
aa_text <- function(x, key, ...) {
  if (inherits(x, "aa_settings")) {
    x <- x$texts
  }

  if (!inherits(x, "aa_texts")) {
    rlang::abort(
      "The first argument must be a result of `aa_texts()` or `aa_settings()`.",
      class = "appauth_error_texts"
    )
  }

  if (!aa_is_string(key) || !key %in% names(x)) {
    rlang::abort(
      paste0(
        "Unknown text key: ",
        paste(key, collapse = ", "),
        ". The list of available keys is returned by `aa_text_keys()`."
      ),
      class = "appauth_error_texts"
    )
  }

  fmt <- x[[key]]
  args <- list(...)

  if (length(args) == 0) {
    return(fmt)
  }

  do.call(sprintf, c(list(fmt), args))
}

#' @export
print.aa_texts <- function(x, ...) {
  lang <- attr(x, "lang")
  cat(
    "appauth texts, language: ",
    if (is.null(lang)) "not set" else lang,
    ", strings: ",
    length(x),
    "\n",
    sep = ""
  )
  invisible(x)
}
