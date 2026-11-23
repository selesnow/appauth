# User who owns a registration link

Checks the confirmation token without changing anything: the token must
be unused, not expired, and the login and address must still be
available. The new password form is shown only for a working link.

## Usage

``` r
aa_registration_token_login(conn, token)
```

## Arguments

- conn:

  Connection with the
  [`aa_init_db()`](https://alexey-seleznev.pro/appauth/reference/aa_init_db.md)
  schema.

- token:

  Token from the `?register=<token>` link.

## Value

The login or `NULL`.

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_registration_token_login(conn, "not-a-token")
  DBI::dbDisconnect(conn)
}
```
