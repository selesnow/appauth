# Set, change or remove a user's email

The address is needed for password recovery
([`aa_request_password_reset()`](https://alexey-seleznev.pro/appauth/reference/aa_request_password_reset.md)).
It is stored in lower case, and two users cannot have the same address.
An empty value (`NULL`, `NA` or `""`) removes the address. Errors
(invalid format, address taken, no such user) have the class
`appauth_error_user` and a text in the settings language.

## Usage

``` r
aa_set_email(conn, login, email, settings = aa_settings())
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- login:

  Login.

- email:

  An address or an empty value to remove it.

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

## Value

`TRUE` if the address was saved and `FALSE` if it was removed
(invisibly).

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  aa_set_email(conn, "boss", "boss@example.com")
  aa_set_email(conn, "boss", NULL)
  DBI::dbDisconnect(conn)
}
```
