# Is the value a password hash

Distinguishes a hash created by
[`aa_hash_password()`](https://alexey-seleznev.pro/appauth/reference/aa_hash_password.md)
from a plain-text password. The function is vectorized; `NA` is not
considered a hash.

## Usage

``` r
aa_is_password_hash(x)
```

## Arguments

- x:

  A character vector, for example the `password` column of the `users`
  table.

## Value

A logical vector of the same length.

## Examples

``` r
aa_is_password_hash(c(aa_hash_password("secret"), "root", NA))
#> [1]  TRUE FALSE FALSE
```
