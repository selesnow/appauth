# Hash a password

Returns a scrypt hash (`sodium` package) for storing in the database.
The hash contains the salt and parameters, so two calls with the same
password give different strings, and verification is done by
[`aa_verify_password()`](https://alexey-seleznev.pro/appauth/reference/aa_verify_password.md).
The hash is irreversible: the password cannot be recovered from it.

## Usage

``` r
aa_hash_password(password)
```

## Arguments

- password:

  The password, a non-empty string.

## Value

A string with the hash, starting with `$7$`.

## Details

The function does not check password length rules, use
[`aa_validate_password()`](https://alexey-seleznev.pro/appauth/reference/aa_validate_password.md)
for that.

## Examples

``` r
hash <- aa_hash_password("secret-password")
substr(hash, 1, 3)
#> [1] "$7$"
aa_verify_password("secret-password", hash)
#> [1] TRUE
```
