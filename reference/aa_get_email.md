# User email

User email

## Usage

``` r
aa_get_email(conn, login)
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- login:

  Login.

## Value

The address in lower case or `NA_character_` if no address is set or the
user does not exist. If the schema is not upgraded to version 7, also
`NA_character_`.

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  aa_set_email(conn, "boss", "Boss@Example.com")
  aa_get_email(conn, "boss")
  DBI::dbDisconnect(conn)
}
```
