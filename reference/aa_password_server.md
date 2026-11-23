# Own password change module: server

The user confirms the current password and sets a new one
([`aa_change_own_password()`](https://alexey-seleznev.pro/appauth/reference/aa_change_own_password.md)).
Auto-login tokens of the other sessions are revoked, the current session
keeps working. The module reports the change to the `on_event` hook with
the `password_changed` event.

## Usage

``` r
aa_password_server(id, conn, auth, settings = aa_settings(), on_event = NULL)
```

## Arguments

- id:

  Module id, the same as in
  [`aa_password_ui()`](https://alexey-seleznev.pro/appauth/reference/aa_password_ui.md).

- conn:

  Database connection.

- auth:

  Authentication object, the result of
  [`aa_auth_server()`](https://alexey-seleznev.pro/appauth/reference/aa_auth_server.md).

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

- on_event:

  Event hook `function(event, user, session_id, value)` or `NULL`.

## Value

A list with the reactive value `changed`: the number of successful
password changes in this session (can be used to close a window or show
a message).

## See also

[`aa_password_ui()`](https://alexey-seleznev.pro/appauth/reference/aa_password_ui.md)

## Examples

``` r
if (FALSE) { # \dontrun{
auth <- aa_auth_server("auth", conn)
aa_password_server("password", conn, auth, on_event = log_event)
} # }
```
