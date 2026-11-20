# Enable two-factor authentication

Checks the app code against the pending secret
([`aa_totp_setup()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_setup.md))
and enables 2FA. Creates 10 recovery codes: **they are returned once**,
only hashes stay in the database. A wrong code raises an error of class
`appauth_error_user` (`reason = "totp_wrong"`).

## Usage

``` r
aa_totp_enable(conn, login, code, settings = aa_settings())
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- login:

  Login.

- code:

  Code from the authenticator app.

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md)
  with `totp_enabled = TRUE`.

## Value

A vector of recovery codes (invisibly).

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  settings <- aa_settings(totp_enabled = TRUE, totp_key =
  "a-long-random-key-for-the-example")
  setup <- aa_totp_setup(conn, "boss", settings)
  codes <- aa_totp_enable(conn, "boss", aa_totp_code(setup$secret), settings)
  length(codes)
  DBI::dbDisconnect(conn)
}
```
