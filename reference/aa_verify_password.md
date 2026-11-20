# Verify a password against a hash

Compares the entered password with the stored hash. If the stored value
is not a hash (for example, a plain-text password), the result is always
`FALSE`: plain-text passwords are not compared. A corrupted hash and
invalid arguments also give `FALSE`; the function does not throw errors.

## Usage

``` r
aa_verify_password(password, stored)
```

## Arguments

- password:

  The entered password.

- stored:

  The value from the `password` column of the `users` table.

## Value

`TRUE` or `FALSE`.

## Examples

``` r
hash <- aa_hash_password("secret")
aa_verify_password("secret", hash)
#> [1] TRUE
aa_verify_password("other", hash)
#> [1] FALSE

# a plain-text password does not pass verification, even if it matches
aa_verify_password("root", "root")
#> [1] FALSE
```
