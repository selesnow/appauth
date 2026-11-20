# Own password change module: UI

A form with "current password, new password, confirmation". Shown only
to a signed-in user. Place it wherever the app has an account page or
settings (in a tab or a modal window). Styles are attached through
[`aa_app_head()`](https://alexey-seleznev.pro/appauth/reference/aa_app_head.md).

## Usage

``` r
aa_password_ui(id)
```

## Arguments

- id:

  Module id.

## Value

A Shiny UI element.

## See also

[`aa_password_server()`](https://alexey-seleznev.pro/appauth/reference/aa_password_server.md)

## Examples

``` r
ui <- shiny::fluidPage(aa_app_head(), aa_password_ui("password"))
```
