# Request self-registration

Checks the login, password, email and the domain and rate limits from
the settings, and stores a pending registration with the password hash.
With `registration_verify_email = TRUE` a one-time confirmation link is
sent with `settings$send_reset(email, link, login)`; with `FALSE` the
account is created immediately. Only the token hash is stored in the
database.

## Usage

``` r
aa_register_user(conn, login, password, email, settings = aa_settings())
```

## Arguments

- conn:

  Connection with the
  [`aa_init_db()`](https://alexey-seleznev.pro/appauth/reference/aa_init_db.md)
  schema.

- login:

  Desired login.

- password:

  Desired password (only the hash is stored).

- email:

  Email address of the visitor.

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md)
  with `registration_enabled = TRUE`.

## Value

A list (invisibly): `sent`, `reason` and `login`. Reasons: `created`,
`sent`, `disabled`, `user_exists`, `email_exists`, `email_invalid`,
`registration_domain`, `registration_throttled`, `send_failed` or a
login or password validation reason.

## Details

The result is meant for the journal and for choosing a generic on-screen
answer: the reason `user_exists` or `email_exists` must not be shown to
a visitor, because that would reveal which accounts exist.

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")

  settings <- aa_settings(
    registration_enabled = TRUE,
    registration_verify_email = FALSE,
    registration_role = "viewer"
  )
  aa_register_user(conn, "worker", "worker-password", "worker@example.com",
                   settings)$reason
  aa_list_users(conn)
  DBI::dbDisconnect(conn)
}
```
