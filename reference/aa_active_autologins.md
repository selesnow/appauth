# How many active autologins users have

Counts autologin tokens that are not revoked and have not expired: that
many devices currently "remember" the user's login (cookie), i.e. can
log in without a password. This is not the number of open tabs: the app
does not track them. If the token table does not exist or cannot be
queried, it is assumed there are no tokens.

## Usage

``` r
aa_active_autologins(conn, login = NULL)
```

## Arguments

- conn:

  Database connection.

- login:

  User login or `NULL`.

## Value

For a given `login`, an integer (0 if there are no tokens). With
`login = NULL`, a table with `login` and `n` columns for users that have
active tokens.

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  aa_issue_token(conn, "boss")
  aa_active_autologins(conn, "boss")
  DBI::dbDisconnect(conn)
}
```
