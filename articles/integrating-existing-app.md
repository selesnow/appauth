# Integrating into an existing app

For an app that already has its own authentication: a `users` table, a
hand-written login form, possibly plaintext passwords. The goal: replace
the hand-written code with package calls without losing users, passwords
or open sessions.

## What is supported

The package is designed for databases of this shape:

- a `users` table with the columns `login`, `password`, `role`. The `id`
  and `blocked` columns may be missing; they are added;
- passwords are either scrypt hashes (`$7$...`) or plaintext (which must
  be migrated, see below);
- optional `auth_sessions` and `login_attempts` tables (created if
  missing).

**Databases other than SQLite.** Upgrading old schemas (the `id`,
`blocked`, `email` columns and others) is designed for SQLite databases.
If you move the app to MySQL, PostgreSQL or DuckDB, create the tables
with the package
([`aa_init_db()`](https://alexey-seleznev.pro/appauth/reference/aa_init_db.md)
on an empty database) and migrate the users with
[`aa_create_user()`](https://alexey-seleznev.pro/appauth/reference/aa_create_user.md);
a `users` table created by hand in MySQL with an ordinary collation
compares logins case-insensitively. Migrating plaintext passwords to
hashes with
[`aa_migrate_plaintext_passwords()`](https://alexey-seleznev.pro/appauth/reference/aa_migrate_plaintext_passwords.md)
works on a file and only for SQLite.

**Not supported** is a schema with different column names (for example
`username`/`pwd`). In that case first bring the table to the required
names with an app migration, or create a view-copy, and only then plug
in the package.

The package does not change the data in existing tables: it only adds
missing columns (`blocked`, `must_change`, `email`, `totp_secret`,
`totp_enabled`, `totp_last_step`) and missing tables, as well as the
service table `appauth_migrations`.

## Migration plan

Do the migration **in a separate branch and on a copy of the database**.
Touch the production database only after verification.

### Step 0. Backup and inventory

1.  Stop the app and copy the database file (`app.db`) to a safe place.
    If the database has plaintext passwords, the copy contains them too:
    do not put it in git or synchronized folders, and delete it after
    verification.
2.  Look at how the passwords are stored:

``` r

conn <- DBI::dbConnect(RSQLite::SQLite(), "app.copy.db")
aa_init_db(conn)                        # completes the schema on the copy
aa_check_default_accounts(conn)         # weak and plaintext passwords
aa_list_users(conn)
DBI::dbDisconnect(conn)
```

[`aa_check_default_accounts()`](https://alexey-seleznev.pro/appauth/reference/aa_check_default_accounts.md)
shows the users whose password is stored as plaintext, equals the login
(`root`/`root`) or is in the list of common weak ones. The function does
not print the passwords.

### Step 1. Migrating plaintext passwords to hashes

Only if step 0 found plaintext passwords. Run it **while the app is
stopped**.

``` r

# first see what would change (writes nothing)
aa_migrate_plaintext_passwords("app.copy.db", dry_run = TRUE)

# run it: a backup next to the database, a single transaction,
# each new hash is verified against the original password before writing
res <- aa_migrate_plaintext_passwords("app.copy.db")
res$migrated   # whose passwords were migrated
res$backup     # path to the backup (it holds plaintext passwords!)
```

After the migration users sign in with their **old passwords**: the
entered password is checked against the new hash. It is safe to run the
function again: it skips hashes. Delete the backup after verification.

While passwords are stored as plaintext, the package will let nobody in
with them: a plaintext password is not accepted as a password. This is
deliberate.

### Step 2. Replace the authentication code

Plug in the package following the [getting started
guide](https://alexey-seleznev.pro/appauth/articles/getting-started.md)
and delete your own code. The table below maps typical hand-written
function names to the package; the names in your app may differ, but the
tasks are the same:

| Typical custom code | In the package |
|----|----|
| `hash_password()`, `verify_password()`, `is_password_hash()` | [`aa_hash_password()`](https://alexey-seleznev.pro/appauth/reference/aa_hash_password.md), [`aa_verify_password()`](https://alexey-seleznev.pro/appauth/reference/aa_verify_password.md), [`aa_is_password_hash()`](https://alexey-seleznev.pro/appauth/reference/aa_is_password_hash.md) |
| `authenticate_user()` | [`aa_authenticate()`](https://alexey-seleznev.pro/appauth/reference/aa_authenticate.md) |
| `validate_new_password()`, `validate_new_login()` | [`aa_validate_password()`](https://alexey-seleznev.pro/appauth/reference/aa_validate_password.md), [`aa_validate_login()`](https://alexey-seleznev.pro/appauth/reference/aa_validate_login.md) (for the whole form [`aa_validate_new_user()`](https://alexey-seleznev.pro/appauth/reference/aa_validate_new_user.md)) |
| `create_user()`, `create_first_admin()`, `set_user_password()` | [`aa_create_user()`](https://alexey-seleznev.pro/appauth/reference/aa_create_user.md), [`aa_create_first_admin()`](https://alexey-seleznev.pro/appauth/reference/aa_create_first_admin.md), [`aa_set_password()`](https://alexey-seleznev.pro/appauth/reference/aa_set_password.md) |
| `migrate_passwords_to_hash()` | [`aa_migrate_plaintext_passwords()`](https://alexey-seleznev.pro/appauth/reference/aa_migrate_plaintext_passwords.md) |
| `mod_auth_ui()`, `mod_auth_server()` (including the first administrator window) | [`aa_auth_ui()`](https://alexey-seleznev.pro/appauth/reference/aa_auth_ui.md), [`aa_auth_server()`](https://alexey-seleznev.pro/appauth/reference/aa_auth_server.md) |
| JS `setAuthCookie`, `clearAuthCookie`, `readAuthCookie` and `input$auth_cookie` in `app.R` | [`aa_app_head()`](https://alexey-seleznev.pro/appauth/reference/aa_app_head.md) and auto-login inside [`aa_auth_server()`](https://alexey-seleznev.pro/appauth/reference/aa_auth_server.md); with the default `cookie_mode = "httponly"` no cookie JavaScript is needed |
| `record_login_attempt()`, `login_lock_remaining()`, `login_global_throttled()`, `clear_login_attempts()` | [`aa_record_attempt()`](https://alexey-seleznev.pro/appauth/reference/aa_record_attempt.md), [`aa_login_lock_remaining()`](https://alexey-seleznev.pro/appauth/reference/aa_login_lock_remaining.md), [`aa_global_throttled()`](https://alexey-seleznev.pro/appauth/reference/aa_global_throttled.md), [`aa_clear_attempts()`](https://alexey-seleznev.pro/appauth/reference/aa_clear_attempts.md); the login module calls them itself through [`aa_login_gate()`](https://alexey-seleznev.pro/appauth/reference/aa_login_gate.md) |
| `login_security_settings()` (settings from `config.yaml`) | `aa_settings_from_list(conf$security)` |
| `normalize_login()` | not needed: the login is compared exactly (see “What changes”) |
| `ensure_login_attempts_table()`, `ensure_users_blocked_column()`, `prepare_login_protection()`, `prepare_user_blocking()` | [`aa_init_db()`](https://alexey-seleznev.pro/appauth/reference/aa_init_db.md) and [`aa_prepare_db()`](https://alexey-seleznev.pro/appauth/reference/aa_prepare_db.md) (or `aa_session_connection(prepare = TRUE)`) |
| `cleanup_security_tables()` | [`aa_cleanup()`](https://alexey-seleznev.pro/appauth/reference/aa_cleanup.md) (called when preparing the database and by the session guard) |
| `find_session_user()`, token lookup and revocation in `app.R` and the auth module | [`aa_find_session_user()`](https://alexey-seleznev.pro/appauth/reference/aa_find_session_user.md), [`aa_issue_token()`](https://alexey-seleznev.pro/appauth/reference/aa_issue_token.md), [`aa_revoke_token()`](https://alexey-seleznev.pro/appauth/reference/aa_revoke_token.md) |
| `user_session_valid(conn, login)` and the check every 30 seconds in `app.R` | [`aa_session_guard()`](https://alexey-seleznev.pro/appauth/reference/aa_session_guard.md) (checks both the role and the token; manually `aa_user_session_valid(conn, login, role, token)`) |
| `perform_logout()` | `auth$logout(reload = TRUE)` |
| `user_can()` | [`aa_can()`](https://alexey-seleznev.pro/appauth/reference/aa_can.md) with [`aa_permissions_from_matrix()`](https://alexey-seleznev.pro/appauth/reference/aa_permissions_from_matrix.md) |
| `require_permission()` | [`aa_require()`](https://alexey-seleznev.pro/appauth/reference/aa_require.md) |
| `is_user_blocked()`, `set_user_blocked()`, `delete_user_account()` | [`aa_get_user()`](https://alexey-seleznev.pro/appauth/reference/aa_get_user.md) (the `blocked` field), [`aa_set_blocked()`](https://alexey-seleznev.pro/appauth/reference/aa_set_blocked.md), [`aa_delete_user()`](https://alexey-seleznev.pro/appauth/reference/aa_delete_user.md) |
| `check_can_block_user()`, `check_can_delete_user()` | [`aa_check_can_block()`](https://alexey-seleznev.pro/appauth/reference/aa_check_can_block.md), [`aa_check_can_delete()`](https://alexey-seleznev.pro/appauth/reference/aa_check_can_delete.md), and also [`aa_check_can_change_role()`](https://alexey-seleznev.pro/appauth/reference/aa_check_can_change_role.md) |
| `users_overview()` | [`aa_users_overview()`](https://alexey-seleznev.pro/appauth/reference/aa_users_overview.md) |
| The user-facing part of `mod_access_ui()`/`mod_access_server()` (table, card, add, role, password, blocking, deletion) | [`aa_users_ui()`](https://alexey-seleznev.pro/appauth/reference/aa_users_ui.md) and [`aa_users_server()`](https://alexey-seleznev.pro/appauth/reference/aa_users_server.md) |
| `dbConnect` per session without closing | [`aa_session_connection()`](https://alexey-seleznev.pro/appauth/reference/aa_session_connection.md) |

These stay in the app (they do not go into the package):
application-specific checks such as `is_safe_task_name()`, the
permission matrix editor and log switches in the access module, and
writing to the log (`write_action_log`).

#### Do not lose open sessions

If the app already had cookie auto-login, users will not have to sign in
again if you set the same cookie name:

``` r

auth <- aa_auth_server("auth", conn, settings, cookie_name = "auth_token")
```

Tokens in the database are stored as sha256 text, so tokens issued
earlier will keep working as long as your old code stored them the same
way.

#### Logging

The package reports events to a hook. Connect it to your log-writing
function:

``` r

log_event <- function(event, user, session_id, value) {
  write_action_log(user = user, func = event, session_id = session_id, value = value)
}
```

The event catalog is
[`aa_events()`](https://alexey-seleznev.pro/appauth/reference/aa_events.md).
If the old log used its own action names (`'User add'`,
`'Login failed'`), map them in the hook with a single table so old
reports do not break:

``` r

legacy_names <- c(
  user_added   = "User add",
  user_removed = "User delete",
  login_failed = "Login failed",
  login_locked = "Login locked"
)

log_event <- function(event, user, session_id, value) {
  func <- if (event %in% names(legacy_names)) legacy_names[[event]] else event
  write_action_log(user = user, func = func, session_id = session_id, value = value)
}
```

The same in shorter form with the ready-made handler (the package does
event selection, names, the write switch and value conversion; details
in the `extension-points` vignette):

``` r

log_event <- aa_event_logger(
  function(action, user, session_id, value) {
    write_action_log(user = user, func = action, session_id = session_id, value = value)
  },
  actions = legacy_names
)
```

#### Common mistake: settings created in `app.R`, functions live in `R/`

An app launched with `shiny::runApp(folder)` loads `app.R` into its
**own environment**, while files from `R/` are often attached with
[`source()`](https://rdrr.io/r/base/source.html) into the **global**
one. If you create `auth_settings <- aa_settings(...)` in `app.R`, the
functions from `R/` (the permission check wrapper, the event hook, the
permission provider) will not see this variable and will fail with
`object 'auth_settings' not found`.

Permission checking in the package is closed by default, so the error
turns into “no permissions”: the tab registered by
[`aa_register_module()`](https://alexey-seleznev.pro/appauth/reference/aa_register_module.md)
stays empty, and the log contains only the package message
`appauth: the permission provider failed`.

What to do: assign such variables globally, like the config
(`auth_settings <<- ...`), or pass them to functions as arguments.

This applies to apps where files from `R/` are attached with an explicit
[`source()`](https://rdrr.io/r/base/source.html) into the global
environment. An app that relies on Shiny’s autoload has a different
quirk: Shiny itself attaches `R/*.R` **before** running `app.R`. So if a
file in `R/` calls a package function at the top level (for example
`aa_permissions_from_matrix(...)`), that file itself needs
[`library(appauth)`](https://alexey-seleznev.pro/appauth/), otherwise
launching through `runApp` fails with `could not find function`, even
though a `testServer` test, which loads `app.R` as a whole, stays green.
When testing the app, run it through
[`runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html) and be sure to
open the tabs as an administrator, see the `testing-your-app` vignette.

### Step 3. Verification on the copy

1.  Run the app on the copy of the database (pass the path through an
    environment variable or config).
2.  Check signing in with old passwords, a wrong password, lockout after
    a series of failures, tabs by role, adding, blocking and deleting a
    user, logout and auto-login.
3.  Run the app’s existing automated tests. The package does not change
    the behavior of permissions and roles, but it changes details: see
    the section below.
4.  Only then switch the production app and verify it the same way.

### Step 4 (optional). Password reset by email

If users have working addresses, enable password reset: hand-written
authentication usually lacks it, while with `appauth` it is added by
settings. The administrator enters addresses in the user card; for
existing users the `email` column is empty after the migration. The
sending function recipe, settings and limitations are described in the
`extension-points` vignette (section “Password reset by email”), and
behind nginx check `reset_base_url` (the `deployment` vignette).

### Step 5 (optional). Two-factor authentication

For apps with privileged roles, enable 2FA:
`aa_settings(totp_enabled = TRUE, totp_key = ...)`, the
[`aa_totp_ui()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_ui.md)
and
[`aa_totp_server()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_server.md)
block in the profile, and either ask administrators to turn it on or
list their roles in `totp_required_roles` to require setup at sign-in.
Set `totp_key` through an environment variable and do not lose it; for
existing users protection is off after the migration. Recipe and
limitations: the `extension-points` vignette (section “Two-factor
authentication”).

### Rollback

Rollback means restoring the database backup and the previous version of
the code. Schema migrations only add columns and tables, so the old
version of the app also works on the new database: it just does not use
the extra columns. Exception: if you migrated passwords to hashes, the
old code must be able to verify scrypt hashes.

## What changes compared to hand-written authentication

The package behaves more strictly than typical hand-written
authentication. Keep this in mind during the migration:

- **The login is compared exactly**, including case and spaces; failed
  attempts are counted the same way (a typical `normalize_login()`
  lowercases the login and trims spaces; now `ALICE` and `alice` have
  separate counters; old lowercase attempt records simply expire after a
  day). `Alice` and `alice` are different users. Existing pairs such as
  `bob`/`Bob` are kept and work as different people, but a new user
  whose login matches an existing one case-insensitively cannot be
  created.
- **Plaintext passwords are not accepted.** They must be migrated (step
  1).
- **You cannot be left without an active administrator**: neither by
  blocking, nor by deletion, nor by role change.
- **A role change takes effect immediately**: the open session of a user
  whose role was changed ends at the next check, and they sign in again
  with the new role.
- **Password reset and “end all sessions” end the user’s open
  sessions.**
- **A password set by an administrator is temporary by default** (the
  `must_change_default` setting): the user must change it at sign-in. To
  keep passwords permanent, set `must_change_default = FALSE`.
- **The administrator role does not get permissions automatically**:
  only those in your permission provider. It can always manage users.
- **New passwords**: from `password_min` (6 by default) to
  `password_max` characters. The rule applies only to new and reset
  passwords; existing ones are not affected.
- **Weak new passwords** (from
  [`aa_common_passwords()`](https://alexey-seleznev.pro/appauth/reference/aa_common_passwords.md),
  equal to the login, a single repeated character) are accepted with a
  warning by default (`password_policy = "warn"`, event
  `weak_password_set`). To reject them, set
  `password_policy = "reject"`; to skip the check, `"off"`.
- **Deleting a user requires confirmation**: the “Delete account” button
  opens a dialog with the “Yes, delete” and “Cancel” buttons. If the
  app’s automated tests have a deletion scenario, add a `delete_confirm`
  click after `delete`.
- **Creation and last login dates** are stored in the `created_at` and
  `last_login_at` columns (migration 6; for existing users the dates are
  empty) and shown in the user table. If the app used to keep such dates
  itself (for example, taken from logs), they can be removed.

## Example on an old schema

This is what a database with an old schema looks like (a table without
`id` and `blocked`, a plaintext password): after the schema is prepared
and the passwords are migrated, sign-in works.

``` r

library(appauth)

db <- tempfile(fileext = ".db")
conn <- DBI::dbConnect(RSQLite::SQLite(), db)
DBI::dbExecute(conn, "CREATE TABLE users (login TEXT PRIMARY KEY, password TEXT, role TEXT)")
#> [1] 0
DBI::dbExecute(conn, "INSERT INTO users VALUES ('worker', 'plain-secret', 'user')")
#> [1] 1

aa_init_db(conn)
is.null(aa_authenticate(conn, "worker", "plain-secret"))   # a plaintext password is not accepted
#> [1] TRUE
aa_check_default_accounts(conn)
#>    login role    reason
#> 1 worker user plaintext
DBI::dbDisconnect(conn)

aa_migrate_plaintext_passwords(db, backup = FALSE)$migrated
#> [1] "worker"

conn <- DBI::dbConnect(RSQLite::SQLite(), db)
aa_authenticate(conn, "worker", "plain-secret")             # the old password works
#>    login role blocked must_change
#> 1 worker user       0           0
DBI::dbDisconnect(conn)
unlink(db)
```
