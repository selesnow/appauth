# Authorization settings

Builds the settings that control the behavior of the package: password
rules, brute-force protection, data retention periods, the list of roles
and the interface language. The settings object is passed to the other
functions and modules of the package; the package does not use global
variables.

## Usage

``` r
aa_settings(
  max_failed_logins = 5,
  lockout_minutes = 15,
  max_failed_logins_per_minute = 30,
  password_min = 6,
  password_max = 128,
  password_policy = "warn",
  login_max = 64,
  autologin = TRUE,
  session_days = 30,
  session_check_seconds = 30,
  attempts_retention_hours = 24,
  token_retention_days = 30,
  roles = c("admin", "user", "viewer"),
  admin_role = "admin",
  must_change_default = TRUE,
  reset_enabled = FALSE,
  send_reset = NULL,
  reset_base_url = NULL,
  reset_ttl_minutes = 60,
  reset_max_per_hour = 3,
  reset_max_per_minute = 10,
  totp_enabled = FALSE,
  totp_key = NULL,
  totp_issuer = "appauth",
  totp_window = 1,
  google_enabled = FALSE,
  google_client_id = NULL,
  google_client_secret = NULL,
  google_redirect_uri = NULL,
  google_domains = NULL,
  password_login = TRUE,
  texts = aa_texts("en")
)
```

## Arguments

- max_failed_logins:

  Number of failed sign-in attempts before the login is locked.

- lockout_minutes:

  Window for counting failed attempts and the duration of the lock, in
  minutes.

- max_failed_logins_per_minute:

  Overall limit of failed sign-in attempts across all logins per minute.

- password_min, password_max:

  Minimum and maximum length of a new password. The limit applies only
  to new and reset passwords, existing passwords are not affected.

- password_policy:

  What to do with weak new passwords (from the
  [`aa_common_passwords()`](https://alexey-seleznev.pro/appauth/reference/aa_common_passwords.md)
  list, equal to the login ignoring case, or made of a single repeated
  character): `"off"` do not check, `"warn"` (default) accept the
  password but show a warning, `"reject"` reject the password. Existing
  passwords are not affected.

- login_max:

  Maximum login length (the login is trimmed and compared exactly,
  case-sensitively, when attempts are counted).

- autologin:

  Whether to use cookie-based auto sign-in. If `FALSE`, the user enters
  the password on every page load and no tokens are issued.

- session_days:

  Lifetime of the auto sign-in token, in days.

- session_check_seconds:

  How often to check that an open session is still allowed (the user has
  not been blocked or deleted), in seconds.

- attempts_retention_hours:

  How many hours to keep records of sign-in attempts.

- token_retention_days:

  How many days to keep expired and revoked tokens before deleting them.

- roles:

  Allowed user roles.

- admin_role:

  Administrator role, it must be one of `roles`. Only this role manages
  users, regardless of the application's permission matrix, and it is
  the role given to the first created user.

- must_change_default:

  Default state of the "require a password change at next sign-in"
  checkbox in the add-user dialog and when resetting a password. `TRUE`
  (default): a password set by an administrator is temporary, and the
  administrator clears the checkbox if a change is not needed. `FALSE`:
  the checkbox is off, the administrator turns it on.

- reset_enabled:

  Enable password recovery by email: a "Forgot your password?" link
  appears on the sign-in form. Default `FALSE`. Requires `send_reset`
  and `reset_base_url`.

- send_reset:

  Function that sends the email, `function(email, link, login)`: sends a
  message with the `link` to the `email` address (for example, using
  `emayili`). An error in the function does not interrupt the request
  and is not visible to the user, the reason goes into the
  `password_reset_requested` event.

- reset_base_url:

  Application address the link in the email points to, for example
  `"https://apps.example.com/my_app"`. It must use `https://`, except
  for local development on `http://127.0.0.1` or `http://localhost`.
  `?reset=<token>` is appended to it.

- reset_ttl_minutes:

  Lifetime of the password change link, in minutes.

- reset_max_per_hour:

  How many recovery emails can be sent to one user per hour, further
  requests are silently ignored.

- reset_max_per_minute:

  Overall limit of recovery emails across all users per minute
  (protection against spam).

- totp_enabled:

  Enable two-factor authentication (one-time TOTP codes from an
  authenticator app). Default `FALSE`. Requires `totp_key`. Two-factor
  protection is voluntary: each user enables it in the
  [`aa_totp_server()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_server.md)
  module, and users who have it enabled enter a code when signing in
  with a password.

- totp_key:

  Encryption key for TOTP secrets in the database, a string of at least
  16 characters (for example, from an environment variable). **Store it
  outside the database and outside the repository.** If the key is lost
  or replaced, existing secrets cannot be decrypted and users have to
  set up 2FA again (an administrator resets it in the user card).

- totp_issuer:

  Service name shown by the authenticator app.

- totp_window:

  How many 30-second steps in each direction of clock drift are
  tolerated (0 to 5, default 1).

- google_enabled:

  Enable sign-in with Google (OpenID Connect): a "Sign in with Google"
  button appears on the sign-in form. Default `FALSE`. Requires
  `google_client_id`, `google_client_secret` and `google_redirect_uri`.
  Only a user who already exists in the database and whose email equals
  the Google account address can sign in: sign-in never creates new
  users, the role is taken from the database. The application's
  two-factor code is not requested for Google sign-in (Google does the
  verification itself).

- google_client_id, google_client_secret:

  Identifier and secret of the OAuth client (type "Web application")
  from the Google Cloud Console. **Store the secret outside the database
  and outside the repository** (for example, in an environment
  variable).

- google_redirect_uri:

  Address Google returns the user to: the address of the application as
  users open it, for example `"https://apps.example.com/"`. It must
  exactly match an address in the "Authorized redirect URIs" list of the
  OAuth client. `https://` is allowed, and `http://localhost` for
  development.

- google_domains:

  Allowed organization domains (a vector, for example
  `c("example.com", "example.net")`). If set, sign-in is accepted only
  for accounts whose signed Google token contains one of these domains
  (`hd`, the primary Workspace domain of the organization) and whose
  email domain is also in the list. If the organization has secondary
  domains, list both the primary and the secondary ones. An empty value
  (`NULL`) disables the domain check, then only the match of the email
  with a user in the database decides.

- password_login:

  Allow sign-in with a login and password. Default `TRUE`. `FALSE` hides
  the password form and "Forgot your password?" and rejects such
  attempts on the server; possible only together with
  `google_enabled = TRUE`, otherwise there would be no way to sign in.
  Creating the first administrator on an empty database is still
  available.

- texts:

  Interface texts, a result of
  [`aa_texts()`](https://alexey-seleznev.pro/appauth/reference/aa_texts.md).

## Value

A list of settings of class `aa_settings`.

## Brute-force protection

If `max_failed_logins` failed attempts accumulate for one login within
`lockout_minutes` minutes, sign-in for this login is blocked for
`lockout_minutes` minutes starting from the last failed attempt.
Attempts made during the lock are not recorded and do not extend the
lock. In addition, if `max_failed_logins_per_minute` failed attempts
accumulate over the last minute across all logins together, sign-in is
temporarily closed for everyone: this stops password guessing spread
over many logins.

## Examples

``` r
# default settings
settings <- aa_settings()

# password recovery by email
settings <- aa_settings(
  reset_enabled  = TRUE,
  reset_base_url = "https://apps.example.com/my_app",
  send_reset = function(email, link, login) {
    message("Email for ", login, ": ", link)
  }
)

# sign-in with Google (secret from an environment variable), password stays
# as a fallback
settings <- aa_settings(
  google_enabled       = TRUE,
  google_client_id     = "1234-abc.apps.googleusercontent.com",
  google_client_secret = Sys.getenv("GOOGLE_OAUTH_CLIENT_SECRET", "secret"),
  google_redirect_uri  = "https://apps.example.com/",
  google_domains       = c("example.com", "example.net")
)

# stricter protection, Russian interface and custom roles
settings <- aa_settings(
  max_failed_logins = 3,
  lockout_minutes   = 30,
  password_min      = 10,
  roles             = c("admin", "editor", "viewer"),
  texts             = aa_texts("ru")
)
settings$lockout_minutes
#> [1] 30
```
