# Create a user

Creates a user with a password hash. Before creation the login,
password, role (must be in `roles` from the settings) and login
uniqueness are checked. On a rule violation the function aborts with an
error of class `appauth_error_user` with text in the settings language
(the `reason` field holds the reason key) that can be shown to the user.

## Usage

``` r
aa_create_user(
  conn,
  login,
  password,
  role,
  settings = aa_settings(),
  must_change = FALSE,
  email = NULL
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

- role:

  A role from the `roles` list of the settings.

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

- must_change:

  Require a password change at the first login (sensible if the password
  was set by an administrator).

- email:

  Address for password recovery or `NULL` (the address can be set later
  with
  [`aa_set_email()`](https://alexey-seleznev.pro/appauth/reference/aa_set_email.md)).
  The format and uniqueness are checked.

## Value

`TRUE` (invisibly).

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_user(conn, "worker", "worker-password", "user")
  aa_list_users(conn)

  # the error can be shown to the user
  tryCatch(
    aa_create_user(conn, "worker", "another-password", "user"),
    appauth_error_user = function(e) conditionMessage(e)
  )
  DBI::dbDisconnect(conn)
}
```
