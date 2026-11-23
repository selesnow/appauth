# User by login

The login is matched exactly, case-sensitive. The password is not
included in the result.

## Usage

``` r
aa_get_user(conn, login)
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- login:

  Login.

## Value

A one-row table with `login`, `role`, `blocked`, `created_at` and
`last_login_at` columns, or `NULL` if there is no such user. Dates are
stored as text `"YYYY-MM-DD HH:MM:SS"` in UTC; for users created before
version 0.3.0 `created_at` is empty (`NA`), and `last_login_at` is empty
until the user logs in with a password.

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  aa_get_user(conn, "boss")
  aa_get_user(conn, "nobody")
  DBI::dbDisconnect(conn)
}
```
