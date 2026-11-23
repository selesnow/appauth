# Forcibly end invalid sessions

Every `session_check_seconds` (from
[`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md))
checks the open session
([`aa_user_session_valid()`](https://alexey-seleznev.pro/appauth/reference/aa_user_session_valid.md)).
If the user has been blocked, deleted or had their role changed, the
session is ended through `auth$logout()`: the `on_event` hook receives
`session_forced_logout` with the reason, and tokens are revoked. Thanks
to this, blocking and role downgrades take effect within the check
interval rather than at the next sign-in.

## Usage

``` r
aa_session_guard(
  auth,
  conn,
  settings = aa_settings(),
  reload = TRUE,
  cleanup_minutes = 60
)
```

## Arguments

- auth:

  A result of
  [`aa_auth_server()`](https://alexey-seleznev.pro/appauth/reference/aa_auth_server.md).

- conn:

  Database connection.

- settings:

  Settings, a result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

- reload:

  Reload the page after sign-out so that the modules of the previous
  user disappear. `TRUE` is recommended.

- cleanup_minutes:

  How often to clean up outdated records, in minutes.

## Value

Invisibly a Shiny observer (it can be stopped with `$destroy()`).

## Details

If the database cannot be read, the session is not ended.

The session token (`auth$token()`) is checked too: a password reset of a
user or "end all sessions" also end open sessions. Every
`cleanup_minutes` the guard also deletes outdated sign-in attempts and
tokens
([`aa_cleanup()`](https://alexey-seleznev.pro/appauth/reference/aa_cleanup.md)).

## Examples

``` r
if (FALSE) { # \dontrun{
auth <- aa_auth_server("auth", conn)
aa_session_guard(auth, conn)
} # }
```
