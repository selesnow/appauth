# Can a login be attempted right now

A single check before verifying the password: first the global failure
limit across all logins, then the lockout of this login. If login is
closed, there is no need to verify the password, and no need to record
the attempt (otherwise the lockout would be extended).

## Usage

``` r
aa_login_gate(conn, login, settings = aa_settings())
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

A list: `allowed` (`TRUE` or `FALSE`), `reason` (`NA`, `"throttled"` for
the global limit or `"locked"` for a login lockout), `seconds` (how many
seconds are left until the login lockout ends, otherwise 0) and
`message` (text to show to the user in the settings language, `NA` if
login is allowed).

## Details

The function **does not stop login on an error**: if the protection
tables do not exist or cannot be queried, login is considered allowed
(the password is still verified) and the reason is written to the app
log. This way an unavailable attempts table does not lock out all users.

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_login_gate(conn, "alsey")$allowed
  for (i in 1:5) aa_record_attempt(conn, "alsey", FALSE)
  aa_login_gate(conn, "alsey")
  DBI::dbDisconnect(conn)
}
```
