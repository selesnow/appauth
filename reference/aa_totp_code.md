# One-time TOTP code for a point in time

The RFC 6238 algorithm (HMAC-SHA1, 30-second step). Needed in tests and
for comparing with an authenticator app.

## Usage

``` r
aa_totp_code(secret, time = Sys.time(), digits = 6, period = 30)
```

## Arguments

- secret:

  Secret in base32.

- time:

  Point in time (now by default).

- digits:

  Number of digits in the code.

- period:

  Step length, seconds.

## Value

A string of `digits` digits or `NA` if the secret is invalid.

## Examples

``` r
aa_totp_code("JBSWY3DPEHPK3PXP")
#> [1] "832998"
```
