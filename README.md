
<img src="man/figures/logo.png" align="right" height="138" alt="appauth logo" />

# appauth

<!-- badges: start -->
<!-- badges: end -->

The `appauth` package gives Shiny applications secure authentication and user management: login, passwords, brute-force protection, blocking, sessions, permissions and ready-made UI modules. It replaces hand-written login, password and session code.

The package works with SQLite (the default), DuckDB, MySQL / MariaDB and PostgreSQL; the application supplies the database connection. See the "Databases" section below.

Interface texts default to English. Russian is available with `aa_texts("ru")`, and any string can be replaced.

## Why use it

Authentication is easy to write in a hurry, and it almost always ends up with the same holes: plaintext passwords, SQL injection in the login check, no brute-force protection, auto-login tokens stored as is, permissions enforced only by hiding buttons. `appauth` solves these once, in the same way everywhere and with automated tests (more than 1400 checks), and leaves everything that differs between applications (the permission matrix, the set of tabs, logging switches) to the application.

A detailed comparison with existing packages such as `shinyauthr` and `shinymanager` has not been done. The reason for a separate package is practical: `appauth` connects to the databases of already running applications without moving data, can safely convert plaintext passwords to hashes, and all of its guarantees (see the `architecture-and-security` vignette) are backed by automated tests and browser checks.

## Features

* Passwords stored only as hashes (scrypt); plaintext passwords are not accepted; a one-off safe migration of plaintext passwords to hashes.
* Login and password sign-in, creation of the first administrator, cookie auto-login (the token is stored in the database only as sha256), logout.
* Brute-force protection: a login is locked after a series of failures, plus a global failure limit per minute.
* Manual blocking and deletion of users, role changes, password reset, ending all sessions. You cannot block or delete yourself or the last active administrator, or remove that administrator's role.
* Forced logout: a blocked, deleted, role-changed or password-reset user loses the open session within the check interval (30 seconds by default).
* Changing your own password, a mandatory change of a temporary password set by an administrator, and logout on all devices (`auth$logout_all()`).
* Password recovery by email: a one-time link from the email, email rate limits, the form response does not reveal whether a user exists (off by default; the email is sent by an application function).
* Two-factor authentication (TOTP): optional, a code from an authenticator app and 10 recovery codes, the secret is encrypted in the database, wrong codes lock the login, reset by an administrator (off by default).
* Sign-in with Google (OpenID Connect): only for existing users by email, with an organisation domain check, no auto-creation; password login can be disabled (off by default).
* Server-side permission checks (`aa_can()`, `aa_require()`), with permissions from a "permission -> roles" matrix or from any custom source.
* Ready-made modules: login, users (with slots for custom blocks), password change; styles with variables and a light theme.
* A single place for logging: the `on_event` hook and the `aa_events()` event catalogue.
* Versioned schema migrations.
* Interface texts in English (default) and Russian, any string can be replaced.

## Quick start

See the `getting-started` vignette for details and the ready-to-run examples in `inst/examples`.

```r
library(shiny)
library(appauth)

settings <- aa_settings()                                            # 1. settings

ui <- fluidPage(aa_app_head(), aa_auth_ui("auth"), uiOutput("main")) # 2. UI

server <- function(input, output, session) {
  conn <- aa_session_connection("app.db", prepare = TRUE)            # 3. database
  auth <- aa_auth_server("auth", conn, settings)                     # 4. login
  aa_session_guard(auth, conn, settings)                             # 5. forced logout

  output$main <- renderUI({
    req(auth$logged_in())
    p("Signed in as ", auth$user()$login)
  })
}

shinyApp(ui, server)
```

The first run on an empty database offers to create an administrator.

## Functions

| Topic | Functions |
| --- | --- |
| Settings and texts | `aa_settings()`, `aa_settings_from_list()`, `aa_texts()`, `aa_text()`, `aa_text_keys()` |
| Database | `aa_init_db()`, `aa_prepare_db()`, `aa_schema_version()`, `aa_cleanup()`, `aa_session_connection()` |
| Passwords | `aa_hash_password()`, `aa_verify_password()`, `aa_is_password_hash()`, `aa_validate_password()`, `aa_validate_login()`, `aa_migrate_plaintext_passwords()`, `aa_check_default_accounts()`, `aa_common_passwords()` |
| Users | `aa_get_user()`, `aa_list_users()`, `aa_users_exist()`, `aa_users_overview()`, `aa_active_autologins()`, `aa_create_user()`, `aa_create_first_admin()`, `aa_validate_new_user()`, `aa_authenticate()`, `aa_set_password()`, `aa_change_own_password()`, `aa_set_role()`, `aa_set_blocked()`, `aa_delete_user()`, `aa_check_can_block()`, `aa_check_can_delete()`, `aa_check_can_change_role()` |
| Password recovery | `aa_set_email()`, `aa_get_email()`, `aa_request_password_reset()`, `aa_reset_token_login()`, `aa_reset_password_with_token()` |
| Two-factor authentication | `aa_totp_setup()`, `aa_totp_enable()`, `aa_totp_disable()`, `aa_totp_enabled()`, `aa_verify_second_factor()`, `aa_recovery_codes_left()`, `aa_totp_secret()`, `aa_totp_uri()`, `aa_totp_code()` |
| Login protection | `aa_login_gate()`, `aa_record_attempt()`, `aa_login_lock_remaining()`, `aa_global_throttled()`, `aa_clear_attempts()` |
| Sessions | `aa_issue_token()`, `aa_find_session_user()`, `aa_revoke_token()`, `aa_revoke_sessions()`, `aa_user_session_valid()` |
| Permissions | `aa_permissions_from_matrix()`, `aa_can()`, `aa_require()` |
| Events | `aa_events()` |
| UI modules | `aa_app_head()`, `aa_auth_ui()` and `aa_auth_server()`, `aa_users_ui()` and `aa_users_server()`, `aa_password_ui()` and `aa_password_server()`, `aa_totp_ui()` and `aa_totp_server()` |
| App helpers | `aa_session_guard()`, `aa_register_module()` |
| AI agent skills | `aa_install_skills()` |

Help for each function: `?aa_authenticate` and so on.

## Documentation

Vignettes (`browseVignettes("appauth")`):

* `getting-started` - quick start and core concepts;
* `integrating-existing-app` - how to move an existing application off hand-written authentication, including plaintext passwords;
* `extension-points` - permissions, roles, events, card slots, texts, styling;
* `testing-your-app` - how to test an application that uses `appauth`;
* `deployment` - HTTPS and nginx, cookies, backups, database file locking on Windows;
* `architecture-and-security` - design, threat model, guarantees and limitations.

Two working examples are in `inst/examples` (`system.file("examples", package = "appauth")`).

## Skills for AI agents

The package ships two skills in English: `appauth` (function reference, database schema, events) and `appauth-secure-shiny` (adoption, migrating old authentication, security audit). They help agents (Claude Code, Codex, Posit Assistant) write and review code that uses `appauth`.

```r
# Claude Code: .claude/skills in the current project
aa_install_skills()

# Codex, Posit Assistant: .agents/skills
aa_install_skills(agent = "agents")

# after updating the package
aa_install_skills(overwrite = TRUE)
```

The skill sources are in `inst/skills` (`system.file("skills", package = "appauth")`).

## Databases

| Database | Driver | Notes |
|---|---|---|
| SQLite (default) | `RSQLite` | Existing databases connect without any migration of data. |
| MySQL / MariaDB | `RMariaDB` | Login, role and hash columns are created with a binary collation that does not ignore trailing spaces (`utf8mb4_0900_bin`, in MariaDB `utf8mb4_nopad_bin`), so `Alice` and `alice` remain different logins. DDL cannot be rolled back, so migrations are idempotent and run under a `GET_LOCK` lock. |
| PostgreSQL | `RPostgres` | Auto-increment via `GENERATED BY DEFAULT AS IDENTITY`, migrations under an advisory lock. |
| DuckDB | `duckdb` | The file is opened by a single process: not suitable for an application running in several R processes. |

The application creates the connection; the package does the rest:

```r
# SQLite
conn <- aa_session_connection("app.db", prepare = TRUE)

# MySQL / MariaDB, PostgreSQL, DuckDB: a function that opens the connection
conn <- aa_session_connection(
  prepare = TRUE,
  connect = function() DBI::dbConnect(
    RMariaDB::MariaDB(), host = "db.example.com", dbname = "app",
    user = "app", password = Sys.getenv("APP_DB_PASSWORD")
  )
)
```

Dates are stored as UTC text (`YYYY-MM-DD HH:MM:SS`) in all databases and time is computed by R, so queries are the same everywhere. BigQuery and other analytical warehouses are not supported: they lack the unique constraints and atomic updates that one-time tokens and last-administrator protection rely on. In the cloud, use managed PostgreSQL or MySQL.

Tests can run on any supported database: `Rscript dev/run-tests-db.R duckdb` (see the script header).

## Principles

* The package contains only what must be identical in all applications (security). The role and permission matrix, logging switches and the contents of the access tab stay with the application.
* The package writes nothing to the application logs itself; it reports events to a hook.
* The database connection belongs to the application; the package works with SQLite, DuckDB, MySQL / MariaDB and PostgreSQL and does not call operating system commands.

## Limitations

Known limitations (the cookie is not `HttpOnly`, lockout is per login, BigQuery and other analytical warehouses are not supported, two-factor authentication is optional and TOTP only, single sign-on is Google only, no independent audit has been done) are listed in the `architecture-and-security` vignette.

## Development

Automated tests: `devtools::test()`; full check: `devtools::check()`. Module checks in a real browser (Chrome and Playwright) are described in `dev/e2e/README.md`. Change history is in `NEWS.md`.
