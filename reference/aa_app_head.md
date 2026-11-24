# Attach appauth styles and scripts

Call it once in the application UI (inside
[`fluidPage()`](https://rdrr.io/pkg/shiny/man/fluidPage.html) or
[`tagList()`](https://rstudio.github.io/htmltools/reference/tagList.html)).
Adds the CSS of the sign-in form and the users tab, and the JS that
handles the server-side auto sign-in cookie tickets (plus legacy cookie
handlers).

## Usage

``` r
aa_app_head()
```

## Value

A `shiny.tag.list` object that attaches the `appauth` dependency.

## Details

The look is changed with `--aa-*` CSS variables (for example
`--aa-primary`), which you override in your own CSS after
`aa_app_head()`. The light theme is enabled with the `aa-theme-light`
class on `<body>` or a parent element.

With `cookie_mode = "httponly"` the cookie is written by the server with
`HttpOnly`, `SameSite=Lax` and `Secure` on HTTPS. The legacy mode uses
the same flags except for `HttpOnly`.

## Examples

``` r
ui <- shiny::fluidPage(
  aa_app_head()
  # ... the rest of the application UI
)
```
