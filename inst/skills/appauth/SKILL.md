---
name: appauth
description: Documentation, function reference, database schema, events and examples for the appauth R package (prefix aa_), which adds authentication and user management to Shiny apps on SQLite (default), DuckDB, MySQL / MariaDB and PostgreSQL. Covers login with username and password, users, roles, permissions, lockouts, sessions, cookie auto-login, password change, email password reset, two-factor authentication (TOTP), user sign-in with Google (OpenID Connect, single sign-on), disabling password login, and the authentication event log. ALWAYS activate this skill when a Shiny app needs anything to do with authentication, users, roles, tab permissions, lockouts, sessions, user passwords, 2FA, Google login, or tests of these parts, and whenever code or logs contain aa_settings, aa_init_db, aa_auth_server, aa_users_server, aa_can, aa_require, aa_session_guard, aa_event_logger or other aa_* functions, even if appauth is not named. Do NOT use it for authenticating scripts to Google APIs (Sheets, Drive, BigQuery), for other internal services or third-party APIs, for secrets in .Renviron, for Plumber APIs, or for Shiny apps without users. For adding auth to a new app, migrating a home-grown login, and security audits, use it together with the appauth-secure-shiny skill.
---

# The `appauth` R package reference

`appauth` gives Shiny apps secure authentication and user management: login, password hashes (scrypt), brute-force protection, lockouts, auto-login tokens, checks of open sessions, server-side permission checks and ready-made UI modules. It works with SQLite (default), DuckDB, MySQL / MariaDB and PostgreSQL (since 0.8.0); the app supplies the database connection. BigQuery and other analytical warehouses are not supported. The function reference in `references` was built from appauth 0.8.0.

## The main rule

**Do authentication in Shiny apps only through `appauth`.** Do not write home-grown user tables, password hashing, login forms, cookie tokens, lockouts or session checks: the package already implements all of these consistently and covers them with tests. The app keeps only its own parts: the permission matrix (which role can do what), the set of tabs, log switches, and app-specific checks.

If the project uses `renv`, the package must be recorded in `renv.lock` (see the "renv" section below).

## Minimal working example

```r
library(shiny)
library(appauth)

settings <- aa_settings()                                   # settings: the defaults suit most apps
provider <- aa_permissions_from_matrix(list(                # permissions: permission -> roles
  Tasks  = c("admin", "user", "viewer"),
  Run    = c("admin", "user"),
  Access = "admin"
))

log_event <- function(event, user, session_id, value) {     # the single place for logging
  message(sprintf("[appauth] %s user=%s value=%s", event, user, value))
}

ui <- fluidPage(
  aa_app_head(),            # styles and cookie script, once per page
  aa_auth_ui("auth"),       # login form or first-administrator creation
  uiOutput("main")
)

server <- function(input, output, session) {
  conn <- aa_session_connection("app.db", prepare = TRUE, settings = settings)  # closed with the session, schema prepared automatically
  auth <- aa_auth_server("auth", conn, settings, on_event = log_event)          # login, auto-login, logout
  aa_session_guard(auth, conn, settings)                    # blocking, deletion, role change and password reset take effect within 30 seconds

  aa_register_module(auth, "Access", provider, function() { # the tab's server part only for those who have the permission
    aa_users_server("users", conn, auth, settings, on_event = log_event)
  })

  output$main <- renderUI({
    req(auth$logged_in())
    user <- auth$user()                                     # list(login, role)
    tabsetPanel(
      tabPanel("Tasks",
        p("Signed in as ", strong(user$login)),
        if (aa_can(user, "Run", provider)) actionButton("run", "Run")),
      if (aa_can(user, "Access", provider)) tabPanel("Access", aa_users_ui("users"))
    )
  })

  observeEvent(input$run, {
    aa_require(auth, "Run", provider, on_event = log_event, settings = settings)  # the permission is checked IN EVERY handler
    showNotification("Done")
  })

  observeEvent(input$logout, auth$logout(reload = TRUE))
}

shinyApp(ui, server)
```

The first launch on an empty database offers to create an administrator. Working examples (Russian UI with permissions from YAML; English UI with permissions from the database and a slot in the user card): `system.file("examples", package = "appauth")`.

## Core concepts

* **User** is `list(login, role)`, taken from `auth$user()` (a reactive value, `NULL` when not signed in). Always take the role from server-side state, never from `input`.
* **Role** is one of `settings$roles` (by default `admin`, `user`, `viewer`). The role `settings$admin_role` manages users; everything else is defined by the app.
* **Permission** is the name of an action or section (`"Run"`, `"Access"`, `"Tasks"`). A role's set of permissions is defined by the *permission provider* (`provider`): `aa_permissions_from_matrix(matrix)` or your own `function(user)` that returns a vector of permission names. An admin does not get permissions by default.
* **Event**: the package writes nothing to logs itself, but reports events to the function `on_event(event, user, session_id, value)`. Catalog: `aa_events()` or [references/events.md](references/events.md).

## What the package guarantees

Passwords are stored only as scrypt hashes; a plaintext password in the database does not allow login; a login is locked after a series of failures (by default 5 in 15 minutes) plus a global per-minute failure limit; the auto-login token is stored in the database only as sha256; blocking, deletion, role change, password reset and "sign out on all devices" terminate open sessions; you cannot block, delete or demote yourself or the last active administrator; all SQL queries are parameterized; the permission check is closed by default (an error in the permission provider means "no permissions"). Email password reset (since 0.4.0, off by default): a one-time link with a 256-bit token (only sha256 in the database), the same form response for any login, limits on emails, all sessions are terminated after the change. Two-factor authentication TOTP (since 0.5.0, off by default and voluntary): the secret is encrypted in the database with the `totp_key` key, a code is accepted only once, recovery codes are single-use, wrong codes lock the login like password guessing, and a correct password is not recorded until the code is entered. Google sign-in (since 0.7.0, off by default, OpenID Connect with PKCE): only a user who already exists in the app can sign in, with an email equal to the Google account address; sign-in never creates new users, the role comes from the database, a blocked user cannot sign in; the signature and contents of the Google token are verified, `state` is single-use and matched against the browser cookie; the package's own 2FA is not requested for Google sign-in; password login can be disabled (`password_login = FALSE`) and this is enforced on the server. Known limitations: the cookie is not `HttpOnly`, lockout is per login (not per IP), single sign-on only through Google (no other providers), 2FA is TOTP only and cannot be made mandatory for roles.

## Which function does what

Full signatures, arguments and examples: [references/api.md](references/api.md) (table of contents) and the per-topic files. In brief:

| Task | Functions |
| --- | --- |
| Settings and texts (ru, en) | `aa_settings()`, `aa_settings_from_list()`, `aa_texts()`, `aa_text()` |
| Database (schema, migrations, connection) | `aa_init_db()`, `aa_prepare_db()`, `aa_session_connection()`, `aa_cleanup()`, `aa_schema_version()` |
| Passwords | `aa_hash_password()`, `aa_verify_password()`, `aa_validate_password()`, `aa_weak_password_warning()`, `aa_migrate_plaintext_passwords()`, `aa_check_default_accounts()` |
| Users (scripts, tests, administration) | `aa_create_user()`, `aa_create_first_admin()`, `aa_authenticate()`, `aa_set_password()`, `aa_change_own_password()`, `aa_set_role()`, `aa_set_blocked()`, `aa_delete_user()`, `aa_list_users()`, `aa_users_overview()` |
| Email password reset | `aa_set_email()`, `aa_get_email()`, `aa_request_password_reset()`, `aa_reset_token_login()`, `aa_reset_password_with_token()`; settings `reset_enabled`, `send_reset`, `reset_base_url` |
| Two-factor authentication (TOTP) | `aa_totp_setup()`, `aa_totp_enable()`, `aa_totp_disable()`, `aa_totp_enabled()`, `aa_verify_second_factor()`, `aa_recovery_codes_left()`, `aa_totp_secret()`, `aa_totp_uri()`, `aa_totp_code()`; settings `totp_enabled`, `totp_key`, `totp_issuer`, `totp_window` |
| Google sign-in (since 0.7.0) | the app has no dedicated functions: it is enabled by the settings `google_enabled`, `google_client_id`, `google_client_secret`, `google_redirect_uri`, `google_domains`, `password_login` in `aa_settings()`; the button and the return from Google are handled by `aa_auth_server()` |
| Login and session protection | `aa_login_gate()`, `aa_issue_token()`, `aa_find_session_user()`, `aa_revoke_sessions()`, `aa_active_autologins()` (how many remembered devices a user has), `aa_user_session_valid()` |
| Permissions and events | `aa_permissions_from_matrix()`, `aa_can()`, `aa_require()`, `aa_events()`, `aa_event_logger()` |
| UI modules | `aa_app_head()`, `aa_auth_ui()` and `aa_auth_server()`, `aa_users_ui()` and `aa_users_server()`, `aa_password_ui()` and `aa_password_server()`, `aa_totp_ui()` and `aa_totp_server()` |
| App helpers | `aa_session_guard()`, `aa_register_module()` |

Module element ids for tests and Playwright (`auth-login`, `users-add`, `password-old`...), choosing a role in selectize, and forging a request: [references/ui-ids.md](references/ui-ids.md). If `Rscript` fails on `library(reticulate)` or picks up foreign libraries, run it with `--no-init-file --no-site-file`.

The result of `aa_auth_server()`: `auth$user()`, `auth$logged_in()`, `auth$role()`, `auth$token()`, `auth$logout(reason = NULL, reload = FALSE)` and `auth$logout_all(reload = TRUE)` (sign out on all devices; show a confirmation dialog before calling it).

## Extension points

Permissions (a matrix or any function `function(user)`), roles (`aa_settings(roles =, admin_role =)`), the `on_event` event hook, user card slots (`extra_card_ui(login, ns)` and `extra_card_server(input, output, session, login)` in `aa_users_server()`), texts (`aa_texts("en", key = "...")`), styling (`--aa-*` CSS variables, light theme), security parameters (`aa_settings()`). Details and examples: [references/extension-points.md](references/extension-points.md).

## Database schema and migrations

The package owns the tables `users` (the `email` column since 0.4.0, the `totp_*` columns since 0.5.0), `auth_sessions`, `login_attempts`, `password_resets`, `totp_recovery`, `oauth_states` (since 0.7.0, Google sign-in parameters) and the service table `appauth_migrations`; `aa_init_db()` builds up the schema idempotently and is compatible with older home-grown schemas. Columns, migration versions, and what to do with an old schema: [references/schema.md](references/schema.md).

## Common mistakes (from real deployments)

1. **Settings are created in `app.R`, but the functions live in `R/`.** If the files from `R/` are attached with an explicit `source()` into the global environment, while `shiny::runApp(dir)` loads `app.R` into its own environment, the variable `auth_settings <- ...` from `app.R` is invisible to those functions: the permission check fails "closed" and the tab stays empty (the log shows `object 'auth_settings' not found`). Create such variables globally (`auth_settings <<- ...`) or pass them as arguments.
1a. **Shiny autoloads `R/*.R` BEFORE `app.R`.** A file in `R/` that calls a package function at the top level (`provider <- aa_permissions_from_matrix(...)`) fails with `could not find function` until `library(appauth)` is called in that file itself, while a `testServer` test stays green. Add `library(appauth)` to such a file or call package functions only inside functions.
1b. **Custom roles and `settings`.** A role is checked against `settings$roles`: if the app has its own roles (`owner`, `editor`), pass `settings` to `aa_create_user()`, `aa_create_first_admin()`, `aa_set_role()` and to tests, otherwise non-standard roles are rejected as an invalid role.
2. **An old version of the package is loaded in the R session.** Pressing "Run App" again in the same session does not reload the package: the new `app.R` calls a function that does not exist in the loaded version (`attempt to apply non-function`). Fix: restart the R session.
3. **Permissions checked only in the UI.** A hidden button is not protection: put `aa_require(...)` as the first line of every action handler.
4. **Users created with SQL queries** with a plaintext password. Create them with `aa_create_user()`/`aa_create_first_admin()`, and migrate passwords with `aa_migrate_plaintext_passwords()`.
5. **Your own database connection without closing it.** Use `aa_session_connection()`: on Windows an unclosed connection keeps the `app.db` file locked, and with MySQL and PostgreSQL extra connections linger.
6. **Forgot `aa_session_guard()`.** Without it, blocking, role change, password reset and "sign out everywhere" do not close already open sessions.
6a. **`aa_session_connection(db)` without `prepare = TRUE`** does not prepare the database schema: prepare it yourself at startup (`aa_prepare_db(con, settings)` once when the process starts).
6b. **Normal package messages in the console.** When a permission is denied, `aa_require()` writes a line like `appauth: access denied: ...` to the console (it ends up in `app.Rout`): this is normal behavior, not an error. A login lockout after a series of failures goes through the `login_attempts` table, while `users.blocked` is set only by a manual block by an administrator: when testing lockout with passwords, `blocked` stays 0, this is not a bug. (The exact message text depends on the interface language.)
6c. **The "require password change" checkbox** in the add-user dialog and on password reset takes its default from `aa_settings(must_change_default =)` (on by default).
6d. **Weak passwords** (from `aa_common_passwords()`, equal to the login, a single repeated character) are accepted by default with a warning and the `weak_password_set` event (`password_policy = "warn"`). To reject them: `aa_settings(password_policy = "reject")`, after which `aa_create_user()` and others raise `appauth_error_user` with the reason `password_common`, `password_equals_login` or `password_repeated`. Use proper passwords in tests too.
6e. **Deleting a user in `aa_users_server()` takes two steps**: `delete` only opens the confirmation dialog, and `delete_confirm` deletes. In `testServer` tests and Playwright you must press confirm after `delete`.
6f. **Dates** `created_at` and `last_login_at` (UTC, text) are present in `aa_get_user()`, `aa_list_users()`, `aa_users_overview()`; for users created before 0.3.0 they are empty, which is not an error. Cookie login does not update `last_login_at`.
6g. **Event log**: instead of a hand-written hook with a lookup table, use `aa_event_logger(writer, actions = , enabled = )`, see [references/events.md](references/events.md).
6h. **Password reset** is enabled only together with `send_reset` and `reset_base_url` (otherwise `aa_settings()` raises an error), and the user must have an email set, otherwise no email is sent (the reason `no_email` appears only in the event). `reset_base_url` is the app address as the user sees it (including the nginx prefix); the link is built as `<reset_base_url>/?reset=<token>`. After changing the password via the link the user signs in the usual way; there is no auto-login. Details: [references/extension-points.md](references/extension-points.md). In `testServer` tests the address bar is mocked via `testthat::local_mocked_bindings(aa_url_search = function(session) "?reset=...", .package = "appauth")`.
6i. **Two-factor authentication** is enabled only with `totp_key` (a string of at least 16 characters, otherwise `aa_settings()` raises an error); the `aa_totp_server()` module is attached once in the user's account page. The key must not be lost or changed: the secrets become unreadable. A code is accepted only once: in tests, for a second sign-in take the code for the next step, `aa_totp_code(secret, Sys.time() + 30)`. Auto-login by cookie does not ask for a code. For your own UI without the modules: call `aa_login_gate()` before `aa_verify_second_factor()` and `aa_record_attempt()` after a wrong code, otherwise the code can be guessed. Details: [references/extension-points.md](references/extension-points.md).
6j. **Google sign-in** (a detailed recipe is in the `appauth-secure-shiny` skill, recipe `google-login`). A domain with HTTPS is required: Google does not allow a redirect to an IP address. `google_redirect_uri` must match the OAuth client's "Authorized redirect URIs" exactly (with or without a trailing slash). Keep the client secret only in an environment variable, never in the repository. The user must have an email equal to the Google account address, otherwise sign-in is denied (`no_user`); there is no auto-creation. `google_domains` is checked against both the token's `hd` (the primary domain of the Workspace organization) and the email domain: with secondary domains list both; an empty list disables the domain check (then any Google account, including Gmail, is let in, but only with the email of an existing user), while a non-empty list rejects personal accounts (they have no `hd`). `password_login = FALSE` is allowed only together with `google_enabled = TRUE`; first verify Google sign-in as an administrator. The Internal consent screen type admits only accounts of your Workspace organization. If the app is opened both by IP and by domain, appauth 0.7.1+ is required: the button on the other address redirects to the return address (`?google=1`), otherwise sign-in ends with `bad_browser`. Google is not called in tests: mock `aa_google_exchange_code`, `aa_google_fetch_jwks` and `aa_url_search` via `testthat::local_mocked_bindings(.package = "appauth")` and sign the tokens with a test key.
7. **`aa_can()`/`aa_require()` outside a reactive context with a matrix function reading a `reactiveVal`.** Inside `observe`/`observeEvent` everything works; in ordinary code wrap the call in `isolate()`.
8. **Slow tests.** scrypt is deliberately slow (fractions of a second): in tests create only the users who actually sign in.
9. **The login is compared exactly.** `Alsey` and `alsey` are different users, but a new login that matches an existing one case-insensitively cannot be created.
10. **`renv` snapshots.** When updating renv projects, `renv::snapshot(packages = ...)` overwrites the lock file with only the listed packages: see the section below.

## renv: how to add `appauth` to a project

A project that uses `renv` needs an entry for `appauth` in `renv.lock`, otherwise `renv::restore()` will not install the package. **Do not use `renv::snapshot(packages = "appauth")` on the main lock file**: it leaves only the specified package and its dependencies in the file. A safe way: copy the installed package folder into the project library, get the entry from a temporary lock file and paste it into the main one.

```r
renv_lib <- .libPaths()[1]
file.copy(file.path(R.home("library"), "appauth"), renv_lib, recursive = TRUE)

tmp_lock <- tempfile(fileext = ".lock")
renv::snapshot(packages = "appauth", lockfile = tmp_lock, prompt = FALSE)
entry <- renv::lockfile_read(tmp_lock)$Packages$appauth

lock <- renv::lockfile_read("renv.lock")
lock$Packages$appauth <- entry
lock$Packages <- lock$Packages[order(tolower(names(lock$Packages)))]
renv::lockfile_write(lock, "renv.lock")
```

Check `git diff renv.lock`: there should be few changes (the `appauth` entry and, if needed, new dependencies).

## Other databases (since 0.8.0)

SQLite is the default, but all package functions also work on DuckDB, MySQL / MariaDB and PostgreSQL: the package detects the database by the connection class (`RSQLite`, `duckdb`, `RMariaDB`, `RPostgres`). Only the creation of the connection changes in the app:

```r
conn <- aa_session_connection(
  prepare = TRUE, settings = settings,
  connect = function() DBI::dbConnect(
    RMariaDB::MariaDB(), host = "db.example.com", dbname = "app", user = "app",
    password = Sys.getenv("APP_DB_PASSWORD")
  )
)
```

What to know (details: [references/schema.md](references/schema.md), the `other-databases` recipe of the `appauth-secure-shiny` skill):

* Create a separate schema (database) for the package tables: `aa_init_db()` creates seven tables. The database user needs the `CREATE`, `ALTER`, `INDEX` privileges and the usual `SELECT`, `INSERT`, `UPDATE`, `DELETE`.
* Time is stored as UTC text in all databases and computed in R: do not use `datetime('now')` and similar SQLite functions in your own queries and tests, pass the time as a parameter (`format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC")`).
* Placeholders in app queries: PostgreSQL (`RPostgres`) uses only `$1, $2`, the others use `?`; the app does not need to write its own SQL against the package tables, the package functions cover that.
* MySQL: logins are in columns with a binary collation without trailing-space padding, DDL is not rolled back (migrations are idempotent and run under a `GET_LOCK` lock). Do not use a `users` table created by hand with an ordinary collation: logins would become case-insensitive.
* DuckDB: the file is opened by one process, so it suits only an app running in a single R process.
* BigQuery is not supported: it lacks the unique constraints and atomic updates that single-use tokens and the last-administrator protection rely on. For the cloud, use managed PostgreSQL or MySQL.
* Building up older home-grown schemas and `aa_migrate_plaintext_passwords()` (which works on a file) are SQLite only.
* Any other database is rejected with an error of class `appauth_error_connection`.
* The package's own tests on a given database: `Rscript dev/run-tests-db.R sqlite|duckdb|mysql|postgres` in the package sources.

## Related skill

`appauth-secure-shiny` guides the rollout from requirements to verification: a step-by-step scenario, recipes for the customizable parts (the permission matrix and its editor, log switches, a config editor, handler protection), migration from home-grown authentication and plaintext passwords, a security checklist, and a script for auditing another app.
