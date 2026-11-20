# User who owns a recovery link

Checks the token from the link without changing anything: it must exist,
be unused and not expired, and the user must not be blocked or deleted.
Needed to show the new password form only for a working link.

## Usage

``` r
aa_reset_token_login(conn, token)
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- token:

  Token from the link (the `reset` parameter of the address bar).

## Value

The user login or `NULL`.

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_reset_token_login(conn, "not-a-token")
  DBI::dbDisconnect(conn)
}
```
