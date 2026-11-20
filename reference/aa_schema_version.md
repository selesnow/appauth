# Current version of the authentication table schema

Current version of the authentication table schema

## Usage

``` r
aa_schema_version(conn)
```

## Arguments

- conn:

  Database connection: SQLite, DuckDB, MySQL / MariaDB or PostgreSQL
  ([`DBI::dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html)
  with the RSQLite, duckdb, RMariaDB or RPostgres driver).

## Value

An integer: the number of the last applied migration or `0` if the
schema has not been created by the package yet.

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_schema_version(conn)
  aa_init_db(conn)
  aa_schema_version(conn)
  DBI::dbDisconnect(conn)
}
```
