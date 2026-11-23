# Set a new password by the link from the email

Checks the token
([`aa_reset_token_login()`](https://alexey-seleznev.pro/appauth/reference/aa_reset_token_login.md)),
checks the new password against the rules from the settings and writes
it. The token is one-time: a weak password is rejected with an error and
does not spend the token, and after a successful change the link stops
working. Along with the password, all of the user's auto-login tokens
are revoked, the other recovery links are consumed, and the password
change requirement and the lock for failed login attempts are cleared.

## Usage

``` r
aa_reset_password_with_token(conn, token, password, settings = aa_settings())
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- token:

  Token from the link (the `reset` parameter of the address bar).

- password:

  New password.

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

## Value

The login of the user whose password was changed (invisibly).

## Details

A wrong, expired or used link raises an error of class
`appauth_error_user` with `reason = "reset_link_invalid"`, a weak
password an error of the same class with a password reason.

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  tryCatch(
    aa_reset_password_with_token(conn, "not-a-token", "new-password"),
    appauth_error_user = function(e) conditionMessage(e)
  )
  DBI::dbDisconnect(conn)
}
```
