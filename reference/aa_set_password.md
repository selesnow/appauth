# Set a new password for a user

Stores the hash of the new password and **revokes all autologin tokens**
of the user, so that after a password reset old browser sessions stop
working (open sessions are ended by
[`aa_session_guard()`](https://alexey-seleznev.pro/appauth/reference/aa_session_guard.md)).
Unused password recovery links sent by email also stop working. The
password is checked against the rules from the settings; on a violation,
an error of class `appauth_error_user`.

## Usage

``` r
aa_set_password(
  conn,
  login,
  password,
  settings = aa_settings(),
  must_change = FALSE,
  keep_token = NULL
)
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- login:

  Login.

- password:

  The password in plain text (only the hash goes to the database).

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

- must_change:

  Require the user to change this password at the next login (sensible
  if the password was set by an administrator).

- keep_token:

  An autologin token that must not be revoked (the current session of
  the person changing their own password), or `NULL`.

## Value

The number of changed users (invisibly): 1, or 0 if there is no such
login.

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  aa_set_password(conn, "boss", "new-boss-password")
  aa_authenticate(conn, "boss", "new-boss-password")
  DBI::dbDisconnect(conn)
}
```
