# Recipe: migrating from home-grown authentication and plain-text passwords to appauth

For an app that already has its own authentication: a `users` table, a login form, possibly plain-text passwords. Goal: replace the home-grown code with package calls without losing users, passwords or open sessions. Work IN A SEPARATE BRANCH and on a COPY of the database; touch the working database only after verification. Apps you are not entitled to change (someone else's, marked "do not touch") are only read and audited.

## What is supported

* a `users` table with columns `login`, `password`, `role` (the `id` and `blocked` columns may be absent, they are added);
* passwords that are either scrypt hashes (`$7$...`) or plain text (which must be migrated);
* optional tables `auth_sessions` and `login_attempts` (created if missing).

A schema with other column names (`username`/`pwd`) is not supported: first bring the table to the required names with an app migration. The package does not change the data of existing tables: it only adds the missing columns (`blocked`, `must_change`) and tables, plus the service table `appauth_migrations`.

## Step 0. Audit and copy

1. Stop the app and copy `app.db` (if it holds plain-text passwords, the copy contains them too: do not put it into git or synchronised folders, delete it after verification).
2. Run the code audit: `Rscript <skill>/scripts/audit_shiny_app.R <app folder>`: it shows home-grown authentication, SQL built by concatenation, plain-text passwords and other problems.
3. On the database copy:

```r
conn <- DBI::dbConnect(RSQLite::SQLite(), "app.copy.db")
aa_init_db(conn)                       # completes the schema on the copy
aa_check_default_accounts(conn)        # plain-text passwords, password = login, weak passwords
aa_list_users(conn)
DBI::dbDisconnect(conn)
```

### If the database is in .gitignore and a "database copy" is needed

To verify on a copy, the app must be able to take the database path not from a hard-coded value but from an environment variable (such as `WAREHOUSE_DB` or `APP_DB`): `db_path <- Sys.getenv("APP_DB", "app.db")`. Keep the copy OUTSIDE the repository or add it to `.gitignore` together with the password backups (`app.copy.db`, `*.bak_*`, `*.db-journal`). Run on the copy: `APP_DB=app.copy.db` (in PowerShell `$env:APP_DB = "app.copy.db"`), then `shiny::runApp(".")`. Delete the backup with plain-text passwords (`*.bak_*`) after verification.

## Step 1. Migrating plain-text passwords to hashes

Only if step 0 found plain-text passwords. Run with the app STOPPED.

```r
aa_migrate_plaintext_passwords("app.copy.db", dry_run = TRUE)      # what will change (writes nothing)
res <- aa_migrate_plaintext_passwords("app.copy.db")               # backup, one transaction, every hash verified
res$migrated; res$backup
```

After migration users sign in with their old passwords: the entered password is checked against the new hash. The function is safe to run again. The backup contains plain-text passwords: delete it after verification. While passwords are plain text, the package will not let anyone in with them (intentionally).

## Step 2. Replace the code

Wire up the package per SKILL.md and remove the home-grown code:

| Before | After |
| --- | --- |
| password hashing and checking, a login-and-password query against `users` | `aa_hash_password()`, `aa_verify_password()`, `aa_authenticate()` |
| the login form, the first-user window | `aa_auth_ui()` and `aa_auth_server()` |
| JS for the cookie, reading the token | `aa_app_head()` and auto-login inside `aa_auth_server()` |
| login attempts and login locking | inside the login module (`aa_login_gate()`) |
| finding a user by token, revoking a token | `aa_find_session_user()`, `aa_issue_token()`, `aa_revoke_token()` |
| periodic check "the user was blocked or deleted" | `aa_session_guard()` |
| logout | `auth$logout(reload = TRUE)` |
| permission checks | `aa_can()` with `aa_permissions_from_matrix()`, `aa_require()` |
| block, delete, role, password, allowability checks | `aa_set_blocked()`, `aa_delete_user()`, `aa_set_role()`, `aa_set_password()`, `aa_check_can_*()` |
| users table and card | `aa_users_ui()` and `aa_users_server()` |
| `dbConnect` without closing | `aa_session_connection()` |

What remains in the app: the permission matrix editor, log toggles, application-specific checks, writing to the log.

### Shiny load order

Shiny auto-loads `R/*.R` BEFORE `app.R`. If a file in `R/` calls a package function at top level (a constant like `provider <- aa_permissions_from_matrix(...)`), add `library(appauth)` to that file or move the call inside a function; otherwise a production start fails with `could not find function`, while the `testServer` test stays green.

### Do not lose open sessions

Set the previous cookie name: `aa_auth_server(..., cookie_name = "<previous name>")`. Tokens are compatible (sha256 as text). If the old app had no cookie auto-login, there is nothing to preserve: after the switch users will have to sign in once again, and that is fine (mention it in the announcement).

### Logging

Attach the hook to the existing log with the previous action names: recipes/logging-toggles.md.

### The app.R environment

Variables needed by functions from `R/` (first of all `auth_settings`) are created globally (`<<-`), otherwise tabs will be empty when started via `runApp`: SKILL.md, the "Common mistakes" section.

## Step 3. Verification on the copy

1. Run the app on the database copy.
2. Check: login with the old passwords, a wrong password, locking after a series of failures, tabs by role, adding, blocking and deleting a user, logout and auto-login.
3. Write a test of the wiring (use the lightweight template `assets/app-skeleton-db-permissions/tests/test_auth_light.R` as the base: the app loads as `runApp`, login with old passwords, permissions, rejection without the permission, connection closing) and run the app's existing automated tests: the package does not change permission and role behaviour, but changes details (see below). Tests for home-grown functions are moved into the package's tests or deleted.
4. Only then switch the production app.

## Rollback

Rollback means returning the previous code version (git) and, if needed, the database backup. Schema migrations only add columns and tables, so the old version of the app also works on the new database. Exception: if passwords were migrated to hashes, the old code must be able to verify scrypt hashes.

## What changes compared to home-grown authentication

* The login is compared exactly (case and spaces matter); login attempts are counted by the exact login. Existing pairs such as `kiruka`/`Kiruka` stay as different users; a new login that matches case-insensitively cannot be created.
* Plain-text passwords are not accepted: they must be migrated (step 1).
* You cannot be left without an active administrator: neither by blocking, nor by deleting, nor by changing the role.
* Changing a role, resetting a password, blocking and "log out on all devices" end open sessions (with `aa_session_guard()`).
* A password set by an administrator is temporary by default (`must_change_default`): the user must change it at login. To make passwords permanent: `must_change_default = FALSE`.
* The administrator role does not get permissions automatically: only those present in the permission source.
* New passwords are from `password_min` (6 by default) to `password_max` characters; existing ones are not affected.
* Weak new passwords (from a list of common ones, equal to the login, a single repeated character) are by default accepted with a warning and a `weak_password_set` event (`password_policy = "warn"`); to reject: `password_policy = "reject"`, to skip the check: `"off"`. For a new app without old test passwords `"reject"` is sensible.
* Deleting a user is two-step: the `delete` button opens a confirmation window, `delete_confirm` deletes. If the app's tests have a delete scenario, add pressing the confirmation.
* The users table gained columns "Created" and "Last login" (columns `created_at` and `last_login_at`, migration 6; the dates are empty for existing users). Your own stores of such dates (for example, from logs) can be removed.

## Example on an old schema

```r
db <- tempfile(fileext = ".db")
conn <- DBI::dbConnect(RSQLite::SQLite(), db)
DBI::dbExecute(conn, "CREATE TABLE users (login TEXT PRIMARY KEY, password TEXT, role TEXT)")
DBI::dbExecute(conn, "INSERT INTO users VALUES ('worker', 'plain-secret', 'user')")
aa_init_db(conn)
is.null(aa_authenticate(conn, "worker", "plain-secret"))   # TRUE: the plain-text password is not accepted
DBI::dbDisconnect(conn)
aa_migrate_plaintext_passwords(db, backup = FALSE)$migrated
conn <- DBI::dbConnect(RSQLite::SQLite(), db)
aa_authenticate(conn, "worker", "plain-secret")             # the old password works
```
