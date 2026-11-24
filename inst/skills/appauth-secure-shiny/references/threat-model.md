# Threat model: who authentication on appauth protects against and what is left to the app

The full version with flows and accepted decisions is the package vignette `architecture-and-security` (`vignette("architecture-and-security", package = "appauth")`). This file covers what you need to know during implementation and audit.

## What we protect

* user passwords (the database holds only scrypt hashes);
* sessions and auto-login tokens;
* app data and functions from those who lack the permission (server-side permission checks);
* user management (administrator only);
* the event log (who did what and when).

## Who we defend against

| Adversary | Capabilities | What mitigates it |
| --- | --- | --- |
| An outsider without an account | guesses passwords, tries SQL injection in the login form, sends forged Shiny requests | login lockout after a series of failures and a global per-minute limit, parameterized queries, a permission check in every handler, the server part of a tab is registered only when the permission is held |
| A low-role user | calls other handlers through the browser (a hidden button is not protection), tries to grant themselves permissions | `aa_require()` as the first line of a handler, the role is taken from server-side state, user management is available only to `admin_role` and is checked against the database on every action |
| Someone who stole the database or a copy of it | reads the tables | passwords are only scrypt hashes, tokens only sha256 (no ready-to-use tokens in the database) |
| Someone who intercepted traffic | reads the password and cookie | HTTPS (the responsibility of the app and infrastructure), cookie with `SameSite=Lax` and `Secure` on HTTPS |
| A former or blocked employee | uses an open session or cookie | blocking and deletion revoke tokens and end open sessions (within `session_check_seconds`), a deleted user's token does not pass to a new owner of the login |
| An administrator by mistake | blocks or deletes themselves or the last administrator | the package forbids it: you cannot block, delete or demote yourself or the last active administrator |

## What the package covers and what it does not

Covered by the package:

* password hashing, verification, length policy, migration of plaintext passwords;
* brute-force protection (per login and global), a dummy hash check for a non-existent login (same response time and same message);
* auto-login tokens (32 random bytes, sha256 in the database, expiry, revocation on sign-out, blocking, deletion, password change, "sign out everywhere");
* checking of open sessions (blocking, deletion, role change, revoked token);
* parameterized SQL queries inside the package, escaping of logins in the UI (HTML in a login is not executed);
* server-side permission checks (`aa_can()`, `aa_require()`), closed by default;
* events for auditing (`on_event`), passwords and tokens never reach the events;
* schema migrations without data loss.

NOT covered by the package, this is the app's responsibility:

* **HTTPS and proxy.** Without HTTPS the password and token travel in clear text.
* **Every action handler.** The package does not know your handlers: `aa_require()` must be put in each one.
* **Protection of app-specific actions:** running commands (`system`, `system2`, `shell`), reading and writing files by a path from the user, app SQL (your own queries must also be parameterized only), HTML output (`escape = FALSE`, `HTML(paste(...))` with foreign data).
* **Secrets:** `.Renviron`, keys and tokens stay outside the repository.
* **Database download** from the UI: do not serve the tables `users`, `auth_sessions`, `login_attempts` (see recipes/database-download.md).
* **Backups and permissions on the database file.**
* **A spare administrator** (see the limitation about lockout by login).

## Known limitations (accepted)

* **Legacy cookie mode:** `cookie_mode = "legacy"` writes the cookie from JavaScript, so XSS in the app can steal the token. Since 0.12.0 the default `httponly` mode writes it from the server through a short-lived encrypted one-time ticket; JavaScript never sees the token. Compensation in legacy mode: the token is stored in the database only as a hash and is revoked on sign-out, blocking, password change. Even with `HttpOnly`, XSS can act in the current session, so the app must not output unvalidated HTML.
* **Lockout by login, not by IP:** behind nginx the client IP is not visible. Consequence: someone can deliberately lock another person's login (including the administrator's) for `lockout_minutes`; the administrator lifts the lock in the user card, so a spare administrator is needed. The global per-minute limit stops guessing across many logins. Configure request limiting (`limit_req`) in nginx.
* **The password is checked only by length** (6 to 128 characters by default), there is no list of forbidden passwords at creation time; `aa_check_default_accounts()` finds weak passwords in an audit.
* **Single sign-on only through Google** (since `appauth` 0.7.0, off by default). There are no other providers. Signing in through Google is equivalent to access to the employee's Google account: it is protected by the organization (Workspace policies), and appauth's own 2FA is not asked for at sign-in. By default the user must be created in advance, and the email in the app must match the Google address: changing an address in Workspace without updating the app blocks sign-in, and reassigning an address to another person gives them someone else's account. Since 0.11.0 `google_signup = TRUE` may create a non-admin account from a verified email in `google_domains` with a random password hash; without a domain list this must be explicitly allowed with `google_signup_require_domains = FALSE`. While password login is enabled it remains the weakest point: disable it (`password_login = FALSE`) when acceptable. `google_domains` is compared against `hd` (the organization's primary domain) and against the email domain; an empty list disables the domain check. Two-factor protection (since `appauth` 0.5.0) is voluntary and only via TOTP codes: no SMS, push notifications or hardware keys, no forced enabling for roles; sign-in through the auto-login cookie does not ask for a code. Losing the `totp_key` key makes the secrets unreadable.
* **Self-registration (since 0.11.0, off by default)** creates only non-admin accounts. With email confirmation, only possession of the address matters: set `registration_domains` for a closed organization and keep the link TTL short. With `registration_verify_email = FALSE` the account is created immediately; use this only when anyone may join. Taken logins and emails return one generic response, throttling is per address, and pending links are consumed when the same user or email is created elsewhere.
* **Up to `session_check_seconds` (30 seconds by default)** between blocking a user and closing their open session.
* **SQLite, DuckDB, MySQL / MariaDB and PostgreSQL are supported** (since `appauth` 0.8.0). BigQuery and other analytical stores do not fit: one-time tokens and last-administrator protection require atomic updates and unique constraints. DuckDB opens a file from one process. In MySQL logins are exact only in columns created by the package (binary collation): recreate a `users` table created by hand through `aa_init_db()`.
* **No independent security audit has been performed:** the properties are confirmed by the package's automated tests (1400+ checks), browser verification and the experience of fixing the bugs found, but not by an external specialist.

## What else to consider at implementation

* First start on an empty database: whoever opens the app first creates the administrator. Create it yourself right after deployment (recipes/first-admin.md).
* The login is compared exactly (`Alsey` and `alsey` are different), a new login that matches an existing one case-insensitively cannot be created.
* Password reset, role change, blocking and "sign out on all devices" affect open sessions only when `aa_session_guard()` is wired in.
