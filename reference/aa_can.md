# Does the user have a permission

Server-side permission check. Hiding buttons and tabs is not protection,
so call this in every action handler (see
[`aa_require()`](https://alexey-seleznev.pro/appauth/reference/aa_require.md)).

## Usage

``` r
aa_can(user, permission, provider)
```

## Arguments

- user:

  The user: a list with `login` and `role` fields, for example
  `auth$user()`. Take the role from server-side state, not from `input`.

- permission:

  Permission name (a single non-empty string).

- provider:

  Permission provider: a function `function(user)` that returns a vector
  of permission names, for example the result of
  [`aa_permissions_from_matrix()`](https://alexey-seleznev.pro/appauth/reference/aa_permissions_from_matrix.md).

## Value

`TRUE` or `FALSE`.

## Details

The check is closed by default: any uncertainty (no user, the permission
is not a string, the provider returned garbage or failed with an error)
gives `FALSE`.

## Examples

``` r
provider <- aa_permissions_from_matrix(list(Access = "admin"))
aa_can(list(login = "root", role = "admin"), "Access", provider)
#> [1] TRUE
aa_can(list(login = "ivan", role = "user"), "Access", provider)
#> [1] FALSE
aa_can(NULL, "Access", provider)
#> [1] FALSE
```
