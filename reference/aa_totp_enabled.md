# Whether two-factor authentication is enabled for a user

Whether two-factor authentication is enabled for a user

## Usage

``` r
aa_totp_enabled(conn, login)
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- login:

  Login.

## Value

`TRUE` or `FALSE` (`FALSE` both for a nonexistent user and if the schema
is not upgraded to version 8).

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  aa_totp_enabled(conn, "boss")
  DBI::dbDisconnect(conn)
}
```
