# Disable two-factor authentication

Erases the user's secret and recovery codes. The function **checks
nothing**: the
[`aa_totp_server()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_server.md)
module requires a password and a code before calling it, and reset by an
administrator
([`aa_users_server()`](https://alexey-seleznev.pro/appauth/reference/aa_users_server.md))
is allowed only to an administrator.

## Usage

``` r
aa_totp_disable(conn, login)
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- login:

  Login.

## Value

`TRUE` if something was reset for the user, otherwise `FALSE`
(invisibly).

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  aa_totp_disable(conn, "boss")
  DBI::dbDisconnect(conn)
}
```
