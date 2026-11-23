# Seconds left until a login lockout ends

Counts the failed attempts of a login after its last successful login
and within the `lockout_minutes` window. If there are at least
`max_failed_logins` of them, the login is blocked until the end of the
window, counted from the last failure.

## Usage

``` r
aa_login_lock_remaining(conn, login, settings = aa_settings())
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

An integer number of seconds, 0 if login is allowed.

## Details

The login is matched **exactly**: `Alsey` and `alsey` are different
logins with separate counters, as at login.

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  for (i in 1:5) aa_record_attempt(conn, "alsey", FALSE)
  aa_login_lock_remaining(conn, "alsey")
  aa_login_lock_remaining(conn, "Alsey")
  DBI::dbDisconnect(conn)
}
```
