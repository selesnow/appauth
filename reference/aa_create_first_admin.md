# Create the first user (administrator)

Creates a user with the `admin_role` role from the settings **only if
the `users` table is empty**. The check and the insert run in one SQL
statement, so of two simultaneous requests (two browser tabs, two
sessions) only one succeeds.

## Usage

``` r
aa_create_first_admin(conn, login, password, settings = aa_settings())
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- login:

  Login.

- password:

  The password in plain text (only the hash goes to the database).

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

## Value

`TRUE` if the administrator was created, `FALSE` if users already exist.

## Details

The login and password are checked by the same rules as in
[`aa_create_user()`](https://alexey-seleznev.pro/appauth/reference/aa_create_user.md)
(on a violation, an error of class `appauth_error_user`).

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  aa_create_first_admin(conn, "second", "second-password")
  DBI::dbDisconnect(conn)
}
```
