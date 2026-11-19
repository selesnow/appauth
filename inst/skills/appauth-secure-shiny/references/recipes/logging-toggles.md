# Recipe: event logging and log toggles

The package writes nothing to logs itself: it reports events to a single function (a hook). The app decides what to do with them, and can give the administrator toggles for "which logs to keep".

## 1. The hook: package events into the app's log

```r
# R/auth_events.R
log_auth_event <- function(event, user, session_id, value) {
  # write the end of the session while the user is still known
  if (event %in% c("logout", "session_forced_logout") && !identical(user, "anonymous"))
    try(session_log(session_id = session_id, user = user, action = "end"), silent = TRUE)

  func <- AUTH_EVENT_ACTIONS[event]
  if (is.na(func)) return(invisible(NULL))                       # login_success and logout are not written to the action log
  try(write_action_log(user = user, func = unname(func), session_id = session_id,
                       value = auth_event_log_value(event, user, value)), silent = TRUE)
  invisible(NULL)
}
```

The mapping between package events and action names in the log is set by one table: this preserves old names (`User add`, `Login failed`) so reports do not break:

```r
AUTH_EVENT_ACTIONS <- c(
  login_failed = "Login failed", login_locked = "Login locked", login_blocked_user = "Blocked login attempt",
  login_throttled = "Login throttled", login_unlocked = "Login unlock",
  first_admin_created = "User add", user_added = "User add", user_removed = "User remove",
  user_role_changed = "User change role", password_reset = "User password reset",
  password_changed = "Password change", sessions_revoked = "Sessions revoke",
  user_blocked = "User block", user_unblocked = "User unblock",
  session_forced_logout = "Forced logout", access_denied = "Access denied")
```

The package puts clarifications into `value` ("login (role)", "login: role"); for the log we take only the login (`sub(" \\(.*\\)$", "", value)`).

Every package event must be either mapped or deliberately skipped: add a test `all(aa_events()$event %in% c(names(AUTH_EVENT_ACTIONS), c("login_success", "logout", "weak_password_set")))`, it will fire when a new event appears in the package. The `weak_password_set` event (a weak password was accepted, mode `password_policy = "warn"`) can be written to the log (`weak_password_set = "Weak password"`, with "login: reason" in value) or skipped.

### Shorter: aa_event_logger() (package 0.3.0 and newer)

Event selection, renaming, a config toggle and value conversion are done by a ready-made function; what remains for you is the write function. The `log_auth_event` hook above turns into:

```r
log_auth_event <- aa_event_logger(
  function(action, user, session_id, value) {
    try(write_action_log(user = user, func = action, session_id = session_id, value = value), silent = TRUE)
  },
  actions = AUTH_EVENT_ACTIONS,                                     # only the listed events are written, under these names
  format_value = function(event, user, value) auth_event_log_value(event, user, value)
)
```

Write the end of the session on `logout` and `session_forced_logout` as a separate step: wrap the handler in a function `function(event, user, session_id, value) { ...session_log...; handler(event, user, session_id, value) }`. The toggle can be given to the handler itself: `enabled = function(event) isTRUE(conf$logging$action_log)` (the function is called on every event, config changes take effect immediately).

## 2. Log toggles in config.yaml

```yaml
logging:
  session_log: yes
  action_log: yes
  error_log: yes
```

The write functions check the toggle and write only when it is on:

```r
write_action_log <- function(func, user, session_id = "x0", value = NULL) {
  if (isTRUE(conf$logging$action_log)) {
    con <- DBI::dbConnect(RSQLite::SQLite(), conf$database_settings$app_data_base)
    on.exit(DBI::dbDisconnect(con))
    DBI::dbWriteTable(con, "action_log", data.frame(
      datetime = format(Sys.time(), tz = "UTC"), func_name = func, user = user,
      session_id = session_id, value = value %||% NA_character_), append = TRUE)
  }
}
```

The log tables (`action_log`, `session_log`) belong to the app, not the package.

## 3. The toggle editor (the "Access" tab, administrator only)

```r
output$logging_editor <- renderUI(tagList(lapply(names(conf_rv()$logging), function(log_type)
  checkboxInput(ns(paste0("log_", log_type)), log_type, value = isTRUE(conf_rv()$logging[[log_type]])))))

observeEvent(input$save_logging, {
  require_access_admin()
  write_action_log(user = auth$user()$login, func = "Logging config change", session_id)
  new_conf <- conf_rv()
  for (type in names(new_conf$logging)) {
    id <- paste0("log_", type)
    if (!is.null(input[[id]])) new_conf$logging[[type]] <- input[[id]]
  }
  conf_rv(new_conf)
  yaml::write_yaml(new_conf, "config.yaml")
})
```

Also write the change of the toggles themselves to the log (action `Logging config change`).

## 4. The action catalog

If the app shows a log with readable names, keep an `actions` table (id, key, name, tab) and synchronise it at start (missing rows are added, existing ones are not changed). The `key` must match the name in the hook, so when you add an event to `AUTH_EVENT_ACTIONS`, add a row to the catalog (a test for the match: `all(AUTH_EVENT_ACTIONS %in% actions_catalog()$key)`).

## 5. What not to write to the log

Passwords, tokens, cookie values, contents of requests with sensitive data. The package does not pass them into events; do not pass them in your own `write_action_log(value = ...)` calls either.
