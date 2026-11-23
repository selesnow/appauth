# Weak password warning

In the `password_policy = "warn"` mode (the default) a weak password is
accepted, but the user should be told to choose a stronger one: the
built-in modules show this as a notification after a successful password
change. The function is for apps with their own interface. A password is
weak if it is in the
[`aa_common_passwords()`](https://alexey-seleznev.pro/appauth/reference/aa_common_passwords.md)
list, equals the login (case-insensitive) or consists of one repeated
character.

## Usage

``` r
aa_weak_password_warning(password, settings = aa_settings(), login = NULL)
```

## Arguments

- password:

  The accepted password.

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md).

- login:

  User login (optional).

## Value

The warning text (in the settings language), or `NULL` if the mode is
not `"warn"` or there are no weaknesses.

## Examples

``` r
aa_weak_password_warning("123456")
#> [1] "The password was accepted, but it is weak: The password is in the list of common weak passwords. Consider changing it to a stronger one."
aa_weak_password_warning("boss", login = "Boss")
#> [1] "The password was accepted, but it is weak: The password is the same as the login. Consider changing it to a stronger one."
aa_weak_password_warning("long-and-unusual-phrase")
#> NULL
```
