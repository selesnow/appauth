# Validate a new user's data

Checks the login, password, role and login uniqueness without creating
anything. Suitable for showing an error in a form before the user is
created.

## Usage

``` r
aa_validate_new_user(conn, login, password, role, settings = aa_settings())
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- login:

  Login.

- password:

  The password in plain text (only the hash goes to the database).

- role:

  A role from the `roles` list of the settings.

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

## Value

`NULL` if the data is fine, otherwise the problem text (in the settings
language).

## Details

A login is considered taken if it matches an existing one exactly or
case-insensitively (so new users do not create pairs like `Kiruka` and
`kiruka`).

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  aa_validate_new_user(conn, "Boss", "another-password", "user")
  aa_validate_new_user(conn, "worker", "another-password", "user")
  DBI::dbDisconnect(conn)
}
```
