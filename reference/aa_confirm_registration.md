# Create an account from a registration link

Checks the token again, consumes it atomically and creates the user with
the hashed password stored in the pending registration. A weak password
has already been rejected when the registration was requested; a
conflict with an account created meanwhile leaves the token unused and
raises an error of class `appauth_error_user`.

## Usage

``` r
aa_confirm_registration(conn, token, settings = aa_settings())
```

## Arguments

- conn:

  Connection with the
  [`aa_init_db()`](https://alexey-seleznev.pro/appauth/reference/aa_init_db.md)
  schema.

- token:

  Token from the address.

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

## Value

The login of the created user (invisibly).

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  settings <- aa_settings(
    registration_enabled = TRUE,
    registration_verify_email = FALSE
  )
  tryCatch(
    aa_confirm_registration(conn, "not-a-token", settings),
    appauth_error_user = function(e) conditionMessage(e)
  )
  DBI::dbDisconnect(conn)
}
```
