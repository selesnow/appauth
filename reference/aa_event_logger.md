# Ready-made event handler for writing to a log

The package reports events to the function
`on_event(event, user, session_id, value)` (catalog:
[`aa_events()`](https://alexey-seleznev.pro/appauth/reference/aa_events.md)).
This function builds such a handler from a `writer` function, so that
the application does not have to write the same code every time:
selecting the events needed, action names for your log, switching
writing on and off, and transforming the value.

## Usage

``` r
aa_event_logger(
  writer,
  actions = NULL,
  events = NULL,
  enabled = TRUE,
  format_value = NULL
)
```

## Arguments

- writer:

  Writer function `function(action, user, session_id, value)`: writes a
  row to your database, file, messenger, etc. All four arguments are
  strings.

- actions:

  A named character vector: the name is an event key from
  [`aa_events()`](https://alexey-seleznev.pro/appauth/reference/aa_events.md),
  the value is the action name in your log. If set, only the listed
  events are written. If `NULL`, all events are written and the event
  key serves as the action name.

- events:

  A vector of event keys to write. If `NULL`, all are taken (or those
  listed in `actions`).

- enabled:

  Whether writing is on: `TRUE`, `FALSE` or a function `function(event)`
  that decides by event (for example, by switches from a config). The
  function is called on every event, so config changes take effect
  immediately.

- format_value:

  An optional function `function(event, user, value)` that returns the
  value to write (for example, keeps only the login in `value`). By
  default `value` is written as is.

## Value

A function `function(event, user, session_id, value)` to pass as
`on_event` to the package modules.

## Details

What the handler does for each event:

1.  skips the event if it is not in `events` (when `events` is set) or
    has no name in `actions` (when `actions` is set);

2.  asks `enabled`: if writing is off, writes nothing;

3.  determines the action name: from `actions`, and if `actions` is not
    set, it is the event key;

4.  calls `writer(action, user, session_id, value)`, where `value` has
    passed through `format_value(event, user, value)` if that function
    is set.

An error in `writer` does not interrupt a package action (the package
catches it and prints a message), so a logging failure does not get in
the way of sign-in and of users' work.

## Examples

``` r
# all events into memory
rows <- list()
handler <- aa_event_logger(function(action, user, session_id, value) {
  rows[[length(rows) + 1]] <<- c(action = action, user = user, value = value)
})
handler("login_failed", "boss", "s1", "")
length(rows)
#> [1] 1

# only selected events with their own action names and a switch
log_on <- TRUE
handler <- aa_event_logger(
  function(action, user, session_id, value) message(action, " ", user),
  actions = c(login_failed = "Login failed", user_added = "User add"),
  enabled = function(event) log_on
)
handler("login_failed", "boss", "s1", "")
#> Login failed boss
handler("logout", "boss", "s1", "")
```
