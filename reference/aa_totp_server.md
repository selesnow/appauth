# Two-factor authentication module: server

The user enables and disables two-factor authentication (TOTP) on their
own:

## Usage

``` r
aa_totp_server(id, conn, auth, settings = aa_settings(), on_event = NULL)
```

## Arguments

- id:

  Module id, the same as in
  [`aa_totp_ui()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_ui.md).

- conn:

  Database connection.

- auth:

  Authentication object, the result of
  [`aa_auth_server()`](https://alexey-seleznev.pro/appauth/reference/aa_auth_server.md).

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md)
  with `totp_enabled = TRUE`.

- on_event:

  Event hook `function(event, user, session_id, value)` or `NULL`.

## Value

A list with a `refresh()` function that redraws the block.

## Details

- **enabling**: a button creates a secret
  ([`aa_totp_setup()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_setup.md)),
  shows a QR code (if the `qrcode` package is installed) and a key for
  manual entry, and after a code from the authenticator app is entered
  ([`aa_totp_enable()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_enable.md))
  turns protection on and shows 10 recovery codes **once**. The user's
  other sessions are ended on enabling;

- **disabling**: needs the password and a code (or a recovery code),
  otherwise whoever took over an open session could remove the
  protection.

Wrong codes count as failed login attempts
([`aa_record_attempt()`](https://alexey-seleznev.pro/appauth/reference/aa_record_attempt.md)),
so guessing a code on the account page locks the login the same way as
guessing a password. Events: `totp_enabled`, `totp_disabled`,
`totp_failed`.

## See also

[`aa_totp_ui()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_ui.md),
[`aa_auth_server()`](https://alexey-seleznev.pro/appauth/reference/aa_auth_server.md)

## Examples

``` r
if (FALSE) { # \dontrun{
auth <- aa_auth_server("auth", conn, settings)
shiny::observe({
  if (auth$logged_in()) aa_totp_server("totp", conn, auth, settings, on_event
  = log_event)
})
} # }
```
