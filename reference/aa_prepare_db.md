# Prepare the database on app start

Calls
[`aa_init_db()`](https://alexey-seleznev.pro/appauth/reference/aa_init_db.md)
and
[`aa_cleanup()`](https://alexey-seleznev.pro/appauth/reference/aa_cleanup.md)
and **never stops the app**: on error it writes a message to the app log
and returns `FALSE`. Meant to be called once at app start. Without the
prepared tables, protection against guessing and locks will not work,
while password sign-in will keep working.

## Usage

``` r
aa_prepare_db(conn, settings = aa_settings())
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

`TRUE` if the schema is prepared, otherwise `FALSE` (invisibly).

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_prepare_db(conn, aa_settings())
  DBI::dbDisconnect(conn)
}
#> appauth: schema migrations applied: 1, 2, 3, 4, 5, 6, 7, 8, 9
```
