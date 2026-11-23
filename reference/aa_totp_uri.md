# otpauth link for an authenticator app

The QR code is built from this link, and apps also understand it on
manual entry.

## Usage

``` r
aa_totp_uri(secret, login, issuer = "appauth")
```

## Arguments

- secret:

  Secret in base32.

- login:

  User login.

- issuer:

  Service name the app will show.

## Value

A string like `otpauth://totp/...`.

## Examples

``` r
aa_totp_uri("JBSWY3DPEHPK3PXP", "ivan", "Reports portal")
#> [1] "otpauth://totp/Reports%20portal:ivan?secret=JBSWY3DPEHPK3PXP&issuer=Reports%20portal&algorithm=SHA1&digits=6&period=30"
```
