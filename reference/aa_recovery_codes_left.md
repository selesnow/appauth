# How many recovery codes are left

How many recovery codes are left

## Usage

``` r
aa_recovery_codes_left(conn, login)
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- login:

  Login.

## Value

An integer: the number of unused recovery codes.

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_recovery_codes_left(conn, "boss")
  DBI::dbDisconnect(conn)
}
```
