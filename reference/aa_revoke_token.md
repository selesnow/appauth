# Revoke an autologin token

Needed on logout: the cookie in the browser stops working afterwards.

## Usage

``` r
aa_revoke_token(conn, token)
```

## Arguments

- conn:

  Database connection.

- token:

  Token from the cookie.

## Value

The number of revoked tokens (0 or 1), invisibly.

## Examples

``` r
if (FALSE) { # \dontrun{
aa_revoke_token(conn, input$auth_cookie)
} # }
```
