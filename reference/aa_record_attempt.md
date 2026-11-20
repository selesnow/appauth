# Record a login attempt

Stores the result of a login attempt for brute-force protection.
Attempts with an empty login are not recorded. Call it only for attempts
made NOT during a lockout: attempts during a lockout are not recorded so
as not to extend it.

## Usage

``` r
aa_record_attempt(conn, login, success, settings = aa_settings())
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- login:

  The entered login (exact, case-sensitive).

- success:

  `TRUE` for a successful login (resets the failure counter), `FALSE`
  for a failed attempt.

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

## Value

`TRUE` if the attempt was recorded, `FALSE` if the login is empty
(invisibly).

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_record_attempt(conn, "alsey", success = FALSE)
  DBI::dbDisconnect(conn)
}
```
