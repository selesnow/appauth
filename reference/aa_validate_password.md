# Validate a new password against the rules

Checks a password being set for a user (on creation or reset). The rules
come from the settings: minimum and maximum length are counted in
characters, not bytes. The limits apply only to new passwords; existing
passwords are not affected.

## Usage

``` r
aa_validate_password(password, settings = aa_settings(), login = NULL)
```

## Arguments

- password:

  The password to check.

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

- login:

  User login, needed to check whether the password equals the login
  (optional).

## Value

`NULL` if the password is fine, otherwise the error text (in the
settings language).

## Details

If the settings have `password_policy = "reject"`, weak passwords (from
the
[`aa_common_passwords()`](https://alexey-seleznev.pro/appauth/reference/aa_common_passwords.md)
list, equal to the login, one repeated character) are also an error. The
`"warn"` mode does not reject the password: a weak password is reported
by
[`aa_weak_password_warning()`](https://alexey-seleznev.pro/appauth/reference/aa_weak_password_warning.md).

## Examples

``` r
aa_validate_password("abc")
#> [1] "Password must be at least 6 characters long"
aa_validate_password("long-enough-password")
#> NULL
aa_validate_password("long-enough-password", aa_settings(password_min = 30))
#> [1] "Password must be at least 30 characters long"
```
