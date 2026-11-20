# Can a user's role be changed

The role must be in the `roles` list of the settings, and the
administrator role cannot be taken from the **last active (not blocked)
administrator**, otherwise nobody in the app could manage users.

## Usage

``` r
aa_check_can_change_role(conn, login, role, settings = aa_settings())
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

`NULL` if allowed, otherwise the reason for refusal (in the settings
language).

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  aa_check_can_change_role(conn, "boss", "user")
  DBI::dbDisconnect(conn)
}
```
