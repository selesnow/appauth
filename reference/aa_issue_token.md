# Issue an autologin token

Creates a random token (32 bytes) and stores its hash and expiry
(`session_days` from
[`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md))
in the database. The token itself must be handed to the browser (in a
cookie); it cannot be recovered from the database.

## Usage

``` r
aa_issue_token(conn, login, settings = aa_settings())
```

## Arguments

- conn:

  Database connection.

- login:

  User login.

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

## Value

A string with the token or `NULL`.

## Details

No token is issued (`NULL` is returned) if autologin is disabled in the
settings, the user does not exist or the user is blocked.

## Examples

``` r
if (FALSE) { # \dontrun{
token <- aa_issue_token(conn, "ivan")
if (!is.null(token)) session$sendCustomMessage("setAuthCookie", token)
} # }
```
