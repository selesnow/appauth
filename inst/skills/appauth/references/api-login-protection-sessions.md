# appauth reference: Login protection and sessions

Package version: 0.11.1. This file is generated automatically from the package help (`dev/skills/build_reference.R`) and must not be edited by hand.

Functions in this section:
`aa_login_gate()`, `aa_record_attempt()`, `aa_login_lock_remaining()`, `aa_global_throttled()`, `aa_clear_attempts()`, `aa_issue_token()`, `aa_find_session_user()`, `aa_revoke_token()`, `aa_revoke_sessions()`, `aa_active_autologins()`, `aa_user_session_valid()`

## Contents

- [aa_login_gate](#aa_login_gate)
- [aa_record_attempt](#aa_record_attempt)
- [aa_login_lock_remaining](#aa_login_lock_remaining)
- [aa_global_throttled](#aa_global_throttled)
- [aa_clear_attempts](#aa_clear_attempts)
- [aa_issue_token](#aa_issue_token)
- [aa_find_session_user](#aa_find_session_user)
- [aa_revoke_token](#aa_revoke_token)
- [aa_revoke_sessions](#aa_revoke_sessions)
- [aa_active_autologins](#aa_active_autologins)
- [aa_user_session_valid](#aa_user_session_valid)

## aa_login_gate

```text
Can a login be attempted right now

Description:

     A single check before verifying the password: first the global failure limit across
     all logins, then the lockout of this login. If login is closed, there is no need to
     verify the password, and no need to record the attempt (otherwise the lockout would
     be extended).

Usage:

     aa_login_gate(conn, login, settings = aa_settings())

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: The entered login (exact, case-sensitive).

settings: Settings, the result of 'aa_settings()'.

Details:

     The function *does not stop login on an error*: if the protection tables do not
     exist or cannot be queried, login is considered allowed (the password is still
     verified) and the reason is written to the app log. This way an unavailable attempts
     table does not lock out all users.

Value:

     A list: 'allowed' ('TRUE' or 'FALSE'), 'reason' ('NA', '"throttled"' for the global
     limit or '"locked"' for a login lockout), 'seconds' (how many seconds are left until
     the login lockout ends, otherwise 0) and 'message' (text to show to the user in the
     settings language, 'NA' if login is allowed).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_login_gate(conn, "alsey")$allowed
       for (i in 1:5) aa_record_attempt(conn, "alsey", FALSE)
       aa_login_gate(conn, "alsey")
       DBI::dbDisconnect(conn)
     }
```

## aa_record_attempt

```text
Record a login attempt

Description:

     Stores the result of a login attempt for brute-force protection. Attempts with an
     empty login are not recorded. Call it only for attempts made NOT during a lockout:
     attempts during a lockout are not recorded so as not to extend it.

Usage:

     aa_record_attempt(conn, login, success, settings = aa_settings())

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: The entered login (exact, case-sensitive).

 success: 'TRUE' for a successful login (resets the failure counter), 'FALSE' for a
          failed attempt.

settings: Settings, the result of 'aa_settings()'.

Value:

     'TRUE' if the attempt was recorded, 'FALSE' if the login is empty (invisibly).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_record_attempt(conn, "alsey", success = FALSE)
       DBI::dbDisconnect(conn)
     }
```

## aa_login_lock_remaining

```text
Seconds left until a login lockout ends

Description:

     Counts the failed attempts of a login after its last successful login and within the
     'lockout_minutes' window. If there are at least 'max_failed_logins' of them, the
     login is blocked until the end of the window, counted from the last failure.

Usage:

     aa_login_lock_remaining(conn, login, settings = aa_settings())

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: The entered login (exact, case-sensitive).

settings: Settings, the result of 'aa_settings()'.

Details:

     The login is matched *exactly*: 'Alsey' and 'alsey' are different logins with
     separate counters, as at login.

Value:

     An integer number of seconds, 0 if login is allowed.

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       for (i in 1:5) aa_record_attempt(conn, "alsey", FALSE)
       aa_login_lock_remaining(conn, "alsey")
       aa_login_lock_remaining(conn, "Alsey")
       DBI::dbDisconnect(conn)
     }
```

## aa_global_throttled

```text
Is the global failed login limit exceeded

Description:

     Counts failed attempts across all logins together over the last minute. If there are
     at least 'max_failed_logins_per_minute' of them, login is temporarily closed for
     everyone: this stops guessing across many logins and growth of the attempts table.

Usage:

     aa_global_throttled(conn, settings = aa_settings())

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

settings: Settings, the result of 'aa_settings()'.

Value:

     'TRUE' or 'FALSE'.

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_global_throttled(conn)
       DBI::dbDisconnect(conn)
     }
```

## aa_clear_attempts

```text
Clear a login lockout caused by failed attempts

Description:

     Deletes the failed login attempts of a login (successful ones stay), so the login
     can be used again right away. A manual block by an administrator
     ('aa_set_blocked()') is not lifted by this function.

Usage:

     aa_clear_attempts(conn, login, settings = aa_settings())

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: The entered login (exact, case-sensitive).

settings: Settings, the result of 'aa_settings()'.

Value:

     The number of deleted records (invisibly).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       for (i in 1:5) aa_record_attempt(conn, "alsey", FALSE)
       aa_clear_attempts(conn, "alsey")
       aa_login_lock_remaining(conn, "alsey")
       DBI::dbDisconnect(conn)
     }
```

## aa_issue_token

```text
Issue an autologin token

Description:

     Creates a random token (32 bytes) and stores its hash and expiry ('session_days'
     from 'aa_settings()') in the database. The token itself must be handed to the
     browser (in a cookie); it cannot be recovered from the database.

Usage:

     aa_issue_token(conn, login, settings = aa_settings())

Arguments:

    conn: Database connection.

   login: User login.

settings: Settings, the result of 'aa_settings()'.

Details:

     No token is issued ('NULL' is returned) if autologin is disabled in the settings,
     the user does not exist or the user is blocked.

Value:

     A string with the token or 'NULL'.

Examples:

     ## Not run:

     token <- aa_issue_token(conn, "ivan")
     if (!is.null(token)) session$sendCustomMessage("setAuthCookie", token)
     ## End(Not run)
```

## aa_find_session_user

```text
Find a user by autologin token

Description:

     Returns the user only if the token exists, is not revoked and has not expired, and
     the user exists, is not blocked and is not required to change the password (after a
     password change the user must log in again). The role is taken from the database at
     the time of the check.

Usage:

     aa_find_session_user(conn, token)

Arguments:

    conn: Database connection.

   token: Token from the cookie.

Value:

     A list with 'login' and 'role' fields, or 'NULL'.

Examples:

     ## Not run:

     user <- aa_find_session_user(conn, input$auth_cookie)
     if (!is.null(user)) {
       # the user logs in without a password
     }
     ## End(Not run)
```

## aa_revoke_token

```text
Revoke an autologin token

Description:

     Needed on logout: the cookie in the browser stops working afterwards.

Usage:

     aa_revoke_token(conn, token)

Arguments:

    conn: Database connection.

   token: Token from the cookie.

Value:

     The number of revoked tokens (0 or 1), invisibly.

Examples:

     ## Not run:

     aa_revoke_token(conn, input$auth_cookie)
     ## End(Not run)
```

## aa_revoke_sessions

```text
End all sessions of a user

Description:

     Revokes all autologin tokens of the user. Open sessions with such tokens are ended
     by 'aa_session_guard()' at its next check, and the cookies in browsers stop working.

Usage:

     aa_revoke_sessions(conn, login)

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

Value:

     The number of revoked tokens (invisibly).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       token <- aa_issue_token(conn, "boss")
       aa_revoke_sessions(conn, "boss")
       is.null(aa_find_session_user(conn, token))
       DBI::dbDisconnect(conn)
     }
```

## aa_active_autologins

```text
How many active autologins users have

Description:

     Counts autologin tokens that are not revoked and have not expired: that many devices
     currently "remember" the user's login (cookie), i.e. can log in without a password.
     This is not the number of open tabs: the app does not track them. If the token table
     does not exist or cannot be queried, it is assumed there are no tokens.

Usage:

     aa_active_autologins(conn, login = NULL)

Arguments:

    conn: Database connection.

   login: User login or 'NULL'.

Value:

     For a given 'login', an integer (0 if there are no tokens). With 'login = NULL', a
     table with 'login' and 'n' columns for users that have active tokens.

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       aa_issue_token(conn, "boss")
       aa_active_autologins(conn, "boss")
       DBI::dbDisconnect(conn)
     }
```

## aa_user_session_valid

```text
Check that an open session is still valid

Description:

     Called periodically (every 'session_check_seconds') so that blocking, deletion, role
     demotion and session termination take effect for a user who is already logged in,
     not only at the next login. A session is invalid if the user was deleted or blocked,
     the role in the database differs from the role in the session, or the token of this
     session was revoked (password reset, "end all sessions").

Usage:

     aa_user_session_valid(conn, login, role, token = NULL)

Arguments:

    conn: Database connection.

   login: User login.

    role: The role the user logged in with.

   token: Autologin token of this session ('auth$token()') or 'NULL' if the session has
          no token (for example, autologin is disabled): then the token is not checked.

Details:

     If the database cannot be read, the session is considered valid ('reason =
     "check_failed"') so that a database failure does not kick out all users; access is
     not widened, because no password is checked.

Value:

     A list: 'valid' (logical), 'reason' ('"ok"', '"deleted"', '"blocked"',
     '"role_changed"', '"token_revoked"', '"check_failed"') and 'role' (the current role
     from the database or 'NULL').

Examples:

     ## Not run:

     check <- aa_user_session_valid(conn, auth$user()$login, auth$user()$role,
     auth$token())
     if (!check$valid) auth$logout(reason = check$reason)
     ## End(Not run)
```

