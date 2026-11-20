# Require a permission in an action handler

Call it on the first line of a handler. If the user has the permission,
it returns `TRUE`. If not, it reports an `access_denied` event to the
`on_event` hook (the permission name goes into `value`), shows the user
a notification and quietly aborts the handler through
[`shiny::req()`](https://rdrr.io/pkg/shiny/man/req.html).

## Usage

``` r
aa_require(
  auth,
  permission,
  provider,
  on_event = NULL,
  settings = aa_settings(),
  session_id = NULL
)
```

## Arguments

- auth:

  The authorization object (a list with a reactive `user` value, as
  returned by the login module) or the user itself (a list with `login`
  and `role`).

- permission:

  Permission name.

- provider:

  Permission provider, see
  [`aa_can()`](https://alexey-seleznev.pro/appauth/reference/aa_can.md).

- on_event:

  Event hook `function(event, user, session_id, value)` or `NULL`.

- settings:

  Settings, the result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md)
  (language of the denial text).

- session_id:

  Session identifier for the hook. By default it is taken from the
  current Shiny session.

## Value

Invisibly `TRUE`. If the permission is missing, aborts the handler.

## Examples

``` r
if (FALSE) { # \dontrun{
observeEvent(input$run_task, {
  aa_require(auth, "Run", provider, on_event = log_event)
  # ... the action ...
})
} # }
```
