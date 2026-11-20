# Delete a user

Deletes the user record, **the user's autologin tokens and failed login
attempts**. This matters: without deleting the tokens, a person who
later gets the same login could log in with the cookie of the previous
owner.

## Usage

``` r
aa_delete_user(conn, login, acting_login = NULL, settings = aa_settings())
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- login:

  Login.

- acting_login:

  Login of the person blocking (the current administrator), or `NULL`
  (for example, when called from a script).

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

## Value

The number of deleted users (invisibly).

## Details

Deletion is performed only if
[`aa_check_can_delete()`](https://alexey-seleznev.pro/appauth/reference/aa_check_can_delete.md)
allows it (you cannot delete yourself or the last active administrator),
otherwise an error of class `appauth_error_user`. A session open for the
user is closed at the login module's next check.

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  aa_create_user(conn, "worker", "worker-password", "user")
  aa_delete_user(conn, "worker", acting_login = "boss")
  aa_list_users(conn)
  DBI::dbDisconnect(conn)
}
```
