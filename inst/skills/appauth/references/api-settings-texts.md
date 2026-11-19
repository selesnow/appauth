# appauth reference: Settings and texts

Reference built from appauth 0.8.0. Generated automatically from the package help pages; do not edit by hand.

Functions in this section:
`aa_settings()`, `aa_settings_from_list()`, `aa_texts()`, `aa_text()`, `aa_text_keys()`

## aa_settings

```text
Authentication settings

Description:

     Collects the settings that control the package's behaviour: password rules,
     brute-force protection, data retention periods, the list of roles and the
     interface language. The settings object is passed to the other functions
     and modules of the package; the package uses no global variables.

Usage:

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
       texts = aa_texts("ru")
     )
     
Arguments:

max_failed_logins: Number of failed login attempts before the login is locked.

lockout_minutes: Window for counting failed attempts and lockout duration, minutes.

max_failed_logins_per_minute: Global limit of failed login attempts across all logins
          per minute.

password_min, password_max: Minimum and maximum length of a new password. The limit
          applies only to new and reset passwords; existing passwords are not affected.

password_policy: What to do with weak new passwords (from the 'aa_common_passwords()'
          list, equal to the login case-insensitively, or made of a single repeated
          character): '"off"' check nothing, '"warn"' (default) accept the password but
          show a warning, '"reject"' reject the password. Existing passwords are not
          affected.

login_max: Maximum login length (the login is also lower-cased and trimmed at the edges
          when counting attempts).

autologin: Whether to use cookie auto-login. If 'FALSE', the user enters the password
          on every page load and no tokens are issued.

session_days: Lifetime of an auto-login token, days.

session_check_seconds: How often to check that an open session is still allowed (the
          user has not been blocked or deleted), seconds.

attempts_retention_hours: How many hours to keep login-attempt records.

token_retention_days: How many days to keep expired and revoked tokens before deleting
          them.

   roles: Allowed user roles.

admin_role: The administrator role; it must be one of 'roles'. Only this role manages
          users, regardless of the app's permission matrix, and it is the role given to
          the first created user.

must_change_default: Default state of the "require a password change at next login"
          checkbox in the add-user dialog and on password reset. 'TRUE' (default): the
          password set by the administrator is temporary, and the administrator clears
          the checkbox if no change is needed. 'FALSE': the checkbox is off, and the
          administrator turns it on themselves.

reset_enabled: Enable password recovery by email: a "Forgot password?" link appears on
          the login form. 'FALSE' by default. Requires 'send_reset' and
          'reset_base_url'.

send_reset: Function that sends the email, function(email, link, login): sends an email
          with the link 'link' to the address 'email' (for example, via 'emayili'). An
          error in the function does not abort the request and is not visible to the
          user; the reason goes into the 'password_reset_requested' event.

reset_base_url: Address of the app that the link in the email points to, for example
          '"https://apps.example.com/my_app"'. ?reset=<token> is appended to it.

reset_ttl_minutes: Lifetime of the password-reset link, minutes.

reset_max_per_hour: How many recovery emails can be sent to one user per hour; further
          requests are silently ignored.

reset_max_per_minute: Global limit of recovery emails across all users per minute
          (protection against spam mailings).

totp_enabled: Enable two-factor authentication (one-time TOTP codes from an
          authenticator app). 'FALSE' by default. Requires 'totp_key'. Two-factor
          protection is voluntary: each user enables it themselves in the
          'aa_totp_server()' module, and users who have it enabled enter a code when
          logging in with a password.

totp_key: Encryption key for TOTP secrets in the database, a string of at least 16
          characters (for example, from an environment variable). *Keep it outside the
          database and outside the repository.* If the key is lost or replaced,
          existing secrets cannot be decrypted and users will have to enroll 2FA again
          (an administrator resets it in the user card).

totp_issuer: Service name shown by the authenticator app.

totp_window: How many 30-second steps in each direction of clock drift are tolerated
          (0 to 5, default 1).

google_enabled: Enable Google sign-in (OpenID Connect): a "Sign in with Google" button
          appears on the login form. 'FALSE' by default. Requires 'google_client_id',
          'google_client_secret' and 'google_redirect_uri'. Only a user who already
          exists in the database and whose email equals the Google account address can
          sign in: sign-in does not create new users, and the role is taken from the
          database. The app's two-factor code is not requested for Google sign-in
          (Google itself does the verification).

google_client_id, google_client_secret: ID and secret of the OAuth client (type "Web
          application") from Google Cloud Console. *Keep the secret outside the
          database and outside the repository* (for example, in an environment
          variable).

google_redirect_uri: Address Google returns the user to: the app address as users open
          it, for example '"https://apps.example.com/"'. It must match exactly an
          address in the OAuth client's "Authorized redirect URIs" list. https:// is
          allowed, and http://localhost for development.

google_domains: Allowed organization domains (a vector, for example 'c("example.com",
          "example.net")'). If set, sign-in is accepted only for accounts whose signed
          Google token carries one of these domains ('hd', the primary Workspace
          domain of the organization) and whose email domain is also in the list. If
          the organization has secondary domains, list both the primary and the
          secondary ones. An empty value ('NULL') disables the domain check; then the
          match of the email with a user in the database decides.

password_login: Allow login by login and password. 'TRUE' by default. 'FALSE' hides the
          password form and "Forgot password?" and rejects such attempts on the
          server; possible only together with 'google_enabled = TRUE', otherwise there
          would be no way to sign in. Creating the first administrator on an empty
          database remains available.

   texts: Interface texts, the result of 'aa_texts()'.

Value:

     A settings list of class 'aa_settings'.

Brute-force protection:

     If 'max_failed_logins' failed attempts accumulate for one login within
     'lockout_minutes' minutes, login under that login is blocked for 'lockout_minutes'
     minutes from the last failed attempt. Attempts during a lockout are not recorded
     and do not extend it. In addition, if 'max_failed_logins_per_minute' failed
     attempts accumulate across all logins together in the last minute, login is
     temporarily closed for everyone: this stops guessing across many logins at once.

Examples:

     # default settings
     settings <- aa_settings()
     
     # password recovery by email
     settings <- aa_settings(
       reset_enabled  = TRUE,
       reset_base_url = "https://apps.example.com/my_app",
       send_reset     = function(email, link, login) message("Email for ", login, ": ", link)
     )
     
     # Google sign-in (secret from an environment variable), password stays as a fallback
     settings <- aa_settings(
       google_enabled       = TRUE,
       google_client_id     = "1234-abc.apps.googleusercontent.com",
       google_client_secret = Sys.getenv("GOOGLE_OAUTH_CLIENT_SECRET", "secret"),
       google_redirect_uri  = "https://apps.example.com/",
       google_domains       = c("example.com", "example.net")
     )
     
     # stricter protection, English interface and custom roles
     settings <- aa_settings(
       max_failed_logins = 3,
       lockout_minutes   = 30,
       password_min      = 10,
       roles             = c("admin", "editor", "viewer"),
       texts             = aa_texts("en")
     )
     settings$lockout_minutes
```

## aa_settings_from_list

```text
Settings from a list (for example, from a 'config.yaml' section)

Description:

     Convenient when the security settings are kept in the app config. Only known
     'aa_settings()' parameters are taken, the rest are ignored, and any parameter can
     be overridden with the '...' arguments.

Usage:

     aa_settings_from_list(x = NULL, ...)
     
Arguments:

       x: A list of settings, for example 'yaml::read_yaml("config.yaml")$security', or
          'NULL'.

     ...: 'aa_settings()' parameters that replace the values from 'x'.

Value:

     A settings list of class 'aa_settings'.

Examples:

     security <- list(max_failed_logins = 3, lockout_minutes = 10, unknown_key = 1)
     settings <- aa_settings_from_list(security, texts = aa_texts("en"))
     settings$max_failed_logins
```

## aa_texts

```text
Interface and message texts

Description:

     Returns the set of texts for the chosen language. Any string can be replaced with
     your own by giving its name and the new value. Texts with value substitution
     contain the markers %d (number) and %s (string); the values are filled in by
     'aa_text()'.

Usage:

     aa_texts(lang = c("ru", "en"), ...)
     
Arguments:

    lang: Text language: '"ru"' (default) or '"en"'.

     ...: Your own texts as 'key = "string"'; they replace the standard ones.

Details:

     Available keys can be listed with 'aa_text_keys()'.

Value:

     A named list of strings of class 'aa_texts'.

Examples:

     # English texts
     texts <- aa_texts("en")
     
     # Russian texts with a custom login button label
     texts <- aa_texts("ru", login_button = "Войти в систему")
     texts$login_button
```

## aa_text

```text
Get a text by key

Description:

     Returns a string from a set of texts. If values are passed, they are substituted
     into the string following the rules of 'sprintf()'.

Usage:

     aa_text(x, key, ...)
     
Arguments:

       x: A set of texts (the result of 'aa_texts()') or settings (the result of
          'aa_settings()').

     key: Text key, see 'aa_text_keys()'.

     ...: Values to substitute into the %d and %s markers.

Value:

     A string.

Examples:

     texts <- aa_texts("ru")
     aa_text(texts, "login_button")
     aa_text(texts, "locked", 15)
```

## aa_text_keys

```text
Interface text keys

Description:

     Interface text keys

Usage:

     aa_text_keys()
     
Value:

     A vector of key names that can be overridden in 'aa_texts()'.

Examples:

     aa_text_keys()
```

