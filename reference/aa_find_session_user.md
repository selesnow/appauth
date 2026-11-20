# Find a user by autologin token

Returns the user only if the token exists, is not revoked and has not
expired, and the user exists, is not blocked and is not required to
change the password (after a password change the user must log in
again). The role is taken from the database at the time of the check.

## Usage

``` r
aa_find_session_user(conn, token)
```

## Arguments

- conn:

  Database connection.

- token:

  Token from the cookie.

## Value

A list with `login` and `role` fields, or `NULL`.

## Examples

``` r
if (FALSE) { # \dontrun{
user <- aa_find_session_user(conn, input$auth_cookie)
if (!is.null(user)) {
  # the user logs in without a password
}
} # }
```
