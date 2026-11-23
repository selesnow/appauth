# Random secret for an authenticator app

Random secret for an authenticator app

## Usage

``` r
aa_totp_secret()
```

## Value

A base32 string of 32 characters (160 bits), the way it is entered into
the app manually.

## Examples

``` r
nchar(aa_totp_secret())
#> [1] 32
```
