# appauth database schema

Package version: 0.10.1, schema version: 9. The description was produced from a real SQLite database after `aa_init_db()`; other databases have the same tables and columns, the types are shown in the "Types per database" section.

The package owns seven tables. It does not touch the other tables of the application.

## users

| Column | Type | Required | Default | Key |
| --- | --- | --- | --- | --- |
| `id` | INTEGER | no |  | PK |
| `login` | TEXT | yes |  |  |
| `password` | TEXT | yes |  |  |
| `role` | TEXT | yes |  |  |
| `blocked` | INTEGER | yes | `0` |  |
| `must_change` | INTEGER | yes | `0` |  |
| `created_at` | TEXT | no |  |  |
| `last_login_at` | TEXT | no |  |  |
| `email` | TEXT | no |  |  |
| `totp_secret` | TEXT | no |  |  |
| `totp_enabled` | INTEGER | yes | `0` |  |
| `totp_last_step` | INTEGER | yes | `0` |  |

* `password` holds a scrypt hash (`$7$...`); a plaintext password will not let the user sign in.
* `blocked` is 1 if the user is blocked by an administrator.
* `must_change` is 1 if the password is temporary (set by an administrator) and the user must change it on sign-in.
* `created_at` is the user creation time (UTC, text `YYYY-MM-DD HH:MM:SS`), set by `aa_create_user()`/`aa_create_first_admin()`; it is empty for users created before version 0.3.0 (SQLite does not allow `DEFAULT CURRENT_TIMESTAMP` with `ALTER TABLE`).
* `last_login_at` is the time of the last successful password sign-in (UTC), written by the `aa_auth_server()` module; sign-in by the auto-login cookie does not update it; it is empty for users who never signed in. The columns are returned by `aa_get_user()`, `aa_list_users()`, `aa_users_overview()`.

* `email` is the address for password recovery (since version 0.4.0), stored in lower case, empty for existing users; the unique index `idx_users_email` applies only to addresses that are set. Set by `aa_set_email()`, read by `aa_get_email()`; the column is not in `aa_get_user()` and `aa_list_users()`.

* `totp_secret` is the TOTP secret (since version 0.5.0) **in encrypted form** (sodium, the `totp_key` key from the settings): hex of the nonce and the ciphertext. Without the key the secret cannot be read. Empty until the user starts enabling 2FA, or after it is disabled.
* `totp_enabled` is 1 if the user confirmed a code and 2FA is on. A secret without `totp_enabled = 1` means "setup started, not finished".
* `totp_last_step` is the last accepted time step (seconds / 30): the same code and earlier steps are no longer accepted.

## auth_sessions

| Column | Type | Required | Default | Key |
| --- | --- | --- | --- | --- |
| `id` | INTEGER | no |  | PK |
| `user_login` | TEXT | yes |  |  |
| `token_hash` | TEXT | yes |  |  |
| `created_at` | DATETIME | no | `CURRENT_TIMESTAMP` |  |
| `expires_at` | DATETIME | yes |  |  |
| `revoked` | INTEGER | no | `0` |  |

* `token_hash` is the sha256 of the token as text (64 characters); the token itself exists only in the browser cookie.
* The token is valid while `revoked = 0`, `expires_at` has not passed, and the user exists and is not blocked.

## login_attempts

| Column | Type | Required | Default | Key |
| --- | --- | --- | --- | --- |
| `id` | INTEGER | no |  | PK |
| `login` | TEXT | yes |  |  |
| `success` | INTEGER | yes |  |  |
| `attempted_at` | TEXT | yes | now (UTC) |  |

* `login` is the exact entered login (case is preserved, length is truncated to `login_max`).
* `attempted_at` is in UTC, text `YYYY-MM-DD HH:MM:SS`; the write time and window boundaries are computed by R, and the comparison is done as strings.

## password_resets

| Column | Type | Required | Default | Key |
| --- | --- | --- | --- | --- |
| `id` | INTEGER | no |  | PK |
| `user_login` | TEXT | yes |  |  |
| `token_hash` | TEXT | yes |  |  |
| `created_at` | TEXT | yes | now (UTC) |  |
| `expires_at` | TEXT | yes |  |  |
| `used` | INTEGER | yes | `0` |  |

* `token_hash` is the sha256 of the token from the email (the token is 32 bytes, 64 hex characters in the email); the token itself is not stored in the database.
* The link is valid while `used = 0` and `expires_at` (`reset_ttl_minutes`) has not passed, and the user exists and is not blocked. A new request, a password change and an administrator reset set `used = 1` for the user's other links; deleting a user deletes their links; `aa_cleanup()` deletes used and expired links older than a day.

## totp_recovery

| Column | Type | Required | Default | Key |
| --- | --- | --- | --- | --- |
| `id` | INTEGER | no |  | PK |
| `user_login` | TEXT | yes |  |  |
| `code_hash` | TEXT | yes |  |  |
| `used` | INTEGER | yes | `0` |  |
| `created_at` | TEXT | yes | now (UTC) |  |

* `code_hash` is the sha256 of a backup code (10 hex characters without a hyphen, lower case); the codes themselves are shown once when 2FA is enabled.
* A new set replaces the previous one; disabling 2FA, an administrator reset and deleting the user delete the codes.

## oauth_states

Google sign-in parameters (since version 0.7.0). A record is created when the "Sign in with Google" button is pressed and is used once.

| Column | Type | Required | Default | Key |
| --- | --- | --- | --- | --- |
| `id` | INTEGER | no |  | PK |
| `state_hash` | TEXT | yes |  | UNIQUE index |
| `nonce` | TEXT | yes |  |  |
| `code_verifier` | TEXT | yes |  |  |
| `created_at` | TEXT | yes | now (UTC) |  |
| `expires_at` | TEXT | yes |  |  |
| `used` | INTEGER | yes | `0` |  |

* `state_hash` is the sha256 of the `state` value (the `state` itself is only in a short-lived browser cookie and in the return URL); `nonce` and `code_verifier` (PKCE) are needed when verifying the token and exchanging the code.
* A record lives for 10 minutes and is consumed by an atomic query (`used = 1`); the `state` is not accepted a second time. `aa_cleanup()` deletes records expired for more than a day. The overall limit on sign-in starts is 60 per minute.

## appauth_migrations

| Column | Type | Required | Default | Key |
| --- | --- | --- | --- | --- |
| `version` | INTEGER | no |  | PK |
| `name` | TEXT | yes |  |  |
| `applied_at` | TEXT | yes | now (UTC) |  |

## Types per database

Table names, column names and migration numbers are the same in all databases. The "Default" column above is shown for SQLite: the package always writes the time itself, so the default value is only a fallback for manual inserts.

| Columns | SQLite | MySQL / MariaDB | PostgreSQL | DuckDB |
| --- | --- | --- | --- | --- |
| `id` | `INTEGER PRIMARY KEY AUTOINCREMENT` | `INT AUTO_INCREMENT PRIMARY KEY` | `INTEGER GENERATED BY DEFAULT AS IDENTITY` | `INTEGER PRIMARY KEY DEFAULT nextval('aa_seq_<table>')` |
| login, role, hashes, `email` | `TEXT` | `VARCHAR(255)`, collation `utf8mb4_0900_bin` (MariaDB `utf8mb4_nopad_bin`) | `VARCHAR(255)` | `VARCHAR(255)` |
| time (`*_at`) | `TEXT` | `VARCHAR(19)` | `VARCHAR(19)` | `VARCHAR(19)` |
| password, `totp_secret` | `TEXT` | `TEXT` | `TEXT` | `TEXT` |

* Time is always UTC text `YYYY-MM-DD HH:MM:SS`, so comparing deadlines works the same in all databases. The "now" default for `created_at` and similar columns also exists in the other databases (as a database expression).
* Email uniqueness is enforced everywhere by the regular unique index `idx_users_email` (several `NULL`s are allowed); in SQLite old databases have it as a partial index (`WHERE email IS NOT NULL`), which behaves the same.
* DuckDB does not allow altering a table that has an index, so `users` is created there with all columns at once (migrations 2, 5, 6, 7 and 8 add nothing).
* In MySQL DDL is not rolled back, while in PostgreSQL the migrations run in a single transaction; in both databases they run under a lock, and a repeated run completes whatever is missing.

## Migrations

`aa_init_db()` applies them in a single transaction (except MySQL, where DDL is not rolled back), idempotently, and is safe on running databases.

| Version | Name |
| --- | --- |
| 1 | `users` |
| 2 | `users_blocked_column` |
| 3 | `auth_sessions` |
| 4 | `login_attempts` |
| 5 | `users_must_change_column` |
| 6 | `users_created_and_last_login_columns` |
| 7 | `password_resets_and_email` |
| 8 | `totp_two_factor` |
| 9 | `oauth_states` |

## Legacy schemas

* Everything in this section applies to SQLite. A `users` table without an `id` column (login is the PRIMARY KEY, as in older home-grown schemas) is supported: the missing columns are added.
* Plaintext passwords are not migrated automatically by `aa_init_db()`: use `aa_migrate_plaintext_passwords(db_path)` while the application is stopped (it makes a backup, uses a transaction and verifies each hash). Until the migration, signing in with a plaintext password is impossible, this is intentional.
* A schema with other column names (`username`/`pwd`) is not supported: first bring the table to `login`/`password`/`role`.
* Logins that differ only in case (`kiruka` and `Kiruka`) are preserved and work as different users; a new such login cannot be created.

## What the application can store alongside

The application's own tables and its own columns about users (department, projects, per-user permissions) live in the application's tables, not in `users`: the package owns only its own columns. In the user card such data is shown by the `extra_card_ui` slot (see extension-points.md).
