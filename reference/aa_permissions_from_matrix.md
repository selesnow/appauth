# Permission provider from a "permission -\> roles" matrix

Creates a permission provider (`provider`) for
[`aa_can()`](https://alexey-seleznev.pro/appauth/reference/aa_can.md)
and
[`aa_require()`](https://alexey-seleznev.pro/appauth/reference/aa_require.md)
from a named list, where the name is a permission and the value is the
roles that hold it (a vector or a single string).

## Usage

``` r
aa_permissions_from_matrix(matrix)
```

## Arguments

- matrix:

  A named list "permission -\> roles", or a function without arguments
  that returns such a list.

## Value

A function `function(user)`: for a list with a `role` field it returns
the permission names. For an empty or unknown role it returns
`character(0)`.

## Details

The administrator role does not receive permissions automatically: a
permission is held only by the roles listed in the matrix.

If the matrix changes while the app is running (a permission editor),
pass a function without arguments that returns the current matrix, for
example `function() conf_rv()$access_matrix`. It is then read on every
check.

A permission provider is any function `function(user)` that returns a
vector of the user's permission names. If a matrix does not suit you
(per-user permissions from a database, group-based permissions), write
such a function yourself: the other package functions treat it the same
way.

## Examples

``` r
provider <- aa_permissions_from_matrix(list(
  Tasks = c("admin", "user", "viewer"),
  Access = "admin"
))
provider(list(login = "ivan", role = "user"))
#> [1] "Tasks"
aa_can(list(login = "ivan", role = "user"), "Access", provider)
#> [1] FALSE
```
