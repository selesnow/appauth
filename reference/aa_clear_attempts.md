# Clear a login lockout caused by failed attempts

Deletes the failed login attempts of a login (successful ones stay), so
the login can be used again right away. A manual block by an
administrator
([`aa_set_blocked()`](https://alexey-seleznev.pro/appauth/reference/aa_set_blocked.md))
is not lifted by this function.

## Usage

``` r
aa_clear_attempts(conn, login, settings = aa_settings())
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- login:

  The entered login (exact, case-sensitive).

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

## Value

The number of deleted records (invisibly).

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  for (i in 1:5) aa_record_attempt(conn, "alsey", FALSE)
  aa_clear_attempts(conn, "alsey")
  aa_login_lock_remaining(conn, "alsey")
  DBI::dbDisconnect(conn)
}
```
