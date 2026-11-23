# 2026-11-23 | OPENCODE (Alsey)
Implemented opt-in self-registration in `0.11.0`: a "Create an account" link on
the login form, one-time email confirmation with a hashed token, configurable
domains and registration role, an hourly limit, automatic account creation from
a verified Google email, new events and texts, a new `registrations` table
(schema version 10) and regression tests. All new settings are off by default,
so existing applications and databases keep their behaviour. Also fixed an
indentation typo in `_pkgdown.yml` and regenerated the favicons so the
documentation site builds cleanly.

# appauth 0.11.0

A feature release; the 0.10.1 submission to CRAN is left untouched. Existing
settings, function signatures and data are unchanged, and all new features must
be enabled explicitly.

* Added self-registration: `aa_register_user()`, `aa_confirm_registration()` and
  `aa_registration_token_login()`. A visitor submits a login, email and password;
  the account is created after following a one-time link from the email. The
  link can also be used through `?register=<token>` without a Shiny form. Only
  the password hash and the token hash are stored.
* New settings: `registration_enabled`, `registration_verify_email`,
  `registration_role`, `registration_domains`, `registration_max_per_hour`,
  `google_signup` and `google_signup_require_domains`. Registration cannot grant
  `admin_role`, requires password login and, with email confirmation, a
  `send_reset` function and `reset_base_url`.
* `google_signup = TRUE` creates an account on first sign-in with Google from
  the verified email and assigns `registration_role`; by default a non-empty
  `google_domains` list is required. The login is derived from the email and
  gets a numeric suffix if it is taken. Google-created accounts get a random
  password hash, so password sign-in is not possible until an administrator sets
  one.
* Schema migration 10 adds the `registrations` table; `aa_cleanup()` removes
  expired and used registrations. Creating a user with the same email consumes
  stale registration links.
* New events: `registration_requested`, `registration_confirmed`,
  `registration_failed` and `google_user_created`. `login_success` now also uses
  the value `registration`. New interface texts are available in English and
  Russian.
* Updated both bundled AI skills and regenerated their function references for
  0.11.0; empty example lines in generated reference files no longer contain
  trailing whitespace.
* Added Shiny `testServer` and snapshot coverage for the registration form,
  immediate registration, the generic confirmation response and the
  `?register=<token>` deep link.

# 2026-11-21 | OPENCODE (Alsey)
Aligned both bundled AI skills with the skill-creator rules: shortened the
frontmatter descriptions to the 1024-character limit while preserving the full
triggering rules in a new `When to activate (full rules)` section, and added a
generated table of contents to every API reference file, and marked those
generated files with `whitespace=cr-at-eol` in `.gitattributes`.

# 2026-11-20 | OPENCODE (Alsey)
Added the shared Google Analytics 4 tag `G-Z56YHE916N` to the pkgdown site so
`/appauth/` pages are tracked together with the main site.

# 2026-11-20 | GEMINI CLI (Alsey)
Updated the package hex logo: corrected letter casing to lowercase 'appauth',
redesigned the emblem with a modern 3D faceted cyber shield and metallic lock,
updated man/figures/logo.svg and man/figures/logo.png, regenerated pkgdown
favicons and added dev/create_logo.R. Switched pkgdown site theme to Bootswatch
Darkly with custom cyan and teal brand accents and arrow-dark syntax theme.

# 2026-11-19 | CLAUDE CODE (Alsey)
Implemented the remaining audit recommendations: transaction wrappers for
login protection and user management, atomic Google sign-in with
`must_change`, expanded tests and snapshots, generated a hex logo, configured
pkgdown at https://alexey-seleznev.pro/appauth/, and added CI package checks.

# appauth 0.10.1

A maintenance release with audit fixes and documentation improvements. The
database schema is unchanged.

* Login attempts, account protection, password changes and user management
  writes now run in database transactions; MySQL and PostgreSQL use lock
  primitives, and DuckDB uses a reentrant write section without savepoints.
* After a Google sign-in, a user with `must_change = 1` is asked for a new
  password before a session is created. The form does not ask for the old
  password because ownership was confirmed by Google.
* `aa_settings(reset_base_url = ...)` now rejects addresses that do not start
  with `https://`, so recovery tokens are not sent over an unencrypted link.
* Added regression tests, snapshots of user-facing errors, database backend
  test documentation and tests for the bundled skills.
* Regenerated AI skill references for 0.10.1 and added `aa_install_skills()`
  to the pkgdown reference index.
* Added a hex logo, configured the pkgdown site and enabled package checks in
  GitLab CI.

# appauth 0.10.0

A release that prepares the package for CRAN: everything is now in English. The database schema and the function signatures (except the new arguments below) do not change.

* **Breaking change: the default language is English.** `aa_texts()` now defaults to `lang = "en"`, so login forms, the users tab and messages are in English unless you ask otherwise. To keep the Russian interface, pass it explicitly: `aa_settings(texts = aa_texts("ru"))`. The set of text keys is the same for both languages.
* All documentation (help pages, vignettes, README, NEWS) is in English. Messages, warnings and errors raised by the package are in English too; error classes and event keys are unchanged. Messages that were matched by text in your tests or logs have new wording.
* `aa_events()` gained the `lang` argument (`"en"` by default, `"ru"` for Russian descriptions).
* The Russian texts are kept as ASCII Unicode escapes in `R/texts-ru.R` (CRAN does not allow non-ASCII characters in R code). The readable source is `dev/texts-ru-source.R`; regenerate the file with `dev/build-texts-ru.R`.
* `DESCRIPTION`: English title and description, `URL` and `BugReports` point to GitHub.
* The example apps, the end-to-end scripts in `dev/` and the bundled skills use the English texts.
* Internal mentions of the applications the package was first written for are removed from the documentation and comments.

# appauth 0.9.0

A release with a new feature: AI agent skills (Claude Code, Codex, Posit Assistant and others) are now bundled with the package. The behaviour of existing functions, the database schema and the settings do not change.

* Two skills, written in English, live in `inst/skills`: `appauth` (function reference, database schema, events, UI identifiers) and `appauth-secure-shiny` (adopting `appauth`, migrating hand-written authentication, Google sign-in, security audit, app templates, the `audit_shiny_app.R` and `scaffold_auth.R` scripts).
* The new function `aa_install_skills()` copies the skills from the installed package into the project's `.claude/skills` (`agent = "claude"`) or `.agents/skills` (`agent = "agents"`), or into the home directory when `global = TRUE`. Skills that are already installed are not overwritten unless `overwrite = TRUE`.
* The skills ship with the package version, so after updating the package it is enough to run `aa_install_skills(overwrite = TRUE)`.
* Automated tests: installation into the target directories, overwrite protection, argument checks.
* The app template of the `appauth-secure-shiny` skill now includes the 0.8.0 events (password reset, 2FA, Google sign-in): the template smoke test now passes completely (22 of 22).

# appauth 0.8.0

A release with a new feature: the package now works not only with SQLite but also with DuckDB, MySQL / MariaDB and PostgreSQL. SQLite remains the default database, its data format and schema do not change, so existing applications and databases keep working without any changes.

* Supported databases are detected from the DBI connection: `RSQLite` (SQLite), `duckdb`, `RMariaDB` (MySQL and MariaDB), `RPostgres` (PostgreSQL). The drivers are installed separately and are listed in `Suggests`. Other databases are rejected with a clear error of class `appauth_error_connection`. BigQuery is intentionally not supported: it has no unique constraints or atomic updates, on which one-time tokens (password reset, Google sign-in, 2FA backup codes) and the last-administrator protection rely.
* Database differences are collected in one place, `R/dialect.R`: dialect detection, column types, auto-increment, index creation, insert-if-missing and locking during migrations. The rest of the code uses plain SQL.
* Time is now computed by R and passed as a parameter (a UTC string `YYYY-MM-DD HH:MM:SS`, the same format SQLite stored), so queries no longer contain `datetime('now')` and the like. A side benefit: token lifetimes do not depend on the clock or time zone of the database server. Time is stored as text in all databases, so date comparison works the same everywhere.
* Query placeholders are adapted to the database (`$1, $2` for PostgreSQL), and `integer64` numbers from `COUNT(*)` are converted to regular integers.
* Schema: new SQLite databases are created as before (the same table names, column names and migration numbers). In MySQL, the login, role and hash columns are created with a binary collation that does not ignore trailing spaces (`utf8mb4_0900_bin`, `utf8mb4_nopad_bin` in MariaDB), so `Alsey` and `alsey` remain different logins, as in SQLite. Email uniqueness in all databases is enforced by a regular unique index (several `NULL` values are allowed). In DuckDB the `users` table is created with all columns at once: this database does not allow altering a table that already has an index.
* Migrations in MySQL and PostgreSQL run under a lock (`GET_LOCK`, `pg_advisory_xact_lock`): starting several application instances at the same time is safe. In MySQL DDL cannot be rolled back, so if a migration is interrupted, a rerun completes whatever is missing (migrations are idempotent, as before).
* `aa_session_connection()` gained the `connect` argument: a function without arguments that opens a connection to any supported database (`db_path` is not needed for it). The connection is closed together with the Shiny session.
* The `aa_query()` and `aa_execute()` wrappers and the `aa_check_conn()` check (instead of `aa_check_sqlite()`) are internal. Public functions accept a connection to any supported database. Migrating plain-text passwords to hashes with `aa_migrate_plain_passwords()` works on a file and remains SQLite-only.
* Miscellaneous: the "by date added" ordering of users is taken from `id` (or from `rowid` in SQLite, or from the login if there is no `id`); the failure time used for locking is computed in R.
* Database verification: the full test suite passed on SQLite, DuckDB 2.0, MySQL 8.0 and PostgreSQL 16.4 (it was not run on MariaDB). To run on a particular database: `Rscript dev/run-tests-db.R sqlite|duckdb|mysql|postgres`.
* Automated tests: the whole suite can be run on any supported database (`Rscript dev/run-tests-db.R sqlite|duckdb|mysql|postgres`). Tests of legacy schemas and the file-based password migration run on SQLite only.

# appauth 0.7.1

A small fix for Google sign-in. The database schema and settings do not change, existing applications keep working without any changes.

* Google sign-in now also works from a page on a different address than `google_redirect_uri`. Previously, when the application was opened by IP address (while the redirect was configured for a domain), sign-in ended with a `bad_browser` rejection: `state` is stored in a cookie of the site address, and cookies for the IP and for the domain are different. Now the "Sign in with Google" button on such an address redirects to the redirect address, and sign-in starts there automatically (the `?google=1` parameter, without a second click). Redirecting is only allowed to Google and to the address from `google_redirect_uri`. Password sign-in and cookie auto-login work independently on each address, as before.
* Automated tests: address parsing and comparison, redirecting from another address, auto-start on `?google=1` without an endless redirect, normal start on the redirect address.

# appauth 0.7.0

A release with a new feature: Google sign-in (OpenID Connect) and the ability to disable password sign-in. Off by default (`google_enabled = FALSE`, `password_login = TRUE`), so applications that do not enable it behave as before. Existing databases are upgraded by migration 9 at startup (`aa_init_db()` or `aa_prepare_db()`), data is not changed. New dependencies: `httr2`, `jose` and `jsonlite`.

* Google sign-in (authorization code flow with PKCE). `aa_settings()` options: `google_enabled`, `google_client_id`, `google_client_secret`, `google_redirect_uri`, `google_domains`; all of them are also read from the `security` section of the config. Enabling without a client ID, secret or redirect address fails immediately, and the secret does not appear in the `print()` output of the settings. A "Sign in with Google" button appears on the login form (alongside the password form or instead of it).
* Who can sign in. Only a user who already exists in the database and whose email equals the address of the Google account: sign-in never creates new users, the role is taken from the database, and a blocked user cannot sign in. The list of allowed organization domains `google_domains` is checked against the signed token (the `hd` field with the primary domain of the Workspace organization, and the email domain must also be in the list: if the organization has secondary domains, list both the primary and the secondary ones); an empty list disables the domain check, and then the email match decides. The application's two-factor code is not requested for Google sign-in (Google performs the verification).
* Security rules. `state`, `nonce` and the PKCE verifier are one-time and live for 10 minutes (in the database `state` is stored only as sha256). The `state` from the address is compared with a short-lived cookie of the browser that started the sign-in: someone else's return link cannot be slipped into a different browser. The client secret never leaves the server. The Google token is verified in full: signature against Google's keys (RS256 only, keys are cached for an hour), issuer, audience (with `azp` when there are several), expiry, `nonce`, verified email and domain. Token parsing does not use partial matching of field names. A global limit on sign-in starts per minute protects the table from being flooded. The user is shown a generic message on any rejection; the reason (and the email) goes only into the event.
* Disabling the password: `password_login = FALSE` hides the password form and "Forgot password?", and password sign-in attempts and reset links are rejected on the server, not only in the interface. The password can only be disabled together with `google_enabled = TRUE`: otherwise `aa_settings()` raises an error. Creating the first administrator on an empty database remains available.
* Migration 9 adds the `oauth_states` table (Google sign-in parameters). `aa_cleanup()` deletes old records and returns a fourth field, `oauth_states`.
* The `aa_events()` catalogue gained the `google_login_failed` event (reason and email in `value`), `login_success` now has the value `google`, and `login_failed` has the value `password_disabled` (29 events). New interface texts in Russian and English (keys `google_*` and `password_login_disabled`).
* Fixed the login form layout: input fields were narrower than the buttons and pushed to the left (Shiny sets them to 300 px while the card is wider); now fields and buttons have the same width.
* Documentation: description of the flow, threat model and limitations in `architecture-and-security`, a recipe and OAuth client setup in `extension-points`, README.
* Automated tests: 2329 checks (new file `test-google.R`: settings, token signature and content, algorithm substitution, foreign key, domains, one-time `state`, browser check, no automatic user creation, the login module; schema tests updated for version 9). Key parsing was verified against real Google public keys.

# appauth 0.6.0

A release with small conveniences for administrators and users. The database schema does not change, there are no migrations, existing applications keep working without any changes.

* Copy buttons in the two-factor authentication module: a "Copy" button appeared next to the manual-entry key and under the backup codes. The key is copied without spaces, backup codes one per line. Over HTTPS the browser clipboard is used, otherwise (and inside Bootstrap modals) copying goes through a hidden field. The button copies what is already visible on the page, so it reveals nothing new. The button text and the "Copied" confirmation are set by the keys `copy_button` and `copy_done`.
* The users table in `aa_users_server()` gained the columns "Email" (a checkmark if an address is set for password recovery; the address itself does not appear in the table), "2FA" (a checkmark if protection is enabled; the column is shown only when `totp_enabled = TRUE` in the settings) and "Auto-logins" (the number of active auto-login tokens: sign-in is remembered on that many devices). Text keys `col_email`, `col_totp`, `col_autologins`; the hint under the table was extended with an explanation of auto-logins.
* New function `aa_active_autologins(conn, login = NULL)`: the number of active (not revoked and not expired) auto-login tokens of a user, or a table for all users. If the token table does not exist, zero is returned.
* `aa_users_overview()` returns three new columns: `has_email`, `totp_on` and `autologins`. Columns are only added, the previous ones stay in place and keep their values. For an old schema without `email` and `totp_enabled` the flags are zero.
* Automated tests: auto-login counting (revoked and expired are not counted, login case, missing table), the new overview and table columns (including the old schema and disabled 2FA), copy buttons for the key and backup codes, texts in both languages.

# appauth 0.5.0

A release with a new feature: two-factor authentication (TOTP). Off by default (`totp_enabled = FALSE`) and voluntary, so applications that do not enable it behave as before. Existing databases are upgraded by migration 8 at startup (`aa_init_db()` or `aa_prepare_db()`), data is not changed, and protection is off for existing users.

* Two-factor authentication with one-time TOTP codes (RFC 6238, HMAC-SHA1, 6 digits, 30-second step): the user enables it in the profile block, and after a correct password enters a code from an authenticator app or a backup code. The algorithm is implemented in the package with no new dependencies and verified against the reference vectors of RFC 4226 and 6238.
* `aa_settings()` options: `totp_enabled`, `totp_key` (the secret encryption key, a string of at least 16 characters, to be stored outside the database), `totp_issuer` (the name shown in the authenticator app) and `totp_window` (allowed clock drift in steps, 1 by default). Enabling without a key fails immediately, and the key does not appear in the `print()` output of the settings.
* Migration 8 adds the columns `totp_secret` (the secret in encrypted form), `totp_enabled` and `totp_last_step` to `users`, and the `totp_recovery` table (only the sha256 of backup codes is stored in the database).
* New functions: `aa_totp_setup()`, `aa_totp_enable()`, `aa_totp_disable()`, `aa_totp_enabled()`, `aa_verify_second_factor()`, `aa_recovery_codes_left()`, `aa_totp_secret()`, `aa_totp_uri()` and `aa_totp_code()`. The `aa_totp_ui()` and `aa_totp_server()` module: enabling (QR code, manual-entry key, 10 backup codes shown once) and disabling (password and code required). The QR code is built by the optional `qrcode` package (in Suggests); without it only the manual-entry key is shown.
* Security rules. The secret is encrypted (sodium) with the `totp_key` key, so the database alone is not enough to produce codes. A code is accepted only once: the accepted time step is remembered by an atomic query. Backup codes are single-use. A wrong code counts as a failed sign-in attempt, and the login is locked under the same rules as for password guessing; a successful attempt is recorded only after a correct code, so a correct password does not reset the counter. No auto-login token is issued before the code is verified. Password recovery by email does not bypass 2FA. When 2FA is enabled, the user's other sessions are terminated. When disabling, the code is checked only if the password is correct, so a foreign attempt does not consume backup codes.
* `aa_auth_server()`: after a correct password a code form is shown (order: password, code, mandatory password change, sign-in). Sign-in via the auto-login cookie does not ask for a code.
* `aa_users_server()`: the user card shows the 2FA status and a "Reset 2FA" button for the case of a lost phone (the secret and backup codes are erased, the user's sessions are terminated, event `totp_reset`). Deleting a user deletes their backup codes.
* The `aa_events()` catalogue gained the events `totp_enabled`, `totp_disabled`, `totp_failed`, `totp_reset` and `recovery_code_used` (28 events). New interface texts in Russian and English (keys `totp_*`, `card_totp`, `done_totp_*`).
* The `custom-permissions-app` example demonstrates 2FA on the Profile tab.
* Documentation: description of the flow, threat model, decisions and limitations in `architecture-and-security`, a recipe and parameters in `extension-points`, the key and server time in `deployment`, a step for existing applications in `integrating-existing-app`, README.
* Automated tests: 398 tests, 2092 checks (new file `test-totp.R`, schema tests updated for version 8); browser verification passed: enabling with a QR code and backup codes, sign-in with a code, reuse of a code and a backup code, lockout on guessing, reset by an administrator.

# appauth 0.4.0

A release with a new feature: password recovery by email. Off by default (`reset_enabled = FALSE`), so applications that do not enable it behave as before. Existing databases are upgraded by migration 7 at startup (`aa_init_db()` or `aa_prepare_db()`), data is not changed.

* Password recovery by email. `aa_settings()` options: `reset_enabled`, `send_reset` (a function `function(email, link, login)` that sends the email, for example via `emayili`), `reset_base_url` (the application address, to which `?reset=<token>` is appended), `reset_ttl_minutes` (60), `reset_max_per_hour` (3) and `reset_max_per_minute` (10); all of them are also read from the `security` section of the config. Enabling without `send_reset` or `reset_base_url` fails immediately.
* Migration 7 adds the `users.email` column (nullable, empty for existing users; the address is stored in lower case, uniqueness applies only to addresses that are set) and the `password_resets` table (only the sha256 of the token, the expiry and a used flag are stored in the database).
* New functions: `aa_set_email()`, `aa_get_email()`, `aa_request_password_reset()`, `aa_reset_token_login()` and `aa_reset_password_with_token()`. `aa_create_user()` gained the `email` argument.
* Security rules. The form response is always the same, whether the user is found, has an address or is blocked; the reason goes only into the event. The token is 256 bits and single-use, a new request invalidates earlier links, a weak password does not consume the token, and of two simultaneous requests only one succeeds. Limits on emails per user per hour and a global limit per minute. After a password change via a link, all auto-login tokens are revoked, the other links are invalidated, and the attempt lockout and the mandatory-change flag are cleared. No email is sent to a blocked user, and a blocked user's link does not work. A password reset by an administrator, a password change and user deletion invalidate unused links.
* The `aa_auth_server()` module: a "Forgot password?" link on the login form, a link request form, reading the `reset` parameter from the address bar (the parameter is removed from the address immediately) and a new-password form. After the password change the user signs in the usual way. The `aa_users_server()` module: an email field in the user card and in the add dialog.
* `aa_cleanup()` deletes used and expired recovery links older than a day and returns a third field, `password_resets`.
* The `aa_events()` catalogue gained the events `password_reset_requested`, `password_reset_done`, `password_reset_failed` and `email_changed` (23 events). New interface texts in Russian and English (keys `forgot_*`, `reset_*` and `email_*`).
* The `custom-permissions-app` example demonstrates password recovery: the example writes the link to the console.
* Documentation: description of the flow, threat model and limitations in `architecture-and-security`, a recipe for sending via `emayili` and parameters in `extension-points`, a section on `reset_base_url` and nginx logs in `deployment`, a step for existing applications in `integrating-existing-app`, README.
* Automated tests were extended with the file `test-password-reset.R`; existing schema tests were updated for version 7.

# appauth 0.3.0

A release with new features. Existing databases are upgraded by a migration at startup (`aa_init_db()` or `aa_prepare_db()`), data is not changed. Applications that call `aa_users_server()` get a delete confirmation and two new table columns; the default settings leave the rest of the behaviour unchanged.

* Creation and last-login dates. Migration 6 adds the columns `created_at` and `last_login_at` to `users` (nullable, empty for existing users: SQLite does not allow the `CURRENT_TIMESTAMP` default when adding a column). `aa_create_user()` and `aa_create_first_admin()` record `created_at`, and the login module records `last_login_at` on a successful password sign-in (including after a mandatory password change and when creating the first administrator); signing in via the auto-login cookie does not update the date. `aa_get_user()` and `aa_list_users()` return both columns (UTC dates as text `YYYY-MM-DD HH:MM:SS`), and `aa_users_overview()` adds columns for display, `created` and `last_login` (server local time, with "unknown" and "never signed in" texts for unknown dates). The users table in `aa_users_ui()` shows the "Created" and "Last login" columns. New texts `col_created`, `col_last_login`, `date_unknown`, `date_never`.
* Weak password policy: the `password_policy` option in `aa_settings()` (and in the `security` section of the config). A password is considered weak if it is in the `aa_common_passwords()` list, equals the login case-insensitively, or consists of a single repeated character. Modes: `"off"` do not check, `"warn"` (default) accept the password and show a warning, `"reject"` reject the password with an `appauth_error_user` error and the reason `password_common`, `password_equals_login` or `password_repeated`. In `"warn"` mode the modules show a notification after adding a user, resetting and changing a password, creating the first administrator and the mandatory password change, and emit the new event `weak_password_set` (value: "login: reason"). For applications with their own interface: `aa_weak_password_warning()`, and `aa_validate_password()` gained an optional `login` argument. Existing passwords are not affected. New texts `password_common`, `password_equals_login`, `password_repeated`, `weak_password_notice`.
* `aa_event_logger()`: a ready-made event handler for `on_event`. The application supplies only the writer function `writer(action, user, session_id, value)`; the package takes care of event selection (`events`, `actions`), renaming to log action names (`actions`), switching logging on and off per event (`enabled`, the function is called on every event, so config changes take effect immediately) and value conversion (`format_value`). Typos in event names are caught immediately, and a writer failure does not interrupt the package action.
* Deleting a user in `aa_users_server()` requires confirmation: the "Delete account" button opens a dialog with "Yes, delete" and "Cancel" buttons. The server deletes only the user for whom the dialog is shown, and only after the confirm button is pressed; a forged or repeated confirmation deletes nothing. New texts `delete_confirm_title`, `delete_confirm_text`, `delete_confirm_button`, `button_cancel`. Identifiers for tests: `delete_cancel`, `delete_confirm` (the ID `delete` now only opens the dialog).
* The `aa_events()` catalogue gained the `weak_password_set` event (19 events).
* Automated tests: 334 tests, 1598 checks; browser verification (`dev/e2e`) was extended with date columns, the weak password warning and delete confirmation.

# appauth 0.2.1

* Fixed the help pages: the return value of `aa_get_user()` is described without `must_change` and without mention of a password (the function has no password), and `aa_authenticate()` has the `must_change` column added.
* Vignettes `integrating-existing-app` and `testing-your-app`: described Shiny autoloading (`R/*.R` is sourced before `app.R`, so a file in `R/` that calls a package function at the top level must call `library(appauth)` itself), and a tip about the `--no-init-file --no-site-file` options for `Rscript`.

# appauth 0.2.0

* `aa_auth_server()` returns a `logout_all(reload = TRUE)` function: "sign out on all devices" revokes all of the user's tokens, emits the `sessions_revoked` event and signs out immediately; open sessions on other devices are closed by `aa_session_guard()`. The application must ask for confirmation before calling it.
* The `minimal-app` example shows buttons next to the user badge: changing one's own password in a dialog (the dialog closes on success), sign-out, and sign-out on all devices with confirmation; browser verification and automated tests were extended.
* Documentation: a "Personal account" recipe in the `extension-points` vignette, a lesson about the `app.R` environment when launching via `runApp()` in the `integrating-existing-app` and `testing-your-app` vignettes (create the settings needed by functions from `R/` globally; load application tests into a separate environment).

# appauth 0.1.0

* First release: passwords, sign-in protection, sessions, permissions, events, sign-in, user and password change modules, SQLite schema migrations, documentation and two example applications. Details below.
* `RSQLite` moved from Suggests to Imports: the package works only with SQLite, and the driver is now installed together with it.
* Package skeleton: folder structure, `DESCRIPTION`, license, and a `.gitlab-ci.yml` that installs into a shared library and sends notifications.
* Added the `architecture-and-security` vignette: threat model, system composition and data, flows (sign-in, first start, auto-login, sign-out, permission check, user management, application start), guarantees, decisions taken and their reasons, known limitations, application responsibilities, lessons from bugs found.
* Added settings and texts:
    * `aa_settings()` - authentication settings (brute-force protection, password rules, auto-login, data retention periods, roles), with sensible defaults;
    * `aa_settings_from_list()` - settings from a list, for example from a `config.yaml` section;
    * `aa_texts()` - interface and message texts in Russian and English with the ability to override any string, `aa_text()` - get a text by key with value substitution, `aa_text_keys()` - the list of keys.
* Added the SQLite database schema with versioned migrations:
    * `aa_init_db()` - create or complete the tables `users`, `auth_sessions`, `login_attempts` and the service table `appauth_migrations`; existing data is not changed, a repeated run changes nothing, and legacy schemas are recognized (including a `users` table without `id` and without `blocked`, and plain-text passwords);
    * `aa_schema_version()` - the schema version;
    * `aa_cleanup()` - delete stale sign-in attempts and tokens;
    * `aa_prepare_db()` - database preparation at application start that does not stop the application on error.
* Added password handling:
    * `aa_hash_password()` - a scrypt hash (package `sodium`) for storage in the database, `aa_verify_password()` - verify a password against a hash (plain-text passwords, corrupted hashes and the hash itself used as a password never pass the check, and the function does not raise errors), `aa_is_password_hash()` - distinguish a hash from a plain-text password;
    * `aa_validate_password()` and `aa_validate_login()` - validate a new password and login against the rules from `aa_settings()` (length is counted in characters), error texts in the language of the settings;
    * `aa_migrate_plaintext_passwords()` - a one-off migration of passwords from plain text to hashes with a backup, a transaction, verification of every hash against the original password and a `dry_run` mode; a repeated run is safe;
    * `aa_check_default_accounts()` and `aa_common_passwords()` - find accounts with a plain-text password, a password equal to the login, or a common weak password.
* Added user handling:
    * reading: `aa_get_user()`, `aa_list_users()` (password hashes are not returned), `aa_users_exist()`;
    * creation: `aa_validate_new_user()` (validation without creating, to show an error in a form), `aa_create_user()`, `aa_create_first_admin()` (creates an administrator with a single SQL query and only on an empty table; of two simultaneous requests only one succeeds);
    * sign-in: `aa_authenticate()` (a parameterized query, the login is compared exactly, case-sensitively, a dummy hash check for a non-existent login evens out the response time, plain-text passwords and a hash used as a password are not accepted);
    * actions: `aa_set_password()` (revokes the user's tokens), `aa_set_role()`, `aa_set_blocked()` (blocking revokes tokens), `aa_delete_user()` (deletes tokens and failed sign-in attempts so that a new owner of the same login does not get access through someone else's cookie);
    * permissibility checks for the interface: `aa_check_can_block()`, `aa_check_can_delete()`, `aa_check_can_change_role()` return the reason text or `NULL`.
    * When rules are violated, action functions abort with an error of class `appauth_error_user` with a text in the language of the settings, and the reason key in the `reason` field.
* User rules: you cannot block or delete yourself, you cannot be left without an active (not blocked) administrator by blocking, deleting or changing a role (the role-change rule is an addition), the login of a new user cannot match an existing one even up to letter case (including Cyrillic), existing login pairs such as `alice` and `Alice` are preserved and work as different users, and a login cannot start or end with a space.
* Schema compatibility was verified on copies of production-like databases: the data of all tables is not changed, only the service table `appauth_migrations` is added.
* Added sign-in brute-force protection:
    * `aa_record_attempt()` - record a sign-in attempt (a successful attempt resets the failure counter of that login);
    * `aa_login_lock_remaining()` - how many seconds the login lock still lasts after a series of failures;
    * `aa_global_throttled()` - the global limit of failures per minute across the whole application;
    * `aa_clear_attempts()` - clear the attempt lockout;
    * `aa_login_gate()` - a single check before sign-in: whether a password may be tried, the reason for refusal and a ready-made text (on a database failure the locks are not applied, and password verification is unaffected);
    * `aa_users_overview()` - a users table with the state `ok`, `blocked` (manually) or `locked` (by attempts) and a ready status for the interface.
* Added sessions and auto-login tokens:
    * `aa_issue_token()` - issue a token (32 random bytes, only sha256 in the database, lifetime `session_days`); it is not issued when auto-login is disabled, nor for a non-existent or blocked user;
    * `aa_find_session_user()` - the user by the token from the cookie (the token must not be revoked or expired, the user must not be blocked, and the role is taken from the database);
    * `aa_revoke_token()` - revoke a token on sign-out;
    * `aa_user_session_valid()` - periodic check of an already open session: blocking, deletion and a ROLE CHANGE invalidate it immediately, not at the next sign-in (on a database failure the session is kept, `reason = "check_failed"`);
    * the storage format is compatible with the previous implementation: tokens that were already issued keep working.
* Added permissions:
    * `aa_permissions_from_matrix()` - a permission source from a "permission -> roles" matrix (roles as a vector or a single string); the matrix can be passed as a function, in which case it is read on every check (a permissions editor without a restart); the administrator role does not get permissions by itself;
    * `aa_can()` - a server-side permission check, closed by default: no user, a non-string permission, a failed permission source or one that returned garbage gives `FALSE`; the permission source can be any function `function(user)` (permissions from the database, by groups);
    * `aa_require()` - the first line of a handler: without the permission, an `access_denied` event goes to the `on_event` hook, the user gets a notification, and the handler is quietly aborted; a broken hook does not cancel the refusal.
* Added authorization events: `aa_events()` - a catalogue of 16 events (sign-in, blocks, sign-out, forced session termination, user actions, access denied) with a description and the content of the `value` field. The package reports them to a single hook `on_event(event, user, session_id, value)` and writes nothing to the application logs by itself; an error in the hook does not interrupt the action; passwords and tokens never reach events. A test ensures that every event emitted by the package code is described in the catalogue.
* Added the sign-in interface:
    * `aa_app_head()` - includes the package CSS and JS (form and users table styles on `--aa-*` variables, a light theme via the `aa-theme-light` class, the auto-login cookie with `SameSite=Lax` and `Secure` on HTTPS, a configurable cookie name so that applications on the same host do not conflict);
    * `aa_auth_ui()` and `aa_auth_server()` - the sign-in module: a sign-in form, or a first-administrator creation form on an empty database, brute-force protection via `aa_login_gate()`, the administrator-block message shown only when the password is correct, cookie auto-login, sign-out and forced sign-out; it returns `user`, `logged_in`, `role` and `logout()`; it reports all events to the `on_event` hook.
* Added the users module `aa_users_ui()` and `aa_users_server()`: a table with statuses (highlighting of blocked and temporarily blocked rows), a card opened by double-click, adding via a dialog, role change, password reset, blocking and unblocking, clearing the sign-in lock, deletion. Only an administrator can manage; the role is checked against the database on every action; the target of an action is taken from the state of the open card, not from the browser; the rules (self, last administrator) are checked on the server. Card extension slots: `extra_card_ui(login, ns)` and `extra_card_server(input, output, session, login)`. Keys for the users tab were added to the texts (ru and en).
* The modules were verified in a real browser (Chrome and Playwright, scenarios in `dev/e2e`): sign-in, error messages, attempt lockout, cookie auto-login and sign-out, the user card, highlighting of blocked and temporarily blocked rows, light and dark themes, adding a user; as a result the following was fixed: the login form takes the whole screen, the error message is styled, a false `access_denied` event is no longer written on sign-out, and a non-administrator role is offered by default for a new user.
* Added integration helpers:
    * `aa_session_connection()` - a SQLite connection that is closed together with the Shiny session (otherwise the connection holds the database file, and on Windows it cannot be renamed or deleted), with optional schema preparation;
    * `aa_session_guard()` - every `session_check_seconds` checks the open session and terminates it if the user was blocked, deleted or had the role changed (the `session_forced_logout` event with a reason, tokens are revoked, and on a database failure the session is kept);
    * `aa_register_module()` - attaches a module's server part once per session when the signed-in user gets the required permission.
    * A separate `aa_logout()` function is not needed: sign-out is `auth$logout()` from `aa_auth_server()`.
* Browser verification (`dev/e2e`) was extended: an administrator-blocked user and a user whose role was changed with an open session end up on the login form within the check interval, and after signing in again the role is the new one (33 checks).
* Automated tests were extended: the content of the user card (buttons by user state, reasons for unavailability, the slot, English language, custom texts, escaping of a login containing HTML), non-default settings (custom roles and a custom administrator role in functions and modules), security regression checks for the modules (SQL injection, huge login and password, a hash used as a password), a check that every catalogue event is actually emitted by the package code; shared module test helpers were moved to `helper-modules.R`.
* Added changing one's own password and mandatory password change:
    * schema migration 5: the `users.must_change` column;
    * `aa_change_own_password()` - change one's own password with confirmation of the current one (tokens of other sessions are revoked, the current one stays, the change requirement is cleared);
    * `aa_set_password(must_change =, keep_token =)` and `aa_create_user(must_change =)` - a password set by an administrator can be made temporary; `aa_authenticate()` now also returns the `must_change` column;
    * the sign-in module shows a password change form after a correct temporary password and does not let the user into the application until the change; the cookie token does not work for such users;
    * `aa_password_ui()` and `aa_password_server()` - the module for changing one's own password (the `password_changed` event);
    * users module: a "require password change" checkbox when adding and resetting (on by default), and a "Terminate all sessions" button (`aa_revoke_sessions()`, the `sessions_revoked` event);
    * `aa_session_guard()` also checks the session token (`aa_user_session_valid(token =)`, reason `token_revoked`), so a password reset and "terminate all sessions" end open sessions; every `cleanup_minutes` (60) the guard cleans stale sign-in attempts and tokens; `aa_auth_server()` also returns a `token()` function.
    * the `must_change_default` option in `aa_settings()` sets the value of the "require password change" checkbox in the add dialog and on password reset (`TRUE` by default, the administrator clears it if a change is not needed; with `FALSE` the administrator ticks the checkbox);
    * On the login form, Enter in a field presses the button.
    * Browser verification was extended (38 checks): sign-in with Enter, changing one's own password, terminating all sessions, mandatory password change.
* Added two example applications (`inst/examples`, described in `inst/examples/README.md`):
    * `minimal-app` - a "permission -> roles" matrix from `config.yaml`, a Russian interface, tabs by permission, handler protection, a users tab, password change, an events hook;
    * `custom-permissions-app` - a different model: custom roles (`owner`, `editor`, `viewer`), per-user permissions from a database table, a slot in the user card for granting permissions, an English interface, `must_change_default = FALSE`, a custom cookie name; it proves that the core is not tied to any particular schema.
    * Both applications are run in full in the automated tests (`test-example-apps.R`) and verified in a browser (`dev/e2e/run_examples.ps1`, 12 checks).
    * Added an end-to-end test on an application schema with plain-text passwords and a `root`/`root` row (legacy schema, password migration, sign-in with English texts).
* Documentation:
    * `README.md` was rewritten: what and why, features, quick start, function table, documentation list, limitations;
    * new vignettes: `getting-started` (quick start, basic concepts, working without Shiny), `integrating-existing-app` (converting an existing application, migrating plain-text passwords, mapping of old functions to new ones, behaviour differences, rollback), `extension-points` (permissions, roles, events, card slots, texts, styling, parameters), `testing-your-app` (techniques and a checklist for security tests), `deployment` (HTTPS and nginx, brute-force protection behind a proxy, first start, secrets, backups, updates, database file locking on Windows, Linux and Docker);
    * in the `architecture-and-security` vignette the limitations and the cookie description were updated (`SameSite=Lax`, `Secure` on HTTPS);
    * all vignette examples are executed during the build, and `devtools::check()` is clean.
* The failure counter is kept per exact login, case-sensitively (`alice` and `Alice` are different people), and not per IP: behind nginx it is not visible.
* Sign-in protection compatibility was verified on copies of production-like databases (51 users): the originals were not changed, and the `alice`/`Alice` pair is locked independently.
* Added automated tests (`tests/testthat`): settings, texts, schema and migrations, including fixtures of legacy schemas, passwords, users, sign-in protection.
