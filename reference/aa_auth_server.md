# Sign-in module: server

Sign-in with login and password protected against guessing
([`aa_login_gate()`](https://alexey-seleznev.pro/appauth/reference/aa_login_gate.md)),
creation of the first administrator on an empty database, auto-login by
cookie (if enabled in the settings) and sign-out. The module reports all
events to the `on_event` hook (catalog in
[`aa_events()`](https://alexey-seleznev.pro/appauth/reference/aa_events.md))
and writes nothing to logs itself.

## Usage

``` r
aa_auth_server(
  id,
  conn,
  settings = aa_settings(),
  on_event = NULL,
  title = NULL,
  logo = NULL,
  cookie_name = "appauth_token"
)
```

## Arguments

- id:

  Module id, the same as in
  [`aa_auth_ui()`](https://alexey-seleznev.pro/appauth/reference/aa_auth_ui.md).

- conn:

  Database connection with the
  [`aa_init_db()`](https://alexey-seleznev.pro/appauth/reference/aa_init_db.md)
  schema.

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

- on_event:

  Event hook `function(event, user, session_id, value)` or `NULL`.

- title:

  Sign-in form title. Defaults to the `login_title` text.

- logo:

  Address of an image above the title (for example `"logo.png"` from the
  `www` folder) or `NULL`.

- cookie_name:

  Auto-login cookie name. Cookies are not isolated by port, so apps on
  the same host need different names.

## Value

A list: `user` (reactive value, a list with `login` and `role` or
`NULL`), `logged_in` (reactive logical), `role` (reactive role or
`NULL`), a `token()` function (the auto-login token of this session or
`NULL`, needed by
[`aa_session_guard()`](https://alexey-seleznev.pro/appauth/reference/aa_session_guard.md)),
a `logout(reason = NULL, reload = FALSE)` function and a
`logout_all(reload = TRUE)` function. Without `reason` this is an
ordinary sign-out (event `logout`); with `reason` (`"blocked"`,
`"deleted"`, `"role_changed"`, `"token_revoked"`) it is forced
(`session_forced_logout`). With `reload = TRUE` the page is reloaded so
that the modules of the previous user disappear.

`logout_all()` is "sign out on all devices": it revokes all tokens of
the user (event `sessions_revoked`) and signs out immediately; open
sessions on other devices are closed by
[`aa_session_guard()`](https://alexey-seleznev.pro/appauth/reference/aa_session_guard.md)
at the next check. Show the user a confirmation dialog before calling
it: the button kicks them out everywhere.

## Details

If the password was set by an administrator (`must_change`), the
password change form is shown after the correct password is entered, and
the user gets into the app only after the change.

## Two-factor authentication

With `totp_enabled = TRUE` in the settings
([`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md)),
a user who has 2FA enabled
([`aa_totp_server()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_server.md))
enters, after the correct password, a code from the authenticator app or
a recovery code. Until then no auto-login token is issued and the
successful login attempt is not recorded: wrong codes count as failed
login attempts, and the login is locked by the same rules as for
password guessing. Auto-login by cookie does not ask for the second
factor (the cookie was issued after it was passed). The module reports
the events `totp_failed` and `recovery_code_used`.

## Password recovery by email

With `reset_enabled = TRUE` in the settings
([`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md)),
a "Forgot password?" link appears on the sign-in form. The user enters a
login or email and is sent an email with a link
`<reset_base_url>/?reset=<token>`, and the on-screen answer is always
the same, whether or not the user was found. The module itself reads the
`reset` parameter from the address bar, removes it from the address and
shows the new password form if the link works. After the password is
changed the user signs in as usual: they are not signed in
automatically. The module reports the events `password_reset_requested`,
`password_reset_done` and `password_reset_failed`. Logic without UI:
[`aa_request_password_reset()`](https://alexey-seleznev.pro/appauth/reference/aa_request_password_reset.md)
and
[`aa_reset_password_with_token()`](https://alexey-seleznev.pro/appauth/reference/aa_reset_password_with_token.md).

## Sign-in with Google

With `google_enabled = TRUE` in the settings
([`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md)),
a "Sign in with Google" button appears on the sign-in form. The user
confirms the sign-in with Google and returns to `google_redirect_uri`;
the package checks the signature and contents of the Google token, the
organization domain (`google_domains`) and finds the user **by email
among already created ones**: sign-in does not create new users, the
role is taken from the database, a blocked user does not get in. The
two-factor code is not asked for in this case (Google does the
confirmation). `state` from the address is compared with a short cookie
of the browser that started the sign-in, so someone else's return link
cannot be slipped in. With `password_login = FALSE` the password form is
hidden and password sign-in attempts are rejected on the server. The
module reports `login_success` with the value `google` and
`google_login_failed` (reason and email in `value`); on refusal the user
sees a generic text. If the page is opened not at the
`google_redirect_uri` address (for example, the app is opened by IP
while the return is configured for a domain), the button sends the user
to the return address and sign-in starts there on its own (parameter
`?google=1`): `state` is stored in the cookie of the site address, and
cookies for an IP and for a domain are different. Password sign-in and
cookie auto-login work independently at each address.

The role and login are taken from the database, not from the entered
string. The `conn` connection belongs to the app: close it when the
session ends.

## See also

[`aa_auth_ui()`](https://alexey-seleznev.pro/appauth/reference/aa_auth_ui.md)

## Examples

``` r
if (FALSE) { # \dontrun{
server <- function(input, output, session) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), "app.db")
  aa_init_db(conn)
  session$onSessionEnded(function() DBI::dbDisconnect(conn))

  auth <- aa_auth_server("auth", conn, on_event = log_event)
  output$app <- shiny::renderUI(if (auth$logged_in()) main_ui())
}
} # }
```
