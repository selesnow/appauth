# Attach appauth styles and scripts

Call it once in the application UI (inside
[`fluidPage()`](https://rdrr.io/pkg/shiny/man/fluidPage.html) or
[`tagList()`](https://rstudio.github.io/htmltools/reference/tagList.html)).
Adds the CSS of the sign-in form and the users tab, and the JS that
reads, writes and deletes the auto sign-in cookie.

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

The cookie is written with `SameSite=Lax`, and on HTTPS also with
`Secure`.

## Examples

``` r
ui <- shiny::fluidPage(
  aa_app_head()
  # ... the rest of the application UI
)
```
