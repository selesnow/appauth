# Users module: server

User management for an administrator: adding, role change, password
reset, blocking and unblocking, clearing the login lock, deletion. The
rules (one cannot block or delete oneself, one cannot be left without an
active administrator) are checked on the server by the package
functions; the UI merely does not show forbidden buttons.

## Usage

``` r
aa_users_server(
  id,
  conn,
  auth,
  settings = aa_settings(),
  on_event = NULL,
  extra_card_ui = NULL,
  extra_card_server = NULL
)
```

## Arguments

- id:

  Module id, the same as in
  [`aa_users_ui()`](https://alexey-seleznev.pro/appauth/reference/aa_users_ui.md).

- conn:

  Database connection.

- auth:

  Authentication object, the result of
  [`aa_auth_server()`](https://alexey-seleznev.pro/appauth/reference/aa_auth_server.md).

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

- on_event:

  Event hook `function(event, user, session_id, value)` or `NULL`.

- extra_card_ui, extra_card_server:

  Card extension slots, see the section "Extension slots".

## Value

A list with a `refresh()` function that redraws the table (for example
after changes made not through the module).

## Details

The module does not depend on the app's permission matrix: only a user
with the role `settings$admin_role` can manage users, and the role is
additionally checked against the database on every action. The target of
an action is taken from the server state of the open card, not from a
value sent by the browser.

## Extension slots

The app can add its own block to the user card.

- `extra_card_ui(login, ns)` returns the block UI. Element ids must be
  wrapped in `ns()`.

- `extra_card_server(input, output, session, login)` is called once on
  module start inside its namespace; `login` is a reactive value with
  the login of the open card. Register the block handlers here.

## See also

[`aa_users_ui()`](https://alexey-seleznev.pro/appauth/reference/aa_users_ui.md),
[`aa_auth_server()`](https://alexey-seleznev.pro/appauth/reference/aa_auth_server.md)

## Examples

``` r
if (FALSE) { # \dontrun{
auth <- aa_auth_server("auth", conn)
shiny::observe({
  if (auth$logged_in()) aa_users_server("users", conn, auth, on_event =
  log_event)
})
} # }
```
