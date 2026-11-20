# Interface and message texts

Returns the set of texts for the chosen language. Any string can be
replaced with your own by passing its key and the new value. Texts with
substituted values contain `%d` (number) and `%s` (string) placeholders,
the values are filled in by
[`aa_text()`](https://alexey-seleznev.pro/appauth/reference/aa_text.md).

## Usage

``` r
aa_texts(lang = c("en", "ru"), ...)
```

## Arguments

- lang:

  Language of the texts: `"en"` (default) or `"ru"`.

- ...:

  Your own texts as `key = "string"`, they replace the default ones.

## Value

A named list of strings of class `aa_texts`.

## Details

Available keys are listed by
[`aa_text_keys()`](https://alexey-seleznev.pro/appauth/reference/aa_text_keys.md).

## Examples

``` r
# English texts (default)
texts <- aa_texts()

# English texts with a custom sign-in button label
texts <- aa_texts("en", login_button = "Log in")
texts$login_button
#> [1] "Log in"

# Russian texts
texts <- aa_texts("ru")
```
