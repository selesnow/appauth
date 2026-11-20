# Getting started

This document is for anyone writing a new Shiny app who wants to add
authentication in half an hour. How the package works and what it
protects against is described in the `architecture-and-security`
vignette; how to migrate an app that is already running is covered in
`integrating-existing-app`.

## What you need

- The package installed:
  [`library(appauth)`](https://alexey-seleznev.pro/appauth/).
- A database for the app: a SQLite file (the default) or DuckDB, MySQL /
  MariaDB or PostgreSQL (see the `deployment` vignette, section “Other
  databases”). The package creates its own tables in it (`users`,
  `auth_sessions`, `login_attempts`, `appauth_migrations` and others)
  and does not touch the app’s other tables.
- A decision on how the app determines permissions: a “permission -\>
  roles” matrix or something of your own. More on this below and in the
  `extension-points` vignette.

## Basic concepts

- **User**: login, role, blocked flag. The password is stored only as a
  scrypt hash.
- **Role**: one of `settings$roles` (by default `admin`, `user`,
  `viewer`). The `settings$admin_role` role manages users; you define
  the other permissions.
- **Permission**: the name of an action or section, for example `"Run"`
  or `"Access"`. A role has a set of permissions, determined by the
  *permission provider* (`provider`).
- **Session**: the signed-in user (`auth$user()`) and, if auto-login is
  on, their token in a cookie.
- **Event**: the package writes nothing to logs itself; it reports
  events (`login_failed`, `user_blocked`…) to the `on_event` function
  that you define.

## Five steps

### 1. Settings

``` r

library(shiny)
library(appauth)

settings <- aa_settings()   # the defaults suit most apps
```

Settings can be read from `config.yaml`:
`aa_settings_from_list(conf$security)`. All parameters are listed in
[`?aa_settings`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

### 2. Permissions

``` r

provider <- aa_permissions_from_matrix(list(
  Tasks  = c("admin", "user", "viewer"),
  Run    = c("admin", "user"),
  Access = "admin"
))
```

The administrator role does not get permissions by itself: only those
listed in the matrix.

### 3. User interface

``` r

ui <- fluidPage(
  aa_app_head(),          # styles and the cookie script, once per page
  aa_auth_ui("auth"),     # login form
  uiOutput("main")        # the rest of the app
)
```

### 4. Server

``` r

log_event <- function(event, user, session_id, value) {
  message(sprintf("[appauth] %s user=%s value=%s", event, user, value))
}

server <- function(input, output, session) {
  # the connection closes together with the session; the schema is prepared on connect
  conn <- aa_session_connection("app.db", prepare = TRUE, settings = settings)

  # login, first administrator creation, auto-login, logout
  auth <- aa_auth_server("auth", conn, settings, on_event = log_event)

  # blocking, deletion, role change and password reset take effect within 30 seconds
  aa_session_guard(auth, conn, settings)

  # the server part of a tab is attached only for those who have the permission
  aa_register_module(auth, "Access", provider, function() {
    aa_users_server("users", conn, auth, settings, on_event = log_event)
  })

  output$main <- renderUI({
    req(auth$logged_in())
    user <- auth$user()

    tabsetPanel(
      tabPanel("Tasks",
        p("Signed in as ", strong(user$login)),
        if (aa_can(user, "Run", provider)) actionButton("run", "Run")
      ),
      if (aa_can(user, "Access", provider)) tabPanel("Access", aa_users_ui("users")),
      tabPanel("Sign out", actionButton("logout", "Sign out"))
    )
  })

  observeEvent(input$run, {
    # the permission is checked on the server: a hidden button is not protection
    aa_require(auth, "Run", provider, on_event = log_event, settings = settings)
    showNotification("Done")
  })

  observeEvent(input$logout, auth$logout(reload = TRUE))
}
```

### 5. Run

``` r

shinyApp(ui, server)
```

On an empty database the app offers to create the first administrator.
After that the administrator adds users on the “Access” tab.
Ready-to-run versions are in
`system.file("examples", package = "appauth")`.

## How it works without Shiny

All features are also available as plain functions. This is handy for
scripts, tests and administrative tasks:

``` r

library(appauth)

conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
aa_init_db(conn)                                   # creates the tables

aa_create_first_admin(conn, "boss", "boss-password")
#> [1] TRUE
aa_create_user(conn, "ivan", "ivan-password", "user")

aa_list_users(conn)                                # password hashes are not returned
#>   login  role blocked          created_at last_login_at
#> 1  boss admin       0 2026-11-20 07:15:32          <NA>
#> 2  ivan  user       0 2026-11-20 07:15:32          <NA>

aa_authenticate(conn, "ivan", "ivan-password")     # user data
#>   login role blocked must_change
#> 1  ivan user       0           0
is.null(aa_authenticate(conn, "ivan", "wrong"))    # wrong password: NULL
#> [1] TRUE
```

Auto-login token and permission check:

``` r

token <- aa_issue_token(conn, "ivan")              # token for the cookie
aa_find_session_user(conn, token)                  # the user is found by the token
#> $login
#> [1] "ivan"
#> 
#> $role
#> [1] "user"

provider <- aa_permissions_from_matrix(list(Tasks = c("admin", "user"), Access = "admin"))
aa_can(list(login = "ivan", role = "user"), "Tasks", provider)
#> [1] TRUE
aa_can(list(login = "ivan", role = "user"), "Access", provider)
#> [1] FALSE
```

Blocking a user revokes their tokens:

``` r

aa_set_blocked(conn, "ivan", TRUE, acting_login = "boss")
is.null(aa_find_session_user(conn, token))
#> [1] TRUE
```

User rules are enforced automatically and report a clear reason:

``` r

tryCatch(
  aa_delete_user(conn, "boss", acting_login = "boss"),
  appauth_error_user = function(e) conditionMessage(e)
)
#> [1] "You cannot delete yourself"

DBI::dbDisconnect(conn)
```

## What to customize

| Need | How |
|----|----|
| Other roles | `aa_settings(roles = c("owner", "editor"), admin_role = "owner")` |
| Stricter brute-force protection | `aa_settings(max_failed_logins = 3, lockout_minutes = 30)` |
| Password length | `aa_settings(password_min = 10)` |
| Weak passwords: reject or do not check | `aa_settings(password_policy = "reject")` or `"off"` (default `"warn"`: accept and warn) |
| No auto-login | `aa_settings(autologin = FALSE)` |
| Russian interface | `aa_settings(texts = aa_texts("ru"))` |
| Custom button text | `aa_texts("en", login_button = "Log in to the system")` |
| Permanent administrator password | `aa_settings(must_change_default = FALSE)` |
| Two-factor authentication (TOTP) | `aa_settings(totp_enabled = TRUE, totp_key = ...)` and [`aa_totp_server()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_server.md) in the user’s account page, recipe in the `extension-points` vignette |
| Password reset by email | `aa_settings(reset_enabled = TRUE, send_reset = ..., reset_base_url = ...)`, recipe in the `extension-points` vignette |
| Your own permissions (not a matrix) | a `function(user)` instead of [`aa_permissions_from_matrix()`](https://alexey-seleznev.pro/appauth/reference/aa_permissions_from_matrix.md) |
| Your own block in the user card | `extra_card_ui` and `extra_card_server` in [`aa_users_server()`](https://alexey-seleznev.pro/appauth/reference/aa_users_server.md) |
| Where to write events | the `on_event` function in all modules; ready-made handler: [`aa_event_logger()`](https://alexey-seleznev.pro/appauth/reference/aa_event_logger.md) |
| Changing your own password and “sign out on all devices” | [`aa_password_server()`](https://alexey-seleznev.pro/appauth/reference/aa_password_server.md) and `auth$logout_all()`, recipe in the `extension-points` vignette |

Details and examples are in the `extension-points` vignette.

## FAQ

**Why
[`aa_register_module()`](https://alexey-seleznev.pro/appauth/reference/aa_register_module.md)
if there is
[`aa_require()`](https://alexey-seleznev.pro/appauth/reference/aa_require.md)?**
They are different things. Registration saves unnecessary work for those
without the permission, while
[`aa_require()`](https://alexey-seleznev.pro/appauth/reference/aa_require.md)
protects against forged requests: the permission is checked again in
every action handler.

**What does
[`aa_session_guard()`](https://alexey-seleznev.pro/appauth/reference/aa_session_guard.md)
do?** At a regular interval it checks the open session. If the user was
blocked, deleted, had their role changed or their password reset, the
session ends. Without it such changes take effect only at the next
login.

**Can I pass
[`aa_auth_server()`](https://alexey-seleznev.pro/appauth/reference/aa_auth_server.md)
a connection that I open myself?** Yes, but then you must close it
yourself in `session$onSessionEnded()`. Otherwise the database file
stays busy until the process stops, and on Windows such a file cannot be
renamed.
[`aa_session_connection()`](https://alexey-seleznev.pro/appauth/reference/aa_session_connection.md)
does this for you.

**What happened to plaintext passwords?** The package does not accept
them: a plaintext password in the database will not let anyone sign in.
How to safely migrate such passwords to hashes is described in the
`integrating-existing-app` vignette.
