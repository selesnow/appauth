# Validate a new user's login

The login must not be empty, must not start or end with whitespace
(login compares the login exactly, so such logins would cause confusion;
the input field in the package UI trims edge whitespace itself) and must
not be longer than `login_max` characters from the settings.

## Usage

``` r
aa_validate_login(login, settings = aa_settings())
```

## Arguments

- login:

  The login to check.

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

## Value

`NULL` if the login is fine, otherwise the error text (in the settings
language).

## Examples

``` r
aa_validate_login("alsey")
#> NULL
aa_validate_login("   ")
#> [1] "Login cannot be empty"
aa_validate_login(" alsey")
#> [1] "Login must not start or end with a space"
```
