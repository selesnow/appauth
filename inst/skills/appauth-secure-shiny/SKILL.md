---
name: appauth-secure-shiny
description: Step-by-step guide to secure authentication and hardening of Shiny apps with appauth. Helps add login, roles, permissions and user management, migrate home-grown auth and plaintext passwords, add Google sign-in (OIDC/SSO), opt-in self-registration by email or on first Google sign-in, and run a security audit (SQL injection, XSS, JS/runjs injection, secrets, UI-only permissions, user-controlled paths, SameSite/Secure cookies, HTTPS, nginx), with checklists and tests. ALWAYS activate when asked to add or rework Shiny login, username/password, roles, permissions, lockouts or sessions, to protect an app, or to audit its security, even if appauth is not named. Do NOT use for script authentication to Google APIs, plain R scripts or packages without Shiny. Function reference comes from the sibling appauth skill shipped in the same package.
---

# Secure authentication in Shiny apps

This guide leads an implementation from the questions to ask the app owner through to verifying the result. **We do not write the authentication core ourselves (passwords, lockouts, sessions, permissions, login and user-management modules): we use the `appauth` package** (function documentation is in the `appauth` skill). What stays in the app is only what differs between apps: the permission matrix and its editor, the set of tabs, log toggles, the config editor, and protection of app-specific actions. These "variable parts" are implemented following the recipes in `references/recipes/`.

## Three working modes

| Mode | When | What to do |
| --- | --- | --- |
| A. New app | no authentication yet | interview -> `assets/app-skeleton` -> implementation steps -> tests -> checklist |
| B. Migration from custom authentication | there is a users table, a login form, possibly plaintext passwords | branch and database copy -> audit -> `recipes/legacy-migration.md` -> tests on the copy -> checklist |
| C. Audit of someone else's app | security needs to be assessed, no request to change code | read only: `scripts/audit_shiny_app.R` -> findings report with priorities |

Determine the mode from the request. If unclear, ask.

## Working rules

1. **Plan first, code second.** Before changing the app, lay out what you change and in which files, and get the user's agreement. In mode C nothing is changed.
2. **Apps that are "off limits"** (third-party, production, marked as do-not-touch) are only read and audited. Implementation is done in a separate branch and on a copy of the database.
3. **Never print secrets** (`.Renviron`, keys, tokens, passwords, cookie values) in the answer, logs or reports. In an audit report give the file and line, not the value.
4. **Do not change live databases without stopping the app and taking a backup**; schema and password migrations go on a copy first.
5. **Verify the running app.** `testServer` tests are not enough: open the app in a browser (Playwright, Chrome), launching it the same way as in production: `shiny::runApp(folder)`, not `source("app.R")` (otherwise environment and load-order errors disappear, see "Common mistakes").
   If `Rscript` fails on `library(reticulate)` or picks up libraries from another project (foreign `R_LIBS_USER`, `RENV_PROJECT`, `.Rprofile`), run it with `--no-init-file --no-site-file` (the skill scripts too: `Rscript --no-init-file --no-site-file <skill>/scripts/audit_shiny_app.R <folder>`); on Windows point R temporary files to `tempdir()`/`Sys.getenv("TEMP")`, not `/tmp/...`.
6. After code changes in a project that has a `NEWS.md`, add an entry to it (project format) and bump the version according to project rules.

## 1. Interview before starting

Ask the questions whose answers change the decision (no more than one or two rounds, decide the rest by default):

* Which **roles** are needed (default `admin`, `user`, `viewer`) and which of them is the administrator?
* How are **permissions** defined: a "permission -> roles" matrix in `config.yaml` (default) or per-user / per-group permissions from the database?
* Is a **permission editor** for roles in the UI (an "Access" tab) and **log toggles** needed?
* **Where to write events** (app log, Telegram, nowhere)? Are there already log tables and custom action names (they must be preserved)?
* Is there a **custom users table** and **plaintext passwords**? Are there open sessions that must not be lost (which cookie name was used)?
* Where is the app **hosted** (server with nginx and HTTPS, Docker/Linux, locally)? Who configures the proxy?
* Is **Google sign-in** needed (single sign-on for Workspace staff)? Does the app have a domain with HTTPS, are there rights to an OAuth client in Google Cloud, should password login stay as a fallback?
* Is **self-registration** needed (email confirmation or immediate creation, allowed domains, role, hourly limit), including automatic viewer creation on the first verified Google sign-in?
* **UI language** (ru or en)? Are custom texts needed?
* Is a **custom field or block in the user card** (slot) needed, i.e. extra user data?
* Who is the **first administrator** and how is it created?

## 2. Mode A: new app

1. Preparation. Pick a template according to the permission model:
   * **permissions from a "permission -> roles" matrix** (default): skeleton `assets/app-skeleton` (a ready app: login, matrix in `config.yaml`, "Access" tab with the permission editor and log toggles, personal-cabinet buttons; test `assets/tests/test_auth_smoke.R`). Copy into a new folder: `cp -r <skill>/assets/app-skeleton/. <app folder>/` and copy `<skill>/assets/tests/*` into `<app folder>/tests/` (create the `tests` folder); on Windows PowerShell: `Copy-Item -Recurse "<skill>\assets\app-skeleton\*" "<app folder>"`;
   * **per-user permissions from the database** (no matrix and no `config.yaml`): skeleton `assets/app-skeleton-db-permissions` (own roles, permission source from a table, user-card slot for granting permissions, lightweight test `tests/test_auth_light.R`) and recipe `recipes/permissions-from-db.md`.
   For an existing app: `Rscript --no-init-file --no-site-file <skill>/scripts/scaffold_auth.R <app folder> --with-tests` creates `R/auth_setup.R`, `config.security.example.yaml`, a test template and prints the manual steps (`app.R` is not edited automatically).
2. Step-by-step implementation (details and code are in the recipes):
   1. Config: `config.yaml` with `security` sections and the permission matrix, kept out of git, missing keys are appended at startup: `recipes/config-editor.md`.
   2. `app.R`: `library(appauth)`, settings **globally** (`auth_settings <<- build_auth_settings(conf$security)`), `aa_prepare_db()` at startup.
   3. Database connection: `aa_session_connection()`, closed together with the session: `recipes/db-connection-lifecycle.md`.
   4. UI: `aa_app_head()` and `aa_auth_ui("auth")`; `server`: `aa_auth_server(...)` with **your own cookie name**, `aa_session_guard()`.
   5. Permissions and tabs: `recipes/permissions-matrix.md`, server modules registered only when the permission is held: `recipes/role-gated-modules.md`.
   6. Protect EVERY handler with `require_permission()`/`aa_require()` as the first line, and validate inputs: `recipes/handler-guards.md`.
   7. The "Access" tab (`aa_users_ui()`/`aa_users_server()`, permission editor): `recipes/permissions-matrix.md`.
   8. Logging via the `on_event` hook and toggles: `recipes/logging-toggles.md`.
   9. Personal cabinet (password change, sign out on all devices with confirmation): `recipes/personal-cabinet.md`.
   9c. Google sign-in, single sign-on SSO (if needed, off by default; requires a domain with HTTPS and appauth 0.7.0+): `recipes/google-login.md`.
   9e. Self-registration (if needed, off by default; requires appauth 0.11.0+): settings `registration_enabled`, `registration_verify_email`, `registration_domains`, `registration_role`, `registration_max_per_hour` and `google_signup`; token flow, generic responses and cleanup are in the `appauth` skill, section "Self-registration" and `references/api-self-registration.md`.
   9b. Two-factor authentication (if needed, off by default): `recipes/two-factor.md`.
   9a. Password recovery by email (if needed, off by default): `recipes/password-reset.md`.
   9d. A different database instead of SQLite (MySQL / MariaDB, PostgreSQL, DuckDB; requires appauth 0.8.0+): `recipes/other-databases.md`.
   10. First administrator and a spare administrator: `recipes/first-admin.md`.
   11. Tests: `recipes/testing.md`, templates `assets/tests/test_auth_smoke.R` (with `config.yaml`) or `assets/app-skeleton-db-permissions/tests/test_auth_light.R` (without it). UI element identifiers for Playwright: `references/ui-ids.md` of the `appauth` skill.
   12. Deployment: HTTPS, nginx, cookie `recipes/cookie-and-https.md`; Docker `recipes/docker-deployment.md`; for a project using `renv`, an `appauth` entry in `renv.lock` (`appauth` skill, section "renv").
3. Verification: checklist `references/security-checklist.md` + `Rscript <skill>/scripts/audit_shiny_app.R <folder>` + a run in the browser.

## 3. Mode B: migration from custom authentication

1. A separate branch (`git checkout -b appauth_pilot`), a database backup, work on a COPY of the database.
2. Audit: `Rscript <skill>/scripts/audit_shiny_app.R <folder>`: what is home-grown, what is dangerous.
3. Step-by-step plan and migration: `recipes/legacy-migration.md` (a "was -> now" table, migrating plaintext passwords with `aa_migrate_plaintext_passwords()`, keeping open sessions via the old cookie name, a hook with the old action names, rollback).
4. Remove the custom authentication files (passwords, lockouts, login form, session checks) only after tests and the browser check on the database copy have passed.
5. Tests of the old functions move into the package's tests (already covered there) or are deleted; add a test of the app wiring: the lightweight template `assets/app-skeleton-db-permissions/tests/test_auth_light.R` (app without `config.yaml`) or `assets/tests/test_auth_smoke.R`. If the database is in `.gitignore`, take the database path from an environment variable (recipe `legacy-migration.md`).
6. Tell users about behaviour changes (exact login match, temporary passwords, instant sign-outs) in NEWS and the announcement.

## 4. Mode C: audit of someone else's app

1. Run `Rscript <skill>/scripts/audit_shiny_app.R <folder> [--md]`. The script only reads code. It finds custom authentication, plaintext passwords, SQL built by concatenation, commands from `input`, permissions enforced only in the UI, `escape = FALSE`, secrets in code and in git, unclosed connections, database download and more. These are heuristics: **verify every finding against the code** (false positives are possible), and the absence of findings does not mean the app is secure.
2. Supplement manually, using `references/security-checklist.md`, what the script cannot see: HTTPS and proxy, backups, file permissions, the "spare administrator" role, database contents (`aa_check_default_accounts()` on a copy).
3. Report: a one-paragraph summary, then a table of findings by priority (critical / before release / to verify / FYI) with file and line, for each finding a decision (fix, or accept the risk and why) and a link to a recipe. Do not print secret values.
4. Do not change code until the user approves the fix plan.

## 5. What not to do (anti-patterns)

| Anti-pattern | Why it is bad | Correct approach |
| --- | --- | --- |
| Own user tables, hashes, login forms | we repeat solved problems and make mistakes | `appauth` |
| Plaintext passwords or a fast hash (md5, sha) | the database is stolen and the passwords are recovered | scrypt via `appauth`, migrate with `aa_migrate_plaintext_passwords()` |
| Permissions only in the UI (a button is hidden) | the handler can be called from the browser | `require_permission()` in every handler |
| Role taken from `input` or a global variable | can be forged, or shared across all sessions | `auth$user()$role` |
| SQL by concatenation (`paste0`, `glue`) | SQL injection | `params = list(...)` |
| `system(paste(...input...))` | command execution | `system2()` with a vector of arguments, whitelist of values |
| `escape = FALSE`, `HTML(paste(...))` with foreign data | XSS | `tags$*()`, escaping |
| `eval(parse(text = input$x))` | code execution | do not use |
| Downloading the database file from the UI | leak of hashes and tokens | serve only the needed tables, without auth tables |
| Secrets and `.Renviron` in git | leak | environment variables, `.gitignore`, rotate exposed secrets |
| `dbConnect` without closing | database file stays locked (Windows) | `aa_session_connection()` |
| App over HTTP without a proxy | password and token in clear text | HTTPS, Shiny port closed |
| A single admin | a login lockout can cut off management | spare administrator |

## 6. Verifying the result

* Checklist `references/security-checklist.md`: critical items (A1, A3, B1, B5, C1, C2, E1, E2, F1, G1) are closed, and there is a decision for the rest.
* `Rscript <skill>/scripts/audit_shiny_app.R <folder> --fail-on=high` exits with code 0.
* The automated test `tests/test_auth_smoke.R` (the app loads as `runApp`, first administrator, "Access" tab rendered, permissions, lockouts, connection closing) is green.
* The app is opened in a browser as an administrator and as an ordinary role: login, tabs, lockout, sign-out, auto-login.
* A spare administrator is created, and the first administrator is not left "on an open window".

## 7. Common mistakes (from a real implementation)

1. **Empty "Access" tab after implementation.** If files from `R/` are attached with an explicit `source()` into the global environment, while `app.R` under `runApp` is loaded into its own environment, an ordinary assignment `auth_settings <- ...` in `app.R` is not visible to those functions, and the permission check fails "closed" (`object 'auth_settings' not found`). Settings must be assigned globally (`<<-`), and in the test `app.R` should be loaded into a separate environment and the tab contents checked as an administrator.
1a. **`could not find function` in a production run although the test is green.** Shiny itself auto-loads `R/*.R` BEFORE `app.R`. A file in `R/` that calls a package function at top level (`provider <- aa_permissions_from_matrix(...)`) fails until `library(appauth)` is called in that file. Either add `library(appauth)` to the file, or call package functions only inside functions (as in the skill skeletons).
1b. **"Invalid role" when creating users in a test or script.** The app has its own roles but `settings` was not passed: pass `auth_settings` to `aa_create_user()`, `aa_create_first_admin()`, `aa_set_role()`.
2. **"attempt to apply non-function" when calling a package function.** An old version of `appauth` is loaded in the R session: pressing "Run App" again does not reload the package. Restart the R session.
3. **`renv::snapshot(packages = "appauth")` truncated `renv.lock`** to a single package. Add the entry through a temporary lock file (see the `appauth` skill).
4. **Audit and tests are "green" but the production run fails.** Check the running app (`runApp`), not only `testServer`.
5. **Forgot `aa_session_guard()`:** lockout, role change, password reset and "sign out everywhere" will not close already open sessions.

Everything else (mistakes in using package functions) is in the `appauth` skill.

## Skill structure and what to read when

| File | When to read |
| --- | --- |
| `references/threat-model.md` | risk assessment, what the package covers and what is left to the app, known limitations |
| `references/security-checklist.md` | final check and mode C |
| `references/recipes/permissions-matrix.md` | permission matrix, permission source, role permission editor, custom roles |
| `references/recipes/permissions-from-db.md` | per-user permissions from the database, user-card slot, tests protecting the slot |
| `references/recipes/role-gated-modules.md` | registering the server parts of tabs by permission |
| `references/recipes/handler-guards.md` | protecting handlers, input validation, running commands, paths, SQL, HTML |
| `references/recipes/logging-toggles.md` | event hook, logs, log toggles |
| `references/recipes/config-editor.md` | `config.yaml` outside git, appending settings, config editor |
| `references/recipes/first-admin.md` | first and spare administrator |
| `references/recipes/db-connection-lifecycle.md` | database connections, closing, SQLite file lock on Windows |
| `references/recipes/other-databases.md` | MySQL / MariaDB, PostgreSQL, DuckDB instead of SQLite: connection, permissions, collation, tests, what is missing (BigQuery) |
| `references/recipes/cookie-and-https.md` | auto-login cookie, HTTPS, nginx, brute-force protection behind a proxy |
| `references/recipes/legacy-migration.md` | mode B: migration from custom authentication and plaintext passwords |
| `references/recipes/personal-cabinet.md` | password change, sign-out on all devices |
| `references/recipes/google-login.md` | Google sign-in (SSO): domain and HTTPS, OAuth client, settings, domains, disabling the password, diagnosing rejections, limitations |
| `references/api-self-registration.md` (in the `appauth` skill) | opt-in self-registration: settings, email confirmation or immediate creation, allowed domains, role, hourly limit, generic responses and cleanup |
| `references/recipes/two-factor.md` | TOTP two-factor authentication: encryption key, profile block, lost phone, limitations |
| `references/recipes/password-reset.md` | password recovery by email: sending the message, `reset_base_url`, user addresses, limitations |
| `references/recipes/docker-deployment.md` | Docker and Linux, `renv`, volumes |
| `references/recipes/database-download.md` | downloading the database from the UI |
| `references/recipes/testing.md` | app tests, checking in the browser |
| `assets/app-skeleton/` | a ready app skeleton (permission matrix in `config.yaml`) for mode A |
| `assets/app-skeleton-db-permissions/` | skeleton for permissions from the database and custom roles (no `config.yaml`), lightweight test |
| `assets/tests/` | end-to-end test template (with `config.yaml`) and helper |
| `references/ui-ids.md` (in the `appauth` skill) | element identifiers of the modules for tests and Playwright |
| `scripts/audit_shiny_app.R` | app audit (`audit_selftest.R` is the script's self-check) |
| `scripts/scaffold_auth.R` | implementation preparation (creates files, overwrites nothing without `--force`) |
