# Is the global failed login limit exceeded

Counts failed attempts across all logins together over the last minute.
If there are at least `max_failed_logins_per_minute` of them, login is
temporarily closed for everyone: this stops guessing across many logins
and growth of the attempts table.

## Usage

``` r
aa_global_throttled(conn, settings = aa_settings())
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

## Value

`TRUE` or `FALSE`.

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_global_throttled(conn)
  DBI::dbDisconnect(conn)
}
```
