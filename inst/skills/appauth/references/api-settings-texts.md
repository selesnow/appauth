# appauth reference: Settings and texts

Package version: 0.11.2. This file is generated automatically from the package help (`dev/skills/build_reference.R`) and must not be edited by hand.

Functions in this section:
`aa_settings()`, `aa_settings_from_list()`, `aa_texts()`, `aa_text()`, `aa_text_keys()`

## Contents

- [aa_settings](#aa_settings)
- [aa_settings_from_list](#aa_settings_from_list)
- [aa_texts](#aa_texts)
- [aa_text](#aa_text)
- [aa_text_keys](#aa_text_keys)

## aa_settings

```text
Authorization settings

Description:

     Builds the settings that control the behavior of the package: password rules,
     brute-force protection, data retention periods, the list of roles and the interface
     language. The settings object is passed to the other functions and modules of the
     package; the package does not use global variables.

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
       registration_enabled = FALSE,
       registration_verify_email = TRUE,
       registration_role = "viewer",
       registration_domains = NULL,
       registration_max_per_hour = 10,
       google_signup = FALSE,
       google_signup_require_domains = TRUE,
       texts = aa_texts("en")
     )

Arguments:

max_failed_logins: Number of failed sign-in attempts before the login is locked.

lockout_minutes: Window for counting failed attempts and the duration of the lock, in
          minutes.

max_failed_logins_per_minute: Overall limit of failed sign-in attempts across all logins
          per minute.

password_min, password_max: Minimum and maximum length of a new password. The limit
          applies only to new and reset passwords, existing passwords are not affected.

password_policy: What to do with weak new passwords (from the 'aa_common_passwords()'
          list, equal to the login ignoring case, or made of a single repeated
          character): '"off"' do not check, '"warn"' (default) accept the password but
          show a warning, '"reject"' reject the password. Existing passwords are not
          affected.

login_max: Maximum login length (the login is trimmed and compared exactly,
          case-sensitively, when attempts are counted).

autologin: Whether to use cookie-based auto sign-in. If 'FALSE', the user enters the
          password on every page load and no tokens are issued.

session_days: Lifetime of the auto sign-in token, in days.

session_check_seconds: How often to check that an open session is still allowed (the user
          has not been blocked or deleted), in seconds.

attempts_retention_hours: How many hours to keep records of sign-in attempts.

token_retention_days: How many days to keep expired and revoked tokens before deleting
          them.

   roles: Allowed user roles.

admin_role: Administrator role, it must be one of 'roles'. Only this role manages users,
          regardless of the application's permission matrix, and it is the role given to
          the first created user.

must_change_default: Default state of the "require a password change at next sign-in"
          checkbox in the add-user dialog and when resetting a password. 'TRUE'
          (default): a password set by an administrator is temporary, and the
          administrator clears the checkbox if a change is not needed. 'FALSE': the
          checkbox is off, the administrator turns it on.

reset_enabled: Enable password recovery by email: a "Forgot your password?" link appears
          on the sign-in form. Default 'FALSE'. Requires 'send_reset' and
          'reset_base_url'.

send_reset: Function that sends the email, function(email, link, login): sends a message
          with the 'link' to the 'email' address (for example, using 'emayili'). An error
          in the function does not interrupt the request and is not visible to the user,
          the reason goes into the 'password_reset_requested' event.

reset_base_url: Application address the link in the email points to, for example
          '"https://apps.example.com/my_app"'. It must use https://, except for local
          development on http://127.0.0.1 or http://localhost. ?reset=<token> is appended
          to it.

reset_ttl_minutes: Lifetime of the password change link, in minutes.

reset_max_per_hour: How many recovery emails can be sent to one user per hour, further
          requests are silently ignored.

reset_max_per_minute: Overall limit of recovery emails across all users per minute
          (protection against spam).

totp_enabled: Enable two-factor authentication (one-time TOTP codes from an authenticator
          app). Default 'FALSE'. Requires 'totp_key'. Two-factor protection is voluntary:
          each user enables it in the 'aa_totp_server()' module, and users who have it
          enabled enter a code when signing in with a password.

totp_key: Encryption key for TOTP secrets in the database, a string of at least 16
          characters (for example, from an environment variable). *Store it outside the
          database and outside the repository.* If the key is lost or replaced, existing
          secrets cannot be decrypted and users have to set up 2FA again (an
          administrator resets it in the user card).

totp_issuer: Service name shown by the authenticator app.

totp_window: How many 30-second steps in each direction of clock drift are tolerated (0
          to 5, default 1).

google_enabled: Enable sign-in with Google (OpenID Connect): a "Sign in with Google"
          button appears on the sign-in form. Default 'FALSE'. Requires
          'google_client_id', 'google_client_secret' and 'google_redirect_uri'. Only a
          user who already exists in the database and whose email equals the Google
          account address can sign in. With 'google_signup = TRUE' a new user is created
          from the verified email; otherwise sign-in never creates users. The role of
          existing users is taken from the database. The application's two-factor code is
          not requested for Google sign-in (Google does the verification itself).

google_client_id, google_client_secret: Identifier and secret of the OAuth client (type
          "Web application") from the Google Cloud Console. *Store the secret outside the
          database and outside the repository* (for example, in an environment variable).

google_redirect_uri: Address Google returns the user to: the address of the application
          as users open it, for example '"https://apps.example.com/"'. It must exactly
          match an address in the "Authorized redirect URIs" list of the OAuth client.
          https:// is allowed, and http://localhost for development.

google_domains: Allowed organization domains (a vector, for example 'c("example.com",
          "example.net")'). If set, sign-in is accepted only for accounts whose signed
          Google token contains one of these domains ('hd', the primary Workspace domain
          of the organization) and whose email domain is also in the list. If the
          organization has secondary domains, list both the primary and the secondary
          ones. An empty value ('NULL') disables the domain check, then only the match of
          the email with a user in the database decides.

password_login: Allow sign-in with a login and password. Default 'TRUE'. 'FALSE' hides
          the password form and "Forgot your password?" and rejects such attempts on the
          server; possible only together with 'google_enabled = TRUE', otherwise there
          would be no way to sign in. Creating the first administrator on an empty
          database is still available.

registration_enabled: Allow visitors to create their own accounts from the sign-in form.
          Default 'FALSE'. The link appears only when the database already has users: on
          an empty database the first administrator is created as before.

registration_verify_email: Require visitors to confirm their email address before the
          account is created. Default 'TRUE'. Requires 'send_reset' and 'reset_base_url';
          with 'FALSE' the account is created immediately.

registration_role: Role given to self-registered users. Default '"viewer"'. It must be
          one of 'roles' and cannot be 'admin_role', so registration never grants
          administrative rights. Used for both the button and Google sign-up.

registration_domains: Allowed email domains for self-registration (a vector like
          'c("example.com")'). 'NULL' (default) allows any domain.

registration_max_per_hour: Maximum number of registration requests per hour across all
          visitors.

google_signup: Create an account automatically on the first sign-in with Google if the
          email is not in the database. Default 'FALSE'. Requires 'google_enabled =
          TRUE'; the login is derived from the email address, the email is taken from the
          verified Google token, and the role is 'registration_role'.

google_signup_require_domains: Require a non-empty 'google_domains' when 'google_signup =
          TRUE'. Default 'TRUE': without a domain check any Google account could create
          an account. Set to 'FALSE' only for a deliberately open application.

   texts: Interface texts, a result of 'aa_texts()'.

Value:

     A list of settings of class 'aa_settings'.

Brute-force protection:

     If 'max_failed_logins' failed attempts accumulate for one login within
     'lockout_minutes' minutes, sign-in for this login is blocked for 'lockout_minutes'
     minutes starting from the last failed attempt. Attempts made during the lock are not
     recorded and do not extend the lock. In addition, if 'max_failed_logins_per_minute'
     failed attempts accumulate over the last minute across all logins together, sign-in
     is temporarily closed for everyone: this stops password guessing spread over many
     logins.

Examples:

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

     # open registration with email confirmation and Google sign-up
     settings <- aa_settings(
       registration_enabled = TRUE,
       google_enabled       = TRUE,
       google_signup        = TRUE,
       google_client_id     = "1234-abc.apps.googleusercontent.com",
       google_client_secret = Sys.getenv("GOOGLE_OAUTH_CLIENT_SECRET", "secret"),
       google_redirect_uri  = "https://apps.example.com/",
       google_domains       = c("example.com"),
       reset_base_url       = "https://apps.example.com/my_app",
       send_reset = function(email, link, login) {
         message("Email for ", login, ": ", link)
       }
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
```

## aa_settings_from_list

```text
Settings from a list (for example, from a 'config.yaml' section)

Description:

     Convenient when the protection settings are kept in the application config. Only
     known parameters of 'aa_settings()' are taken, the rest are ignored, and any
     parameter can be overridden with the '...' arguments.

Usage:

     aa_settings_from_list(x = NULL, ...)

Arguments:

       x: A list of settings, for example 'yaml::read_yaml("config.yaml")$security', or
          'NULL'.

     ...: Parameters of 'aa_settings()' that replace the values from 'x'.

Value:

     A list of settings of class 'aa_settings'.

Examples:

     security <- list(max_failed_logins = 3, lockout_minutes = 10, unknown_key =
     1)
     settings <- aa_settings_from_list(security, texts = aa_texts("en"))
     settings$max_failed_logins
```

## aa_texts

```text
Interface and message texts

Description:

     Returns the set of texts for the chosen language. Any string can be replaced with
     your own by passing its key and the new value. Texts with substituted values contain
     %d (number) and %s (string) placeholders, the values are filled in by 'aa_text()'.

Usage:

     aa_texts(lang = c("en", "ru"), ...)

Arguments:

    lang: Language of the texts: '"en"' (default) or '"ru"'.

     ...: Your own texts as 'key = "string"', they replace the default ones.

Details:

     Available keys are listed by 'aa_text_keys()'.

Value:

     A named list of strings of class 'aa_texts'.

Examples:

     # English texts (default)
     texts <- aa_texts()

     # English texts with a custom sign-in button label
     texts <- aa_texts("en", login_button = "Log in")
     texts$login_button

     # Russian texts
     texts <- aa_texts("ru")
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

       x: A set of texts (result of 'aa_texts()') or settings (result of
          'aa_settings()').

     key: Text key, see 'aa_text_keys()'.

     ...: Values for the %d and %s placeholders.

Value:

     A string.

Examples:

     texts <- aa_texts("en")
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

