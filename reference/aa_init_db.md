# Create or update the authentication table schema

Applies versioned migrations: creates missing tables and columns and
records the applied versions in the service table `appauth_migrations`.
Existing data is not changed, a repeated run changes nothing. Old
schemas are recognized too (for example, a `users` table without an `id`
column or without `blocked`, a database without session and login
attempt tables): what is missing is completed, users, passwords and
tokens stay as they were.

## Usage

``` r
aa_init_db(conn)
```

## Arguments

- conn:

  Database connection: SQLite, DuckDB, MySQL / MariaDB or PostgreSQL
  ([`DBI::dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html)
  with the RSQLite, duckdb, RMariaDB or RPostgres driver).

## Value

A list (invisibly): `applied` (migration versions applied in this call),
`version` (the current schema version) and `legacy` (`TRUE` if the
`users` table already existed before the package was connected).

## Details

Migrations run in a single transaction: on error the changes are rolled
back. It is safe to call the function on every app start, including on
live databases. For a start that must not stop the app on error, use
[`aa_prepare_db()`](https://alexey-seleznev.pro/appauth/reference/aa_prepare_db.md).

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_schema_version(conn)
  DBI::dbDisconnect(conn)
}
```
