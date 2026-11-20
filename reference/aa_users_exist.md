# Does the database have at least one user

If there are no users, the app needs to show the form for creating the
first administrator; the package login module does this.

## Usage

``` r
aa_users_exist(conn)
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

## Value

`TRUE` or `FALSE`.

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_users_exist(conn)
  DBI::dbDisconnect(conn)
}
```
