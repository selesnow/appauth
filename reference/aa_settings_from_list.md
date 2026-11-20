# Settings from a list (for example, from a `config.yaml` section)

Convenient when the protection settings are kept in the application
config. Only known parameters of
[`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md)
are taken, the rest are ignored, and any parameter can be overridden
with the `...` arguments.

## Usage

``` r
aa_settings_from_list(x = NULL, ...)
```

## Arguments

- x:

  A list of settings, for example
  `yaml::read_yaml("config.yaml")$security`, or `NULL`.

- ...:

  Parameters of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md)
  that replace the values from `x`.

## Value

A list of settings of class `aa_settings`.

## Examples

``` r
security <- list(max_failed_logins = 3, lockout_minutes = 10, unknown_key =
1)
settings <- aa_settings_from_list(security, texts = aa_texts("en"))
settings$max_failed_logins
#> [1] 3
```
