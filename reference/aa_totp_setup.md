# Start setting up two-factor authentication

Creates a new secret and stores it in the database in encrypted form,
but **does not enable** 2FA: it is enabled only after
[`aa_totp_enable()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_enable.md)
with a correct code from the app. A repeated call replaces the pending
secret. If 2FA is already enabled, an error of class
`appauth_error_user` is raised.

## Usage

``` r
aa_totp_setup(conn, login, settings = aa_settings())
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- login:

  Login.

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md)
  with `totp_enabled = TRUE`.

## Value

A list: `secret` (base32, for manual entry) and `uri` (an `otpauth://`
link, the QR code is built from it).

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  settings <- aa_settings(totp_enabled = TRUE, totp_key =
  "a-long-random-key-for-the-example")
  setup <- aa_totp_setup(conn, "boss", settings)
  setup$uri
  DBI::dbDisconnect(conn)
}
```
