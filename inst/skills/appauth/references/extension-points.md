# appauth extension points

The package contains what must be identical in every application. Everything that differs is plugged in through extension points. More detail with examples: the package vignette `extension-points` (`vignette("extension-points", package = "appauth")`).

Contents: permissions, roles, events, user card slots, profile area, texts, styling, security settings, what stays with the application.

## Permissions

`aa_permissions_from_matrix(matrix)` builds a permission source from a named list "permission -> roles" (a vector or a single string, like a `config.yaml` file). Permission names are arbitrary; the package does not know them. The administrator role does not get any permissions on its own.

```r
provider <- aa_permissions_from_matrix(list(Tasks = c("admin", "user"), Access = "admin"))
aa_can(list(login = "ivan", role = "user"), "Access", provider)   # FALSE
```

A matrix that changes without a restart (a permissions editor): pass a function, it is read on every check: `aa_permissions_from_matrix(function() conf_rv()$access_matrix)`. Call the check inside `observe`/`observeEvent` (or wrap it in `isolate()`), because a `reactiveVal` is read inside.

A custom permission source is any `function(user)` that returns a vector of the user's permission names (per-user permissions from the DB, by group, from an external system):

```r
provider <- function(user) {
  if (identical(user$role, "owner")) return(c("reports", "export", "users"))
  DBI::dbGetQuery(conn, "SELECT permission FROM user_permissions WHERE login = ?",
                  params = list(user$login))$permission
}
```

`aa_can()` is closed by default: no user given, permission is not a string, the permission source failed or returned non-strings all mean `FALSE`. Where to check:

* in the UI, `aa_can(user, "Run", provider)` decides whether to show a button or tab (convenience, not protection);
* on the server, in EVERY handler, as the first line: `aa_require(auth, "Run", provider, on_event = log_event, settings = settings)`: without the permission the handler stops silently, the user sees a notification, and the hook receives `access_denied`;
* `aa_register_module(auth, "Access", provider, function() mod_server("tab"))` attaches the server part of a tab once per session, only for those who have the permission. This protects against unnecessary work, not against forged requests.

## Roles

`aa_settings(roles = c("owner", "editor", "viewer"), admin_role = "owner")`. `admin_role` must be one of `roles`. Only this role manages users (the users module checks it on the server and verifies against the DB on every action, independently of the matrix), and the first created administrator receives it.

## Events

One hook for all modules: `on_event(event, user, session_id, value)`. Catalog and example: [events.md](events.md). The hook can be used for more than logging: for example, notify a chat about `login_locked` or `user_blocked`. An error in the hook does not interrupt the package action.

## User card slots

The card (double click on a table row) shows the standard actions: block, role, password, end sessions, delete. A custom block is added with two functions in `aa_users_server()`:

* `extra_card_ui(login, ns)` returns the block UI, wrap ids in `ns()`;
* `extra_card_server(input, output, session, login)` is called once at module start, `login` is a reactive value with the login of the open card.

```r
card_ui <- function(login, ns) div(class = "aa-card-section", h5("Permissions"),
  checkboxGroupInput(ns("permissions"), NULL, choices = c("reports", "export")),
  actionButton(ns("save_permissions"), "Save"))

card_server <- function(input, output, session, login) {
  observeEvent(input$save_permissions, {
    req(identical(isolate(auth$user())$role, "owner"), login())   # permission check in the slot handler itself
    save_permissions(login(), input$permissions)
  })
}
aa_users_server("users", conn, auth, settings, on_event = log_event,
                extra_card_ui = card_ui, extra_card_server = card_server)
```

The slot handler must check the permission itself: a slot is application code. The rest of the content of the "Access" tab (role permissions editor, log switches, database paths) is assembled by the application: `tabPanel("Access", aa_users_ui("users"), my_permissions_editor(), my_log_switches())`.

## Profile area: buttons next to the user badge

```r
pw <- aa_password_server("password", conn, auth, settings, on_event = log_event)

observeEvent(input$change_password, showModal(modalDialog(
  aa_password_ui("password"), title = "Change password", easyClose = TRUE, footer = modalButton("Close"))))
observeEvent(pw$changed(), removeModal(), ignoreInit = TRUE)

observeEvent(input$logout_all, showModal(modalDialog(            # confirmation is required
  "All your sessions on all devices will be ended.", title = "Log out on all devices?", easyClose = TRUE,
  footer = tagList(modalButton("Cancel"), actionButton("logout_all_confirm", "Log out everywhere", class = "btn-danger")))))
observeEvent(input$logout_all_confirm, { removeModal(); auth$logout_all(reload = TRUE) })
observeEvent(input$logout, auth$logout(reload = TRUE))
```

Changing one's own password checks the current password, rejects the same and weak passwords, revokes the tokens of other sessions and keeps the current one (event `password_changed`). `logout_all()` revokes all tokens and logs out immediately (event `sessions_revoked`); on other devices the session is closed by `aa_session_guard()` within `session_check_seconds`. With `autologin = FALSE` sessions have no tokens, so "log out everywhere" closes only the current session.

## Password reset by email

Off by default. You need a mail sending function, the application address for the link, and an email for the users:

```r
library(emayili)

send_reset <- function(email, link, login) {
  msg <- envelope() %>%
    from("My App <noreply@example.com>") %>%
    to(email) %>%
    subject("Password reset") %>%
    html(paste0("<p>Hello, ", htmltools::htmlEscape(login), "!</p>",
                "<p>To set a new password, follow this <a href='", link, "'>link</a>. It is valid for 60 minutes and works once.</p>"))
  smtp <- gmail(Sys.getenv("APP_EMAIL"), Sys.getenv("APP_EMAIL_PWD"))
  smtp(msg)
}

settings <- aa_settings(
  reset_enabled  = TRUE,
  send_reset     = send_reset,
  reset_base_url = "https://apps.example.com/my_app"   # how users open the app, with the nginx prefix, over HTTPS
)
```

* `aa_auth_server()` itself shows "Forgot password?", reads `?reset=<token>` from the URL (and removes it from there) and shows the new password form. Nothing else needs to be plugged in.
* The response to the user is always the same; the reason (`sent`, `no_user`, `no_email`, `blocked`, `throttled`, `send_failed`) is visible only in the `password_reset_requested` event.
* The address is set by an administrator in the card or when adding a user, programmatically via `aa_set_email()` and the `email` argument of `aa_create_user()`. Without an address no email is sent (reset by an administrator remains).
* Logic without UI: `aa_request_password_reset()`, `aa_reset_token_login()`, `aa_reset_password_with_token()` (errors of class `appauth_error_user`, an invalid link has `reason = "reset_link_invalid"`).
* The link is single-use; a weak password with `password_policy = "reject"` does not consume the link; after the change all sessions of the user are ended. An email with a link is equivalent to a key to the account: you may leave the address empty for administrators.
* Limitations: the email is sent synchronously (response time may reveal whether a user exists), and the token is visible in the nginx access log until used.

## Two-factor authentication (TOTP)

Off by default and **voluntary**: the user enables it in the profile area block, and those who have it enabled enter a code at login. You need a secret encryption key (outside the DB and the repository) and a block in the profile:

```r
settings <- aa_settings(
  totp_enabled = TRUE,
  totp_key     = Sys.getenv("APP_TOTP_KEY"),   # a string of at least 16 characters
  totp_issuer  = "Reports portal"
)

aa_totp_server("totp", conn, auth, settings, on_event = log_event)                 # server, once
tabPanel("Profile", aa_password_ui("password"), hr(), aa_totp_ui("totp"))              # UI
```

* `aa_auth_server()` itself asks for the code after a correct password. Order: password, code, mandatory password change, login. The autologin token and the successful login attempt are recorded only after the code; cookie login does not ask for a code.
* Enrollment: QR code (needs the optional `qrcode` package, otherwise only the key for manual entry), confirmation with a code, 10 recovery codes shown once; the user's other sessions are ended.
* Disabling requires the password and a code. Lost phone: a recovery code or "Reset 2FA" by an administrator in the card (event `totp_reset`, the user's sessions are ended).
* Wrong codes count as failed login attempts: the login is locked by the same rules as for password guessing. Custom UI: `aa_totp_setup()`, `aa_totp_enable()`, `aa_verify_second_factor()` (preceded by `aa_login_gate()`, after a wrong code `aa_record_attempt()`), `aa_totp_disable()`, `aa_totp_enabled()`, `aa_recovery_codes_left()`.
* If `totp_key` is lost or replaced, the secrets become unreadable: users must enroll 2FA again (reset by an administrator). Keep the key separate from the database and its copies. Server time must be synchronized (NTP).
* Tests: the code for the current step is `aa_totp_code(secret)`; an accepted code cannot be reused, for a second login take the next step `aa_totp_code(secret, Sys.time() + 30)`.

## Google login (since 0.7.0)

Off by default. Only a user who already exists in the database and has an email equal to the Google account address can log in; the role comes from the database, a blocked user cannot log in, login does not create new users, and it does not ask for the package's own 2FA. You need a domain with HTTPS and an OAuth client in Google Cloud Console (consent screen type Internal, client type Web application, redirect URI exactly as `google_redirect_uri`).

```r
settings <- aa_settings(
  google_enabled       = TRUE,
  google_client_id     = Sys.getenv("GOOGLE_OAUTH_CLIENT_ID"),
  google_client_secret = Sys.getenv("GOOGLE_OAUTH_CLIENT_SECRET"),   # keep the secret outside the repository
  google_redirect_uri  = "https://apps.example.com/",
  google_domains       = c("example.com", "example.net"),            # empty: domain is not checked
  password_login       = TRUE                                        # FALSE: Google only
)
```

* The application plugs in nothing else: `aa_auth_ui()` and `aa_auth_server()` show the button and handle the return themselves (`?code=...&state=...`, the parameters are removed from the URL immediately).
* Token validation: signature against Google keys (RS256 only), issuer, audience, expiry, `nonce`, verified email, domain. `google_domains` is checked against both `hd` (the primary domain of the Workspace organization) and the email domain: with secondary domains, list both. An empty list disables the domain check, and then the match of the email with a user decides (Gmail also works); a non-empty list does not let through personal accounts without `hd`.
* If the application is opened at several addresses (by IP and by domain), the button on a page whose address differs from `google_redirect_uri` redirects to the return address, and the login starts there on its own (`?google=1`): `state` is stored in the cookie of the address, and cookies for the IP and for the domain are different (since 0.7.1; in 0.7.0 logging in from another address ended with a `bad_browser` rejection). Password login and autologin work independently on each address.
* `state` is single-use (10 minutes) and is compared with the cookie of the browser that started the login (protection against login substitution). On rejection the user sees a generic text, while the reason and email go to the `google_login_failed` event; success is `login_success` with the value `google`.
* `password_login = FALSE` hides the password form and "Forgot password?", and password login attempts and reset links are rejected on the server. Allowed only together with `google_enabled = TRUE`; creation of the first administrator on an empty database remains.
* Do not call Google in tests: `testthat::local_mocked_bindings(aa_google_exchange_code = ..., aa_google_fetch_jwks = ..., aa_url_search = ..., .package = "appauth")`, sign tokens with a test key (`jose::jwt_encode_sig`); the `nonce` is stored in the `oauth_states` table.

## Another database (since 0.8.0)

A SQLite file is opened by default. For DuckDB, MySQL / MariaDB or PostgreSQL, pass a function that opens the connection:

```r
conn <- aa_session_connection(
  prepare = TRUE, settings = settings,
  connect = function() DBI::dbConnect(
    RPostgres::Postgres(), host = "db.example.com", dbname = "app", user = "app",
    password = Sys.getenv("APP_DB_PASSWORD")
  )
)
```

* The rest of the application code does not change. The driver (`RMariaDB`, `RPostgres`, `duckdb`) is installed separately, and the password comes only from an environment variable.
* A connection opened by the application itself is passed to the package functions as is: the database is determined by its class. An unsupported database gives an `appauth_error_connection` error.
* Write the application's own queries to its own tables without SQLite time functions (`datetime('now')`), pass the time as a parameter; PostgreSQL placeholders are `$1`, `$2`.
* Details on types and collation: [schema.md](schema.md).

## Texts

All texts are available in Russian and English: `aa_texts("ru")`, `aa_texts("en")`. Any string can be replaced: `aa_texts("en", login_button = "Sign in to the system")`. Keys: `aa_text_keys()`. An unknown key or an empty value gives an error immediately. Substituted values: `aa_text(texts, "locked", 15)`.

## Styling

`aa_app_head()` attaches the styles and script. Colors are changed with CSS variables, and they must be overridden AFTER `aa_app_head()`: `--aa-primary`, `--aa-primary-hover`, `--aa-danger`, `--aa-warning`, `--aa-bg`, `--aa-card-bg`, `--aa-card-border`, `--aa-text`, `--aa-muted`, `--aa-input-bg`, `--aa-input-border`. Light theme: class `aa-theme-light` on `<body>`. Title and logo of the login form: `aa_auth_server(title = , logo = )` (an image from `www`). Autologin cookie name: `aa_auth_server(cookie_name = )`; applications on the same host need different names (cookies are not isolated by port).

## Security settings (`aa_settings()`)

| Parameter | Default | Meaning |
| --- | --- | --- |
| `max_failed_logins` | 5 | failures before a login is locked |
| `lockout_minutes` | 15 | counting window and lock duration |
| `max_failed_logins_per_minute` | 30 | global limit of failures across all logins |
| `password_min`, `password_max` | 6, 128 | length of a new password |
| `login_max` | 64 | login length |
| `autologin` | `TRUE` | cookie autologin |
| `session_days` | 30 | token lifetime |
| `session_check_seconds` | 30 | how often to check an open session |
| `attempts_retention_hours`, `token_retention_days` | 24, 30 | how long to keep attempts and expired tokens |
| `roles`, `admin_role` | `admin`, `user`, `viewer` / `admin` | roles |
| `must_change_default` | `TRUE` | a password set by an administrator is temporary by default (change at login) |
| `reset_enabled` | `FALSE` | password reset by email (needs `send_reset` and `reset_base_url`) |
| `reset_ttl_minutes` | 60 | lifetime of the link from the email |
| `reset_max_per_hour`, `reset_max_per_minute` | 3, 10 | email limit per user per hour and global per minute |
| `totp_enabled` | `FALSE` | two-factor authentication (TOTP), voluntary; needs `totp_key` |
| `totp_key` | `NULL` | TOTP secret encryption key (a string of at least 16 characters), keep outside the DB |
| `totp_issuer`, `totp_window` | `"appauth"`, 1 | name shown in the authenticator app, allowed clock drift in 30-second steps |
| `google_enabled` | `FALSE` | Google login (needs `google_client_id`, `google_client_secret`, `google_redirect_uri`) |
| `google_client_id`, `google_client_secret` | `NULL` | OAuth client (keep the secret outside the DB and the repository) |
| `google_redirect_uri` | `NULL` | return address, `https://...` (`http://localhost` for development), exactly as in the OAuth client |
| `google_domains` | `NULL` | allowed organization domains (`hd` and email domain); empty: domain is not checked |
| `password_login` | `TRUE` | password login; `FALSE` only together with `google_enabled = TRUE` |

It is convenient to keep settings in `config.yaml` and read them with `aa_settings_from_list(conf$security, texts = aa_texts("en"))`: extra keys are ignored. An invalid value (zero, text instead of a number) raises an error: if a typo in the config must not crash the application, wrap the call in `tryCatch` with fallback default settings.

## What stays with the application

The permission matrix and its editor; log switches and the log itself; the set of tabs and domain-specific checks (task names, paths, commands); additional user fields (they live in the application's tables and are shown in the card through a slot). If a feature turns out to be needed in three applications, that is a reason to move it into the package.
