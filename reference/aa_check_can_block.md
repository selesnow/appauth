# Can a user be blocked

You cannot block yourself or the last active administrator.

## Usage

``` r
aa_check_can_block(conn, login, acting_login = NULL, settings = aa_settings())
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

`NULL` if allowed, otherwise the reason for refusal (in the settings
language).

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  aa_check_can_block(conn, "boss", acting_login = "boss")
  DBI::dbDisconnect(conn)
}
```
