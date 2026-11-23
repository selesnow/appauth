# Block or unblock a user

A manual block closes login for the user (both by password and by
autologin token) without deleting the account, until an administrator
lifts it. When blocking, **all autologin tokens** of the user are
revoked, and a session already open for the user is closed at the login
module's next check.

## Usage

``` r
aa_set_blocked(
  conn,
  login,
  blocked = TRUE,
  acting_login = NULL,
  settings = aa_settings()
)
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- login:

  Login.

- blocked:

  `TRUE` to block, `FALSE` to unblock.

- acting_login:

  Login of the person blocking (the current administrator), or `NULL`
  (for example, when called from a script).

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

## Value

The number of changed users (invisibly).

## Details

Blocking is performed only if
[`aa_check_can_block()`](https://alexey-seleznev.pro/appauth/reference/aa_check_can_block.md)
allows it (you cannot block yourself or the last active administrator),
otherwise an error of class `appauth_error_user`. Unblocking needs no
checks and does not restore revoked tokens; the user has to log in
again.

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  aa_create_user(conn, "worker", "worker-password", "user")
  aa_set_blocked(conn, "worker", TRUE, acting_login = "boss")
  aa_get_user(conn, "worker")
  aa_set_blocked(conn, "worker", FALSE)
  DBI::dbDisconnect(conn)
}
```
