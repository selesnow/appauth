# Check that an open session is still valid

Called periodically (every `session_check_seconds`) so that blocking,
deletion, role demotion and session termination take effect for a user
who is already logged in, not only at the next login. A session is
invalid if the user was deleted or blocked, the role in the database
differs from the role in the session, or the token of this session was
revoked (password reset, "end all sessions").

## Usage

``` r
aa_user_session_valid(conn, login, role, token = NULL)
```

## Arguments

- conn:

  Database connection.

- login:

  User login.

- role:

  The role the user logged in with.

- token:

  Autologin token of this session (`auth$token()`) or `NULL` if the
  session has no token (for example, autologin is disabled): then the
  token is not checked.

## Value

A list: `valid` (logical), `reason` (`"ok"`, `"deleted"`, `"blocked"`,
`"role_changed"`, `"token_revoked"`, `"check_failed"`) and `role` (the
current role from the database or `NULL`).

## Details

If the database cannot be read, the session is considered valid
(`reason = "check_failed"`) so that a database failure does not kick out
all users; access is not widened, because no password is checked.

## Examples

``` r
if (FALSE) { # \dontrun{
check <- aa_user_session_valid(conn, auth$user()$login, auth$user()$role,
auth$token())
if (!check$valid) auth$logout(reason = check$reason)
} # }
```
