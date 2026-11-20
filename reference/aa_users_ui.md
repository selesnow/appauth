# Users module: UI

A table of users with statuses and an add button. Double-clicking a row
opens the user card. The module is visible only to an administrator and
shows nothing to anyone else. Styles are attached through
[`aa_app_head()`](https://alexey-seleznev.pro/appauth/reference/aa_app_head.md).

## Usage

``` r
aa_users_ui(id)
```

## Arguments

- id:

  Module id.

## Value

A Shiny UI element.

## Details

The rest of the "Access" tab content (permissions editor, log switches)
is assembled by the app, for example
`tabPanel("Access", aa_users_ui("users"), my_permissions_editor())`.

## See also

[`aa_users_server()`](https://alexey-seleznev.pro/appauth/reference/aa_users_server.md)

## Examples

``` r
ui <- shiny::fluidPage(aa_app_head(), aa_users_ui("users"))
```
