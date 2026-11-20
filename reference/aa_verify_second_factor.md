# Verify the second factor at sign-in

Accepts a code from the app (6 digits) or a recovery code. An app code
is accepted once: a repeat of the same code (time step) is rejected. A
recovery code is one-time. The function **does not limit the number of
attempts itself**: call
[`aa_login_gate()`](https://alexey-seleznev.pro/appauth/reference/aa_login_gate.md)
before it and
[`aa_record_attempt()`](https://alexey-seleznev.pro/appauth/reference/aa_record_attempt.md)
after a wrong code, as the sign-in module does.

## Usage

``` r
aa_verify_second_factor(conn, login, code, settings = aa_settings())
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- login:

  Login.

- code:

  Entered code.

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md)
  with `totp_enabled = TRUE`.

## Value

A list: `ok` (`TRUE` or `FALSE`) and `method` (`"totp"`, `"recovery"` or
`NA`).

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  settings <- aa_settings(totp_enabled = TRUE, totp_key =
  "a-long-random-key-for-the-example")
  aa_verify_second_factor(conn, "boss", "123456", settings)$ok
  DBI::dbDisconnect(conn)
}
```
