# List of users

List of users

## Usage

``` r
aa_list_users(conn)
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

## Value

A table with `login`, `role`, `blocked`, `created_at` and
`last_login_at` columns in creation order (for the dates see
[`aa_get_user()`](https://alexey-seleznev.pro/appauth/reference/aa_get_user.md)).
Password hashes are not included in the result.

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  aa_list_users(conn)
  DBI::dbDisconnect(conn)
}
```
