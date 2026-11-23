# Delete stale authentication data

Deletes login attempt records older than `attempts_retention_hours`
hours, as well as expired and revoked auto-login tokens older than
`token_retention_days` days, as well as used and expired password
recovery tokens, pending registrations and Google sign-in parameters
older than a day. Active tokens and fresh attempts are not touched. Call
it after
[`aa_init_db()`](https://alexey-seleznev.pro/appauth/reference/aa_init_db.md).

## Usage

``` r
aa_cleanup(conn, settings = aa_settings())
```

## Arguments

- conn:

  Database connection: SQLite, DuckDB, MySQL / MariaDB or PostgreSQL
  ([`DBI::dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html)
  with the RSQLite, duckdb, RMariaDB or RPostgres driver).

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

## Value

A list (invisibly): `login_attempts` (the number of deleted login
attempts), `auth_sessions` (the number of deleted tokens),
`password_resets` (the number of deleted password recovery tokens),
`registrations` (the number of deleted pending registrations) and
`oauth_states` (the number of deleted sign-in parameters for Google).

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_cleanup(conn)
  DBI::dbDisconnect(conn)
}
```
