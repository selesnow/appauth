# Change a user's role

The role must be in the `roles` list of the settings; the administrator
role cannot be taken from the last active administrator (see
[`aa_check_can_change_role()`](https://alexey-seleznev.pro/appauth/reference/aa_check_can_change_role.md)).
On a violation, an error of class `appauth_error_user`.

## Usage

``` r
aa_set_role(conn, login, role, settings = aa_settings())
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- login:

  Login.

- role:

  A role from the `roles` list of the settings.

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

## Value

The number of changed users (invisibly).

## Details

The user's open session keeps working with the old role until the login
module's next live-session check, and at the next login the role is
taken from the database.

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  aa_create_user(conn, "worker", "worker-password", "user")
  aa_set_role(conn, "worker", "viewer")
  aa_get_user(conn, "worker")
  DBI::dbDisconnect(conn)
}
```
