# Request password recovery

Finds a user by login or email, creates a one-time token and calls
`settings$send_reset(email, link, login)` to send an email with the
link. Only the token hash stays in the database. The user's previous
unused links stop working.

## Usage

``` r
aa_request_password_reset(conn, identifier, settings = aa_settings())
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- identifier:

  The login or email the user entered.

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md)
  with `reset_enabled = TRUE`.

## Value

A list (invisibly): `sent` (`TRUE` if the email was sent), `reason`
(`"sent"`, `"disabled"`, `"no_user"`, `"no_email"`, `"blocked"`,
`"throttled"` or `"send_failed"`) and `login` (the found login or `NA`).

## Details

No email is sent if the user does not exist, has no email, is blocked by
an administrator, or a limit is exceeded (`reset_max_per_hour` per user,
`reset_max_per_minute` overall). The function result is meant for the
journal: the user should be shown the same answer in every case, so that
it is impossible to find out which logins and addresses exist.

An error in `send_reset` does not abort the function but is returned as
`send_failed`: the token is consumed in that case.

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  aa_set_email(conn, "boss", "boss@example.com")

  settings <- aa_settings(
    reset_enabled  = TRUE,
    reset_base_url = "https://apps.example.com/my_app",
    send_reset = function(email, link, login) message("Link for ", login, ":
    ", link)
  )
  aa_request_password_reset(conn, "boss", settings)$reason
  aa_request_password_reset(conn, "nobody", settings)$reason
  DBI::dbDisconnect(conn)
}
#> Link for boss:
#>     https://apps.example.com/my_app/?reset=b8f4811446e5439a295f8de89bbd9b1562e219a1cf0cceeae8e3d0963a6494ec
```
