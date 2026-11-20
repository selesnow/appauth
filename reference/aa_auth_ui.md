# Sign-in module: UI

The sign-in form (or the creation of the first administrator if there
are no users yet). When the user is signed in, the module shows nothing.
Styles are attached through
[`aa_app_head()`](https://alexey-seleznev.pro/appauth/reference/aa_app_head.md).

## Usage

``` r
aa_auth_ui(id)
```

## Arguments

- id:

  Module id.

## Value

A Shiny UI element.

## See also

[`aa_auth_server()`](https://alexey-seleznev.pro/appauth/reference/aa_auth_server.md)

## Examples

``` r
ui <- shiny::fluidPage(aa_app_head(), aa_auth_ui("auth"))
```
