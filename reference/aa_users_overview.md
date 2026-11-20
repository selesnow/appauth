# Users with statuses for a table

A list of users with the flags needed for the table on the access
management tab: whether the user is blocked by an administrator, whether
login is blocked after failed attempts and how much time is left. If the
attempts tables are unavailable, the attempt-based lockout status is
treated as absent.

## Usage

``` r
aa_users_overview(conn, settings = aa_settings())
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

## Value

A table with columns `login`, `role`, `blocked`, `state` (`"blocked"`
for a block by an administrator, `"locked"` for a lockout by attempts,
otherwise `"ok"`), `lock_seconds` (seconds until the attempt lockout
ends) and `status` (status text in the settings language, an empty
string for `"ok"`), as well as `created_at` and `last_login_at` (dates
from the database in UTC, as in
[`aa_get_user()`](https://alexey-seleznev.pro/appauth/reference/aa_get_user.md))
and `created` and `last_login` (the same dates for display: server local
time, with the texts for "unknown" and "never logged in" for unknown
dates), as well as `has_email` (1 if an email is set for password
recovery; the address itself is not included), `totp_on` (1 if the user
has 2FA enabled) and `autologins` (how many active autologins, see
[`aa_active_autologins()`](https://alexey-seleznev.pro/appauth/reference/aa_active_autologins.md)).

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  aa_users_overview(conn)
  DBI::dbDisconnect(conn)
}
```
