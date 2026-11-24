# appauth event catalog

Package version: 0.11.2. The table is generated from `aa_events()`.

All modules and `aa_require()` report events to a single function `on_event(event, user, session_id, value)`:

* `event`: the event key from the table below;
* `user`: the login the event is attributed to (for a failed login, the login that was entered; if there is no login, `"anonymous"`);
* `session_id`: the Shiny session identifier;
* `value`: additional detail, always a string. Passwords and tokens never appear in events.

An error inside the hook never interrupts the package action (it is printed as a message). The package itself writes nothing to application logs.

| Event | What happened | What is in `value` |
| --- | --- | --- |
| `login_success` | Successful login (by password, via Google, via an auto-login cookie, or after self-registration) | cookie (auto-login), google (Google sign-in) or registration (self-registration) |
| `login_failed` | Wrong login or password | password_disabled, if password login is disabled |
| `login_locked` | Login attempt for a login locked after failed attempts | seconds until the lockout ends |
| `login_blocked_user` | Login attempt by a user blocked by an administrator | (empty) |
| `login_throttled` | Refusal because of the global per-minute limit of failed attempts | (empty) |
| `login_unlocked` | An administrator lifted the lockout caused by login attempts | the login the lockout was lifted from |
| `logout` | The user logged out themselves | (empty) |
| `session_forced_logout` | The session was terminated forcibly | reason: deleted, blocked, role_changed, token_revoked |
| `first_admin_created` | The first administrator was created | (empty) |
| `user_added` | An administrator added a user | login of the new user and role |
| `user_removed` | An administrator removed a user | login of the removed user |
| `user_role_changed` | An administrator changed a user's role | login and new role |
| `password_changed` | The user changed their own password | (empty) |
| `sessions_revoked` | An administrator terminated all of a user's sessions | user login |
| `password_reset` | An administrator changed a user's password | user login |
| `user_blocked` | An administrator blocked a user | user login |
| `user_unblocked` | An administrator unblocked a user | user login |
| `access_denied` | Access denied: the role lacks the required permission | permission name |
| `password_reset_requested` | Password recovery requested by email (the user always sees the same response) | result: sent, no_user, no_email, blocked, throttled, send_failed |
| `password_reset_done` | Password changed via the link from the email | (empty) |
| `password_reset_failed` | Invalid or expired password recovery link | (empty) |
| `email_changed` | An administrator set, changed, or removed a user's email | user login |
| `totp_enabled` | The user enabled two-factor authentication | (empty) |
| `totp_disabled` | The user disabled two-factor authentication | (empty) |
| `totp_failed` | Wrong code when confirming login or disabling 2FA | (empty) |
| `totp_reset` | An administrator reset a user's 2FA | user login |
| `recovery_code_used` | Login confirmed with a recovery code | (empty) |
| `google_login_failed` | Failed Google login (the user sees a generic message) | reason: start_failed, bad_state, bad_browser, bad_code, exchange_failed, bad_token, bad_nonce, email_unverified, domain, no_user, blocked, cancelled, signup_login_taken; followed by a space and the email, if known |
| `weak_password_set` | A weak password was accepted (`password_policy = "warn"` mode) | login and reason: password_common, password_equals_login, password_repeated |
| `registration_requested` | Self-registration requested (the user always sees the same response) | sent, created, user_exists, email_exists, email_invalid, registration_domain, registration_throttled, send_failed, or a login or password validation reason |
| `registration_confirmed` | Account created from the email confirmation link | login of the new user |
| `registration_failed` | Failed attempt to confirm a registration | reason: registration_link_invalid, user_exists, email_exists |
| `google_user_created` | Account created automatically on first Google sign-in | login of the new user |

## Event handler: aa_event_logger()

Instead of a hand-written hook, build the handler with the ready-made function (since version 0.3.0): you write only `writer(action, user, session_id, value)`, while event filtering, action names, the logging switch, and value formatting are handled by the package.

```r
log_event <- aa_event_logger(
  function(action, user, session_id, value) {
    write_action_log(user = user, func = action, session_id = session_id, value = value)
  }
)
# all events are written under the event keys; the hook is passed to on_event of the modules and aa_require()
```

If the application already has a log with its own action names (for example `'User add'`, `'Login failed'`), map events to names with the named vector `actions`: only the listed events are written, and existing reports keep working:

```r
legacy_names <- c(user_added = "User add", user_removed = "User remove", login_failed = "Login failed")
log_event <- aa_event_logger(
  function(action, user, session_id, value) write_action_log(user = user, func = action, session_id = session_id, value = value),
  actions = legacy_names,
  enabled = function(event) isTRUE(conf_rv()$logging$action_log),     # switch from the config, called on every event
  format_value = function(event, user, value) sub(" \\(.*\\)$", "", value)  # e.g. keep only the login in value
)
```

Arguments: `events` (which events to write), `actions` (the name is the event key, the value is the action name), `enabled` (`TRUE`, `FALSE`, or `function(event)`), `format_value` (`function(event, user, value)`). Unknown event names raise an error immediately. A failure in `writer` does not interrupt the package action. If you need to do something else (for example, record the end of a session on `logout`), wrap the handler in your own function `function(event, user, session_id, value)` that calls it and does the rest. A hand-written hook also works: any function with the arguments `event, user, session_id, value` is enough.

The `login_success` and `logout` events are usually not needed in an action log if the application keeps a separate session log: `session_forced_logout` and `logout` are convenient for recording the end of a session.
Every event in the catalog is actually emitted by the package code, and the list grows only together with a package release: before using a new event, check `aa_events()` of the installed version.
