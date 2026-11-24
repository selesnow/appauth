# appauth reference: Users

Package version: 0.13.0. This file is generated automatically from the package help (`dev/skills/build_reference.R`) and must not be edited by hand.

Functions in this section:
`aa_get_user()`, `aa_list_users()`, `aa_users_exist()`, `aa_users_overview()`, `aa_create_user()`, `aa_create_first_admin()`, `aa_validate_new_user()`, `aa_authenticate()`, `aa_set_password()`, `aa_change_own_password()`, `aa_set_role()`, `aa_set_blocked()`, `aa_delete_user()`, `aa_check_can_block()`, `aa_check_can_delete()`, `aa_check_can_change_role()`

## Contents

- [aa_get_user](#aa_get_user)
- [aa_list_users](#aa_list_users)
- [aa_users_exist](#aa_users_exist)
- [aa_users_overview](#aa_users_overview)
- [aa_create_user](#aa_create_user)
- [aa_create_first_admin](#aa_create_first_admin)
- [aa_validate_new_user](#aa_validate_new_user)
- [aa_authenticate](#aa_authenticate)
- [aa_set_password](#aa_set_password)
- [aa_change_own_password](#aa_change_own_password)
- [aa_set_role](#aa_set_role)
- [aa_set_blocked](#aa_set_blocked)
- [aa_delete_user](#aa_delete_user)
- [aa_check_can_block](#aa_check_can_block)
- [aa_check_can_delete](#aa_check_can_delete)
- [aa_check_can_change_role](#aa_check_can_change_role)

## aa_get_user

```text
User by login

Description:

     The login is matched exactly, case-sensitive. The password is not included in the
     result.

Usage:

     aa_get_user(conn, login)

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

Value:

     A one-row table with 'login', 'role', 'blocked', 'created_at' and 'last_login_at'
     columns, or 'NULL' if there is no such user. Dates are stored as text '"YYYY-MM-DD
     HH:MM:SS"' in UTC; for users created before version 0.3.0 'created_at' is empty
     ('NA'), and 'last_login_at' is empty until the user logs in with a password.

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       aa_get_user(conn, "boss")
       aa_get_user(conn, "nobody")
       DBI::dbDisconnect(conn)
     }
```

## aa_list_users

```text
List of users

Description:

     List of users

Usage:

     aa_list_users(conn)

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

Value:

     A table with 'login', 'role', 'blocked', 'created_at' and 'last_login_at' columns in
     creation order (for the dates see 'aa_get_user()'). Password hashes are not included
     in the result.

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       aa_list_users(conn)
       DBI::dbDisconnect(conn)
     }
```

## aa_users_exist

```text
Does the database have at least one user

Description:

     If there are no users, the app needs to show the form for creating the first
     administrator; the package login module does this.

Usage:

     aa_users_exist(conn)

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

Value:

     'TRUE' or 'FALSE'.

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_users_exist(conn)
       DBI::dbDisconnect(conn)
     }
```

## aa_users_overview

```text
Users with statuses for a table

Description:

     A list of users with the flags needed for the table on the access management tab:
     whether the user is blocked by an administrator, whether login is blocked after
     failed attempts and how much time is left. If the attempts tables are unavailable,
     the attempt-based lockout status is treated as absent.

Usage:

     aa_users_overview(conn, settings = aa_settings())

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

settings: Settings, the result of 'aa_settings()'.

Value:

     A table with columns 'login', 'role', 'blocked', 'state' ('"blocked"' for a block by
     an administrator, '"locked"' for a lockout by attempts, otherwise '"ok"'),
     'lock_seconds' (seconds until the attempt lockout ends) and 'status' (status text in
     the settings language, an empty string for '"ok"'), as well as 'created_at' and
     'last_login_at' (dates from the database in UTC, as in 'aa_get_user()') and
     'created' and 'last_login' (the same dates for display: server local time, with the
     texts for "unknown" and "never logged in" for unknown dates), as well as 'has_email'
     (1 if an email is set for password recovery; the address itself is not included),
     'totp_on' (1 if the user has 2FA enabled) and 'autologins' (how many active
     autologins, see 'aa_active_autologins()').

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       aa_users_overview(conn)
       DBI::dbDisconnect(conn)
     }
```

## aa_create_user

```text
Create a user

Description:

     Creates a user with a password hash. Before creation the login, password, role (must
     be in 'roles' from the settings) and login uniqueness are checked. On a rule
     violation the function aborts with an error of class 'appauth_error_user' with text
     in the settings language (the 'reason' field holds the reason key) that can be shown
     to the user.

Usage:

     aa_create_user(
       conn,
       login,
       password,
       role,
       settings = aa_settings(),
       must_change = FALSE,
       email = NULL
     )

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

password: The password in plain text (only the hash goes to the database).

    role: A role from the 'roles' list of the settings.

settings: Settings, the result of 'aa_settings()'.

must_change: Require a password change at the first login (sensible if the password was
          set by an administrator).

   email: Address for password recovery or 'NULL' (the address can be set later with
          'aa_set_email()'). The format and uniqueness are checked.

Value:

     'TRUE' (invisibly).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_user(conn, "worker", "worker-password", "user")
       aa_list_users(conn)

       # the error can be shown to the user
       tryCatch(
         aa_create_user(conn, "worker", "another-password", "user"),
         appauth_error_user = function(e) conditionMessage(e)
       )
       DBI::dbDisconnect(conn)
     }
```

## aa_create_first_admin

```text
Create the first user (administrator)

Description:

     Creates a user with the 'admin_role' role from the settings *only if the 'users'
     table is empty*. The check and the insert run in one SQL statement, so of two
     simultaneous requests (two browser tabs, two sessions) only one succeeds.

Usage:

     aa_create_first_admin(conn, login, password, settings = aa_settings())

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

password: The password in plain text (only the hash goes to the database).

settings: Settings, the result of 'aa_settings()'.

Details:

     The login and password are checked by the same rules as in 'aa_create_user()' (on a
     violation, an error of class 'appauth_error_user').

Value:

     'TRUE' if the administrator was created, 'FALSE' if users already exist.

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       aa_create_first_admin(conn, "second", "second-password")
       DBI::dbDisconnect(conn)
     }
```

## aa_validate_new_user

```text
Validate a new user's data

Description:

     Checks the login, password, role and login uniqueness without creating anything.
     Suitable for showing an error in a form before the user is created.

Usage:

     aa_validate_new_user(conn, login, password, role, settings = aa_settings())

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

password: The password in plain text (only the hash goes to the database).

    role: A role from the 'roles' list of the settings.

settings: Settings, the result of 'aa_settings()'.

Details:

     A login is considered taken if it matches an existing one exactly or
     case-insensitively (so new users do not create pairs like 'Kiruka' and 'kiruka').

Value:

     'NULL' if the data is fine, otherwise the problem text (in the settings language).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       aa_validate_new_user(conn, "Boss", "another-password", "user")
       aa_validate_new_user(conn, "worker", "another-password", "user")
       DBI::dbDisconnect(conn)
     }
```

## aa_authenticate

```text
Verify login and password (login)

Description:

     Looks up the user by login (exact, case-sensitive) and verifies the password against
     the hash. If the user does not exist, verification is still run against a dummy hash
     so the response time does not reveal whether the login exists. A plain-text password
     in the database is never accepted.

Usage:

     aa_authenticate(conn, login, password)

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

password: The entered password.

Details:

     For a user blocked by an administrator, with a correct password a row with 'blocked
     = 1' is returned: what to do next is up to the calling code (the login module
     reports the block only to someone who knows the password). With a wrong password the
     result is always 'NULL'.

Value:

     A one-row table with 'login', 'role', 'blocked' and 'must_change' columns (the
     password is not included in the result), or 'NULL' if the login or password is
     wrong.

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       aa_authenticate(conn, "boss", "boss-password")
       aa_authenticate(conn, "boss", "wrong")
       DBI::dbDisconnect(conn)
     }
```

## aa_set_password

```text
Set a new password for a user

Description:

     Stores the hash of the new password and *revokes all autologin tokens* of the user,
     so that after a password reset old browser sessions stop working (open sessions are
     ended by 'aa_session_guard()'). Unused password recovery links sent by email also
     stop working. The password is checked against the rules from the settings; on a
     violation, an error of class 'appauth_error_user'.

Usage:

     aa_set_password(
       conn,
       login,
       password,
       settings = aa_settings(),
       must_change = FALSE,
       keep_token = NULL
     )

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

password: The password in plain text (only the hash goes to the database).

settings: Settings, the result of 'aa_settings()'.

must_change: Require the user to change this password at the next login (sensible if the
          password was set by an administrator).

keep_token: An autologin token that must not be revoked (the current session of the
          person changing their own password), or 'NULL'.

Value:

     The number of changed users (invisibly): 1, or 0 if there is no such login.

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       aa_set_password(conn, "boss", "new-boss-password")
       aa_authenticate(conn, "boss", "new-boss-password")
       DBI::dbDisconnect(conn)
     }
```

## aa_change_own_password

```text
Change your own password

Description:

     For the user themselves: the current password must be confirmed. The new password is
     checked against the rules from the settings and must differ from the current one.
     Autologin tokens of other sessions are revoked; the token of the current session
     ('keep_token') stays. The password change requirement ('must_change') is cleared.

Usage:

     aa_change_own_password(
       conn,
       login,
       old_password,
       new_password,
       settings = aa_settings(),
       keep_token = NULL
     )

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

old_password: The current password.

new_password: The new password.

settings: Settings, the result of 'aa_settings()'.

keep_token: Autologin token of the current session that must not be revoked.

Details:

     Errors (wrong current password, weak or the same password) have class
     'appauth_error_user' and text in the settings language.

Value:

     'TRUE' (invisibly).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       aa_change_own_password(conn, "boss", "boss-password", "new-boss-password")
       DBI::dbDisconnect(conn)
     }
```

## aa_set_role

```text
Change a user's role

Description:

     The role must be in the 'roles' list of the settings; the administrator role cannot
     be taken from the last active administrator (see 'aa_check_can_change_role()'). On a
     violation, an error of class 'appauth_error_user'.

Usage:

     aa_set_role(conn, login, role, settings = aa_settings())

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

    role: A role from the 'roles' list of the settings.

settings: Settings, the result of 'aa_settings()'.

Details:

     The user's open session keeps working with the old role until the login module's
     next live-session check, and at the next login the role is taken from the database.

Value:

     The number of changed users (invisibly).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       aa_create_user(conn, "worker", "worker-password", "user")
       aa_set_role(conn, "worker", "viewer")
       aa_get_user(conn, "worker")
       DBI::dbDisconnect(conn)
     }
```

## aa_set_blocked

```text
Block or unblock a user

Description:

     A manual block closes login for the user (both by password and by autologin token)
     without deleting the account, until an administrator lifts it. When blocking, *all
     autologin tokens* of the user are revoked, and a session already open for the user
     is closed at the login module's next check.

Usage:

     aa_set_blocked(
       conn,
       login,
       blocked = TRUE,
       acting_login = NULL,
       settings = aa_settings()
     )

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

 blocked: 'TRUE' to block, 'FALSE' to unblock.

acting_login: Login of the person blocking (the current administrator), or 'NULL' (for
          example, when called from a script).

settings: Settings, the result of 'aa_settings()'.

Details:

     Blocking is performed only if 'aa_check_can_block()' allows it (you cannot block
     yourself or the last active administrator), otherwise an error of class
     'appauth_error_user'. Unblocking needs no checks and does not restore revoked
     tokens; the user has to log in again.

Value:

     The number of changed users (invisibly).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       aa_create_user(conn, "worker", "worker-password", "user")
       aa_set_blocked(conn, "worker", TRUE, acting_login = "boss")
       aa_get_user(conn, "worker")
       aa_set_blocked(conn, "worker", FALSE)
       DBI::dbDisconnect(conn)
     }
```

## aa_delete_user

```text
Delete a user

Description:

     Deletes the user record, *the user's autologin tokens and failed login attempts*.
     This matters: without deleting the tokens, a person who later gets the same login
     could log in with the cookie of the previous owner.

Usage:

     aa_delete_user(conn, login, acting_login = NULL, settings = aa_settings())

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

acting_login: Login of the person blocking (the current administrator), or 'NULL' (for
          example, when called from a script).

settings: Settings, the result of 'aa_settings()'.

Details:

     Deletion is performed only if 'aa_check_can_delete()' allows it (you cannot delete
     yourself or the last active administrator), otherwise an error of class
     'appauth_error_user'. A session open for the user is closed at the login module's
     next check.

Value:

     The number of deleted users (invisibly).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       aa_create_user(conn, "worker", "worker-password", "user")
       aa_delete_user(conn, "worker", acting_login = "boss")
       aa_list_users(conn)
       DBI::dbDisconnect(conn)
     }
```

## aa_check_can_block

```text
Can a user be blocked

Description:

     You cannot block yourself or the last active administrator.

Usage:

     aa_check_can_block(conn, login, acting_login = NULL, settings = aa_settings())

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

acting_login: Login of the person blocking (the current administrator), or 'NULL' (for
          example, when called from a script).

settings: Settings, the result of 'aa_settings()'.

Value:

     'NULL' if allowed, otherwise the reason for refusal (in the settings language).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       aa_check_can_block(conn, "boss", acting_login = "boss")
       DBI::dbDisconnect(conn)
     }
```

## aa_check_can_delete

```text
Can a user be deleted

Description:

     You cannot delete yourself or the last active administrator.

Usage:

     aa_check_can_delete(conn, login, acting_login = NULL, settings = aa_settings())

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

acting_login: Login of the person blocking (the current administrator), or 'NULL' (for
          example, when called from a script).

settings: Settings, the result of 'aa_settings()'.

Value:

     'NULL' if allowed, otherwise the reason for refusal (in the settings language).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       aa_check_can_delete(conn, "boss", acting_login = "boss")
       DBI::dbDisconnect(conn)
     }
```

## aa_check_can_change_role

```text
Can a user's role be changed

Description:

     The role must be in the 'roles' list of the settings, and the administrator role
     cannot be taken from the *last active (not blocked) administrator*, otherwise nobody
     in the app could manage users.

Usage:

     aa_check_can_change_role(conn, login, role, settings = aa_settings())

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

    role: A role from the 'roles' list of the settings.

settings: Settings, the result of 'aa_settings()'.

Value:

     'NULL' if allowed, otherwise the reason for refusal (in the settings language).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       aa_check_can_change_role(conn, "boss", "user")
       DBI::dbDisconnect(conn)
     }
```

