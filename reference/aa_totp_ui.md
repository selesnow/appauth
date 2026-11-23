# Two-factor authentication module: UI

A block for the account page: the two-factor authentication status,
enabling (secret, QR code and confirmation with a code) and disabling.
Shows nothing until `totp_enabled` is set in the settings. Styles are
attached through
[`aa_app_head()`](https://alexey-seleznev.pro/appauth/reference/aa_app_head.md).

## Usage

``` r
aa_totp_ui(id)
```

## Arguments

- id:

  Module id.

## Value

A Shiny UI element.

## See also

[`aa_totp_server()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_server.md)

## Examples

``` r
ui <- shiny::fluidPage(aa_app_head(), aa_totp_ui("totp"))
```
