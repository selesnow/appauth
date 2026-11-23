# Get a text by key

Returns a string from a set of texts. If values are passed, they are
substituted into the string following the rules of
[`sprintf()`](https://rdrr.io/r/base/sprintf.html).

## Usage

``` r
aa_text(x, key, ...)
```

## Arguments

- x:

  A set of texts (result of
  [`aa_texts()`](https://alexey-seleznev.pro/appauth/reference/aa_texts.md))
  or settings (result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md)).

- key:

  Text key, see
  [`aa_text_keys()`](https://alexey-seleznev.pro/appauth/reference/aa_text_keys.md).

- ...:

  Values for the `%d` and `%s` placeholders.

## Value

A string.

## Examples

``` r
texts <- aa_texts("en")
aa_text(texts, "login_button")
#> [1] "Sign in"
aa_text(texts, "locked", 15)
#> [1] "Too many failed sign-in attempts. Try again in 15 min."
```
