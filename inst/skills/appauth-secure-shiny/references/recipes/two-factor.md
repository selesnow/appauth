# Recipe: two-factor authentication (TOTP)

Needed by apps with privileged roles or sensitive data. Requires `appauth` version 0.5.0 or newer; mandatory role enrollment requires 0.13.0. **Off by default**: protection is voluntary unless roles are listed in `totp_required_roles`. A voluntary user turns protection on in their personal area; a required role is shown the setup wizard before entering the application. Full reference: the `appauth` skill (`references/extension-points.md`, `references/api-two-factor.md`).

## When to enable it

* The app manages a server, tasks, access or employee data, and there are several administrators.
* Since 0.13.0, list privileged roles in `totp_required_roles`; `aa_auth_server()` then forces enrollment before the application. Without that setting, ask administrators to enable 2FA themselves.
* Do not count on 2FA as a replacement for HTTPS, decent passwords and permission checks in handlers.

## Steps

1. **The secret-encryption key.** The TOTP secret is stored in the database encrypted, and the key is taken from a service environment variable (a string of at least 16 characters). It is **not** kept in the repository, in `config.yaml` next to the database, or in database backups. Losing or replacing the key makes the secrets unreadable: users will have to set up 2FA again, and the administrator resets it in the user card.

2. **Settings.**

```r
settings <- aa_settings_from_list(
  conf$security,
  totp_enabled        = TRUE,
  totp_key            = Sys.getenv("APP_TOTP_KEY"),
  totp_issuer         = "Service name",       # shown by the authenticator app
  totp_required_roles = "admin"               # optional; character() keeps 2FA voluntary
)
```

3. **The personal-area block.** The server is attached once, like the password change, and the UI goes into the profile:

```r
aa_totp_server("totp", conn, auth, settings, on_event = log_event)

tabPanel("Profile", aa_password_ui("password"), hr(), aa_totp_ui("totp"))
```

The login itself (the code form after the password) is handled by `aa_auth_server()`.

4. **The QR code.** It is built by the optional `qrcode` package: install it into the server library, otherwise the user is shown only the key for manual entry (a working option, but less convenient).

5. **Server time** must be synchronised (NTP): the code is tied to 30-second steps, and the allowed drift is set by `totp_window` (1 step by default).

6. **Events.** `totp_enabled`, `totp_disabled`, `totp_failed`, `totp_reset`, `totp_enrollment_required`, `recovery_code_used` arrive in the `on_event` hook. In `aa_event_logger()` add them to `actions` if your log uses its own names. Series of `totp_failed` are worth showing the same way as `login_failed` series.

7. **A lost phone.** The user has 10 backup codes (single-use, shown once at enabling). If those are gone too: the administrator opens the user card and presses "Reset 2FA" (the user's sessions end, event `totp_reset`).

## How it is protected (for checking during an audit)

* The secret is encrypted (`sodium`); stealing the database file alone does not yield codes. Backup codes are in the database only as sha256.
* A code is accepted once: the accepted time step is remembered with an atomic query, and entering the same code again is rejected.
* A wrong code counts as a failed login attempt, and the login is locked under the same rules as for password guessing. A successful attempt is recorded only after a correct code, so a correct password does not reset the counter.
* Before the code, no auto-login token is issued. Login by auto-login cookie does not ask for the code from an enrolled user (the cookie was issued after the code and is valid for `session_days` days: this is a "trusted device"). A role in `totp_required_roles` without enabled 2FA is an exception: the cookie is revoked and the enrollment wizard is shown.
* `aa_session_guard()` ends a session with reason `totp_required` while the role's 2FA is missing; `aa_totp_server()` does not allow such a role to disable 2FA.
* Disabling requires the password and a code, and the code is checked only when the password is correct. Password reset by email does not bypass 2FA.

## Verification

* A user with 2FA enabled sees the code form after a correct password, not the app; a wrong code does not let them in.
* A role in `totp_required_roles` without 2FA sees the enrollment wizard after a correct password (and after a forced password change), after Google sign-in and instead of a remembered cookie; the wizard has identifiers `totp_enroll_code` and `totp_enroll_btn`.
* The same code is not accepted a second time; a backup code works once.
* After a series of wrong codes the login is locked (as with password guessing).
* Disabling with a wrong password or code does not remove protection, and backup codes are not spent.
* In `testServer` tests the code is computed by `aa_totp_code(secret)`; for a second login in the same test take the code of the next step, `aa_totp_code(secret, Sys.time() + 30)`, because an accepted step does not pass again. In Playwright compute the code per RFC 6238 from the key in `.aa-totp code`.

## Creating the key from the UI (optional)

Instead of editing `.Renviron` by hand, an administrator can create the key with a button in the 2FA block of the settings. Rules without which this must not be done:

* **Only while the key exists nowhere** (neither in the process environment nor in `.Renviron`) **and nobody has 2FA enabled.** An existing key must not be overwritten: the secrets of all users would become unreadable. If the key is lost while someone has 2FA enabled, creation is forbidden: first the administrator resets 2FA for those users.
* **Writing is safe:** a copy of `.Renviron` before writing (`.Renviron.bak_*`, add the mask to `.gitignore`), other lines are not changed, writing goes through a temporary file and a rename, after writing the value is re-read, and on a mismatch the file is restored from the copy.
* **The key takes effect immediately** (`Sys.setenv()` in the running process), no restart needed; the file is also updated, so after a restart the key is the same.
* **Show the key once** in a window that cannot be closed without the "I saved the key" checkbox (a copy in a password manager is required). After that the key is shown nowhere: for verification show a fingerprint (the first 8 characters of its SHA-256), and write only the fingerprint to the log.
* **A "Check key" button** makes a trial 2FA setup on a temporary in-memory database; the block warns if the key in the file and in the running process differ (a restart is needed).
* The action is for the administrator only (a role check on the server in the handler, like the other settings), and enabling 2FA in the settings without a key must be rejected on save.
* **Startup must not silently turn 2FA off.** If the config has 2FA enabled but there is no key or the required package version, stop the app at start with a clear message (otherwise users with 2FA would start logging in with the password alone); when settings change at runtime, keep the previous ones. Validate `totp_required_roles` against the known roles and require `totp_enabled = TRUE`, so a typo does not silently leave a privileged role voluntary.
