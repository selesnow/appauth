# End all sessions of a user

Revokes all autologin tokens of the user. Open sessions with such tokens
are ended by
[`aa_session_guard()`](https://alexey-seleznev.pro/appauth/reference/aa_session_guard.md)
at its next check, and the cookies in browsers stop working.

## Usage

``` r
aa_revoke_sessions(conn, login)
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- login:

  Login.

## Value

The number of revoked tokens (invisibly).

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  token <- aa_issue_token(conn, "boss")
  aa_revoke_sessions(conn, "boss")
  is.null(aa_find_session_user(conn, token))
  DBI::dbDisconnect(conn)
}
```
