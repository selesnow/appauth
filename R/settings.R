#' Authorization settings
#'
#' Builds the settings that control the behavior of the package: password
#' rules, brute-force protection, data retention periods, the list of roles and
#' the interface language. The settings object is passed to the other functions
#' and modules of the package; the package does not use global variables.
#'
#' @section Brute-force protection:
#' If `max_failed_logins` failed attempts accumulate for one login within
#' `lockout_minutes` minutes, sign-in for this login is blocked for
#' `lockout_minutes` minutes starting from the last failed attempt. Attempts
#' made during the lock are not recorded and do not extend the lock. In
#' addition, if `max_failed_logins_per_minute` failed attempts accumulate over
#' the last minute across all logins together, sign-in is temporarily closed
#' for everyone: this stops password guessing spread over many logins.
#'
#' @param max_failed_logins Number of failed sign-in attempts before the login
#'   is locked.
#' @param lockout_minutes Window for counting failed attempts and the duration
#'   of the lock, in minutes.
#' @param max_failed_logins_per_minute Overall limit of failed sign-in attempts
#'   across all logins per minute.
#' @param password_min,password_max Minimum and maximum length of a new
#'   password. The limit applies only to new and reset passwords, existing
#'   passwords are not affected.
#' @param password_policy What to do with weak new passwords (from the
#'   [aa_common_passwords()] list, equal to the login ignoring case, or made of
#'   a single repeated character): `"off"` do not check, `"warn"` (default)
#'   accept the password but show a warning, `"reject"` reject the password.
#'   Existing passwords are not affected.
#' @param login_max Maximum login length (the login is also lowercased and
#'   trimmed when attempts are counted).
#' @param autologin Whether to use cookie-based auto sign-in. If `FALSE`, the
#'   user enters the password on every page load and no tokens are issued.
#' @param session_days Lifetime of the auto sign-in token, in days.
#' @param session_check_seconds How often to check that an open session is
#'   still allowed (the user has not been blocked or deleted), in seconds.
#' @param attempts_retention_hours How many hours to keep records of sign-in
#'   attempts.
#' @param token_retention_days How many days to keep expired and revoked tokens
#'   before deleting them.
#' @param roles Allowed user roles.
#' @param admin_role Administrator role, it must be one of `roles`. Only this
#'   role manages users, regardless of the application's permission matrix, and
#'   it is the role given to the first created user.
#' @param must_change_default Default state of the "require a password change
#'   at next sign-in" checkbox in the add-user dialog and when resetting a
#'   password. `TRUE` (default): a password set by an administrator is
#'   temporary, and the administrator clears the checkbox if a change is not
#'   needed. `FALSE`: the checkbox is off, the administrator turns it on.
#' @param reset_enabled Enable password recovery by email: a "Forgot your
#'   password?" link appears on the sign-in form. Default `FALSE`. Requires
#'   `send_reset` and `reset_base_url`.
#' @param send_reset Function that sends the email, `function(email, link,
#'   login)`: sends a message with the `link` to the `email` address (for
#'   example, using `emayili`). An error in the function does not interrupt the
#'   request and is not visible to the user, the reason goes into the
#'   `password_reset_requested` event.
#' @param reset_base_url Application address the link in the email points to,
#'   for example `"https://apps.example.com/my_app"`. `?reset=<token>` is
#'   appended to it.
#' @param reset_ttl_minutes Lifetime of the password change link, in minutes.
#' @param reset_max_per_hour How many recovery emails can be sent to one user
#'   per hour, further requests are silently ignored.
#' @param reset_max_per_minute Overall limit of recovery emails across all users
#'   per minute (protection against spam).
#' @param totp_enabled Enable two-factor authentication (one-time TOTP codes
#'   from an authenticator app). Default `FALSE`. Requires `totp_key`.
#'   Two-factor protection is voluntary: each user enables it in the
#'   [aa_totp_server()] module, and users who have it enabled enter a code when
#'   signing in with a password.
#' @param totp_key Encryption key for TOTP secrets in the database, a string of
#'   at least 16 characters (for example, from an environment variable).
#'   **Store it outside the database and outside the repository.** If the key
#'   is lost or replaced, existing secrets cannot be decrypted and users have
#'   to set up 2FA again (an administrator resets it in the user card).
#' @param totp_issuer Service name shown by the authenticator app.
#' @param totp_window How many 30-second steps in each direction of clock drift
#'   are tolerated (0 to 5, default 1).
#' @param google_enabled Enable sign-in with Google (OpenID Connect): a "Sign in
#'   with Google" button appears on the sign-in form. Default `FALSE`. Requires
#'   `google_client_id`, `google_client_secret` and `google_redirect_uri`. Only
#'   a user who already exists in the database and whose email equals the
#'   Google account address can sign in: sign-in never creates new users, the
#'   role is taken from the database. The application's two-factor code is not
#'   requested for Google sign-in (Google does the verification itself).
#' @param google_client_id,google_client_secret Identifier and secret of the
#'   OAuth client (type "Web application") from the Google Cloud Console.
#'   **Store the secret outside the database and outside the repository** (for
#'   example, in an environment variable).
#' @param google_redirect_uri Address Google returns the user to: the address
#'   of the application as users open it, for example
#'   `"https://apps.example.com/"`. It must exactly match an address in the
#'   "Authorized redirect URIs" list of the OAuth client. `https://` is
#'   allowed, and `http://localhost` for development.
#' @param google_domains Allowed organization domains (a vector, for example
#'   `c("example.com", "example.net")`). If set, sign-in is accepted only for
#'   accounts whose signed Google token contains one of these domains (`hd`,
#'   the primary Workspace domain of the organization) and whose email domain
#'   is also in the list. If the organization has secondary domains, list both
#'   the primary and the secondary ones. An empty value (`NULL`) disables the
#'   domain check, then only the match of the email with a user in the database
#'   decides.
#' @param password_login Allow sign-in with a login and password. Default
#'   `TRUE`. `FALSE` hides the password form and "Forgot your password?" and
#'   rejects such attempts on the server; possible only together with
#'   `google_enabled = TRUE`, otherwise there would be no way to sign in.
#'   Creating the first administrator on an empty database is still available.
#' @param texts Interface texts, a result of [aa_texts()].
#'
#' @returns A list of settings of class `aa_settings`.
#' @export
#'
#' @examples
#' # default settings
#' settings <- aa_settings()
#'
#' # password recovery by email
#' settings <- aa_settings(
#'   reset_enabled  = TRUE,
#'   reset_base_url = "https://apps.example.com/my_app",
#'   send_reset     = function(email, link, login) message("Email for ", login, ": ", link)
#' )
#'
#' # sign-in with Google (secret from an environment variable), password stays as a fallback
#' settings <- aa_settings(
#'   google_enabled       = TRUE,
#'   google_client_id     = "1234-abc.apps.googleusercontent.com",
#'   google_client_secret = Sys.getenv("GOOGLE_OAUTH_CLIENT_SECRET", "secret"),
#'   google_redirect_uri  = "https://apps.example.com/",
#'   google_domains       = c("example.com", "example.net")
#' )
#'
#' # stricter protection, Russian interface and custom roles
#' settings <- aa_settings(
#'   max_failed_logins = 3,
#'   lockout_minutes   = 30,
#'   password_min      = 10,
#'   roles             = c("admin", "editor", "viewer"),
#'   texts             = aa_texts("ru")
#' )
#' settings$lockout_minutes
aa_settings <- function(
    max_failed_logins            = 5,
    lockout_minutes              = 15,
    max_failed_logins_per_minute = 30,
    password_min                 = 6,
    password_max                 = 128,
    password_policy              = "warn",
    login_max                    = 64,
    autologin                    = TRUE,
    session_days                 = 30,
    session_check_seconds        = 30,
    attempts_retention_hours     = 24,
    token_retention_days         = 30,
    roles                        = c("admin", "user", "viewer"),
    admin_role                   = "admin",
    must_change_default          = TRUE,
    reset_enabled                = FALSE,
    send_reset                   = NULL,
    reset_base_url               = NULL,
    reset_ttl_minutes            = 60,
    reset_max_per_hour           = 3,
    reset_max_per_minute         = 10,
    totp_enabled                 = FALSE,
    totp_key                     = NULL,
    totp_issuer                  = "appauth",
    totp_window                  = 1,
    google_enabled               = FALSE,
    google_client_id             = NULL,
    google_client_secret         = NULL,
    google_redirect_uri          = NULL,
    google_domains               = NULL,
    password_login               = TRUE,
    texts                        = aa_texts("en")
) {
  aa_check_positive(max_failed_logins, "max_failed_logins")
  aa_check_positive(lockout_minutes, "lockout_minutes")
  aa_check_positive(max_failed_logins_per_minute, "max_failed_logins_per_minute")
  aa_check_positive(password_min, "password_min")
  aa_check_positive(password_max, "password_max")
  aa_check_positive(login_max, "login_max")
  aa_check_flag(autologin, "autologin")
  aa_check_flag(must_change_default, "must_change_default")
  aa_check_flag(reset_enabled, "reset_enabled")
  aa_check_positive(reset_ttl_minutes, "reset_ttl_minutes")
  aa_check_positive(reset_max_per_hour, "reset_max_per_hour")
  aa_check_positive(reset_max_per_minute, "reset_max_per_minute")
  aa_check_flag(totp_enabled, "totp_enabled")
  aa_check_flag(google_enabled, "google_enabled")
  aa_check_flag(password_login, "password_login")
  aa_check_positive(session_days, "session_days")
  aa_check_positive(session_check_seconds, "session_check_seconds")
  aa_check_positive(attempts_retention_hours, "attempts_retention_hours")
  aa_check_positive(token_retention_days, "token_retention_days")

  if (!(aa_is_string(password_policy) && password_policy %in% c("off", "warn", "reject"))) {
    rlang::abort(
      "`password_policy` must be one of: \"off\", \"warn\", \"reject\".",
      class = "appauth_error_settings"
    )
  }

  if (!(is.null(send_reset) || is.function(send_reset))) {
    rlang::abort(
      "`send_reset` must be a function `function(email, link, login)` or `NULL`.",
      class = "appauth_error_settings"
    )
  }

  if (!(is.null(reset_base_url) || aa_is_string(reset_base_url))) {
    rlang::abort(
      "`reset_base_url` must be a string with the application address or `NULL`.",
      class = "appauth_error_settings"
    )
  }

  if (reset_enabled && !(is.function(send_reset) && aa_is_string(reset_base_url))) {
    rlang::abort(
      "`reset_enabled = TRUE` requires the `send_reset` function and the application address `reset_base_url`.",
      class = "appauth_error_settings"
    )
  }

  if (!(is.null(totp_key) || (is.character(totp_key) && length(totp_key) == 1 && !is.na(totp_key)))) {
    rlang::abort(
      "`totp_key` must be a string or `NULL`.",
      class = "appauth_error_settings"
    )
  }

  if (totp_enabled && !(aa_is_string(totp_key) && nchar(totp_key) >= 16)) {
    rlang::abort(
      "`totp_enabled = TRUE` requires an encryption key `totp_key` (a string of at least 16 characters).",
      class = "appauth_error_settings"
    )
  }

  if (!aa_is_string(totp_issuer)) {
    rlang::abort(
      "`totp_issuer` must be a non-empty string.",
      class = "appauth_error_settings"
    )
  }

  if (!(is.numeric(totp_window) && length(totp_window) == 1 && is.finite(totp_window) &&
        totp_window >= 0 && totp_window <= 5 && totp_window == round(totp_window))) {
    rlang::abort(
      "`totp_window` must be an integer from 0 to 5.",
      class = "appauth_error_settings"
    )
  }

  # domains from a config arrive as a list, from code as a vector: lowercase them
  google_domains <- tolower(trimws(as.character(unlist(google_domains))))
  google_domains <- unique(google_domains[!is.na(google_domains) & nzchar(google_domains)])

  if (!all(grepl("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?\\.[a-z]{2,}$", google_domains))) {
    rlang::abort(
      "`google_domains` must contain domains like `example.com`.",
      class = "appauth_error_settings"
    )
  }

  for (field in c("google_client_id", "google_client_secret", "google_redirect_uri")) {
    value <- get(field)

    if (!(is.null(value) || (is.character(value) && length(value) == 1 && !is.na(value)))) {
      rlang::abort(
        paste0("`", field, "` must be a string or `NULL`."),
        class = "appauth_error_settings"
      )
    }
  }

  if (google_enabled && !(aa_is_string(google_client_id) && aa_is_string(google_client_secret) &&
                          aa_is_string(google_redirect_uri))) {
    rlang::abort(
      "`google_enabled = TRUE` requires `google_client_id`, `google_client_secret` and `google_redirect_uri`.",
      class = "appauth_error_settings"
    )
  }

  if (google_enabled && !grepl("^(https://[^/\\s]+|http://(localhost|127\\.0\\.0\\.1)(:[0-9]+)?)(/\\S*)?$", google_redirect_uri, perl = TRUE)) {
    rlang::abort(
      "`google_redirect_uri` must be an `https://...` address (`http://localhost` for development).",
      class = "appauth_error_settings"
    )
  }

  if (!password_login && !google_enabled) {
    rlang::abort(
      "Password sign-in can be disabled (`password_login = FALSE`) only together with `google_enabled = TRUE`.",
      class = "appauth_error_settings"
    )
  }

  if (password_min > password_max) {
    rlang::abort(
      "`password_min` cannot be greater than `password_max`.",
      class = "appauth_error_settings"
    )
  }

  if (!(is.character(roles) && length(roles) >= 1 && !anyNA(roles) &&
        all(nzchar(roles)) && !anyDuplicated(roles))) {
    rlang::abort(
      "`roles` must be a vector of unique non-empty strings.",
      class = "appauth_error_settings"
    )
  }

  if (!(aa_is_string(admin_role) && admin_role %in% roles)) {
    rlang::abort(
      "`admin_role` must be one of the roles in `roles`.",
      class = "appauth_error_settings"
    )
  }

  if (!inherits(texts, "aa_texts")) {
    rlang::abort(
      "`texts` must be a result of `aa_texts()`.",
      class = "appauth_error_settings"
    )
  }

  structure(
    list(
      max_failed_logins            = max_failed_logins,
      lockout_minutes              = lockout_minutes,
      max_failed_logins_per_minute = max_failed_logins_per_minute,
      password_min                 = password_min,
      password_max                 = password_max,
      password_policy              = password_policy,
      login_max                    = login_max,
      autologin                    = autologin,
      session_days                 = session_days,
      session_check_seconds        = session_check_seconds,
      attempts_retention_hours     = attempts_retention_hours,
      token_retention_days         = token_retention_days,
      roles                        = roles,
      admin_role                   = admin_role,
      must_change_default          = must_change_default,
      reset_enabled                = reset_enabled,
      send_reset                   = send_reset,
      reset_base_url               = reset_base_url,
      reset_ttl_minutes            = reset_ttl_minutes,
      reset_max_per_hour           = reset_max_per_hour,
      reset_max_per_minute         = reset_max_per_minute,
      totp_enabled                 = totp_enabled,
      totp_key                     = totp_key,
      totp_issuer                  = totp_issuer,
      totp_window                  = totp_window,
      google_enabled               = google_enabled,
      google_client_id             = google_client_id,
      google_client_secret         = google_client_secret,
      google_redirect_uri          = google_redirect_uri,
      google_domains               = google_domains,
      password_login               = password_login,
      texts                        = texts
    ),
    class = "aa_settings"
  )
}

#' Settings from a list (for example, from a `config.yaml` section)
#'
#' Convenient when the protection settings are kept in the application config.
#' Only known parameters of [aa_settings()] are taken, the rest are ignored, and
#' any parameter can be overridden with the `...` arguments.
#'
#' @param x A list of settings, for example
#'   `yaml::read_yaml("config.yaml")$security`, or `NULL`.
#' @param ... Parameters of [aa_settings()] that replace the values from `x`.
#'
#' @returns A list of settings of class `aa_settings`.
#' @export
#'
#' @examples
#' security <- list(max_failed_logins = 3, lockout_minutes = 10, unknown_key = 1)
#' settings <- aa_settings_from_list(security, texts = aa_texts("en"))
#' settings$max_failed_logins
aa_settings_from_list <- function(x = NULL, ...) {
  if (!(is.null(x) || is.list(x))) {
    rlang::abort(
      "The first argument must be a list of settings or `NULL`.",
      class = "appauth_error_settings"
    )
  }

  known <- setdiff(names(formals(aa_settings)), "texts")
  from_list <- if (is.null(x)) list() else x[intersect(names(x), known)]

  do.call(aa_settings, utils::modifyList(from_list, list(...)))
}

#' @export
print.aa_settings <- function(x, ...) {
  cat("appauth settings\n")
  cat("  Failed attempts before login lock: ", x$max_failed_logins,
      " within ", x$lockout_minutes, " min., lock for ", x$lockout_minutes, " min.\n", sep = "")
  cat("  Overall limit of failed attempts: ", x$max_failed_logins_per_minute, " per minute\n", sep = "")
  cat("  New password length: from ", x$password_min, " to ", x$password_max, " characters\n", sep = "")
  cat("  Weak passwords: ", switch(x$password_policy, off = "not checked", warn = "warning", reject = "rejected"), "\n", sep = "")
  cat("  Auto sign-in: ", if (x$autologin) "enabled" else "disabled",
      ", token lifetime ", x$session_days, " days\n", sep = "")
  cat("  Password set by an administrator: ", if (x$must_change_default) "temporary (change at sign-in)" else "permanent",
      " by default\n", sep = "")
  cat("  Password recovery by email: ",
      if (x$reset_enabled) paste0("enabled, link valid for ", x$reset_ttl_minutes, " min.") else "disabled",
      "\n", sep = "")
  cat("  Two-factor authentication: ", if (x$totp_enabled) "enabled (voluntary)" else "disabled", "\n", sep = "")
  cat("  Password sign-in: ", if (x$password_login) "allowed" else "disabled", "\n", sep = "")
  cat("  Google sign-in: ",
      if (x$google_enabled) {
        paste0("enabled", if (length(x$google_domains)) paste0(" (domains: ", paste(x$google_domains, collapse = ", "), ")") else "")
      } else "disabled",
      "\n", sep = "")
  cat("  Roles: ", paste(x$roles, collapse = ", "),
      " (administrator: ", x$admin_role, ")\n", sep = "")
  cat("  Interface language: ", attr(x$texts, "lang"), "\n", sep = "")
  invisible(x)
}
