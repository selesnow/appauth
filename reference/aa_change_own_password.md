# Change your own password

For the user themselves: the current password must be confirmed. The new
password is checked against the rules from the settings and must differ
from the current one. Autologin tokens of other sessions are revoked;
the token of the current session (`keep_token`) stays. The password
change requirement (`must_change`) is cleared.

## Usage

``` r
aa_change_own_password(
  conn,
  login,
  old_password,
  new_password,
  settings = aa_settings(),
  keep_token = NULL
)
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- login:

  Login.

- old_password:

  The current password.

- new_password:

  The new password.

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

- keep_token:

  Autologin token of the current session that must not be revoked.

## Value

`TRUE` (invisibly).

## Details

Errors (wrong current password, weak or the same password) have class
`appauth_error_user` and text in the settings language.

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  aa_change_own_password(conn, "boss", "boss-password", "new-boss-password")
  DBI::dbDisconnect(conn)
}
```
