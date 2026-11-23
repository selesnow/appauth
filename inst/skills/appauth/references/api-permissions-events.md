# appauth reference: Permissions and events

Package version: 0.11.1. This file is generated automatically from the package help (`dev/skills/build_reference.R`) and must not be edited by hand.

Functions in this section:
`aa_permissions_from_matrix()`, `aa_can()`, `aa_require()`, `aa_events()`, `aa_event_logger()`

## Contents

- [aa_permissions_from_matrix](#aa_permissions_from_matrix)
- [aa_can](#aa_can)
- [aa_require](#aa_require)
- [aa_events](#aa_events)
- [aa_event_logger](#aa_event_logger)

## aa_permissions_from_matrix

```text
Permission provider from a "permission -> roles" matrix

Description:

     Creates a permission provider ('provider') for 'aa_can()' and 'aa_require()' from a
     named list, where the name is a permission and the value is the roles that hold it
     (a vector or a single string).

Usage:

     aa_permissions_from_matrix(matrix)

Arguments:

  matrix: A named list "permission -> roles", or a function without arguments that
          returns such a list.

Details:

     The administrator role does not receive permissions automatically: a permission is
     held only by the roles listed in the matrix.

     If the matrix changes while the app is running (a permission editor), pass a
     function without arguments that returns the current matrix, for example 'function()
     conf_rv()$access_matrix'. It is then read on every check.

     A permission provider is any function function(user) that returns a vector of the
     user's permission names. If a matrix does not suit you (per-user permissions from a
     database, group-based permissions), write such a function yourself: the other
     package functions treat it the same way.

Value:

     A function function(user): for a list with a 'role' field it returns the permission
     names. For an empty or unknown role it returns 'character(0)'.

Examples:

     provider <- aa_permissions_from_matrix(list(
       Tasks = c("admin", "user", "viewer"),
       Access = "admin"
     ))
     provider(list(login = "ivan", role = "user"))
     aa_can(list(login = "ivan", role = "user"), "Access", provider)
```

## aa_can

```text
Does the user have a permission

Description:

     Server-side permission check. Hiding buttons and tabs is not protection, so call
     this in every action handler (see 'aa_require()').

Usage:

     aa_can(user, permission, provider)

Arguments:

    user: The user: a list with 'login' and 'role' fields, for example 'auth$user()'.
          Take the role from server-side state, not from 'input'.

permission: Permission name (a single non-empty string).

provider: Permission provider: a function function(user) that returns a vector of
          permission names, for example the result of 'aa_permissions_from_matrix()'.

Details:

     The check is closed by default: any uncertainty (no user, the permission is not a
     string, the provider returned garbage or failed with an error) gives 'FALSE'.

Value:

     'TRUE' or 'FALSE'.

Examples:

     provider <- aa_permissions_from_matrix(list(Access = "admin"))
     aa_can(list(login = "root", role = "admin"), "Access", provider)
     aa_can(list(login = "ivan", role = "user"), "Access", provider)
     aa_can(NULL, "Access", provider)
```

## aa_require

```text
Require a permission in an action handler

Description:

     Call it on the first line of a handler. If the user has the permission, it returns
     'TRUE'. If not, it reports an 'access_denied' event to the 'on_event' hook (the
     permission name goes into 'value'), shows the user a notification and quietly aborts
     the handler through 'shiny::req()'.

Usage:

     aa_require(
       auth,
       permission,
       provider,
       on_event = NULL,
       settings = aa_settings(),
       session_id = NULL
     )

Arguments:

    auth: The authorization object (a list with a reactive 'user' value, as returned by
          the login module) or the user itself (a list with 'login' and 'role').

permission: Permission name.

provider: Permission provider, see 'aa_can()'.

on_event: Event hook function(event, user, session_id, value) or 'NULL'.

settings: Settings, the result of 'aa_settings()' (language of the denial text).

session_id: Session identifier for the hook. By default it is taken from the current
          Shiny session.

Value:

     Invisibly 'TRUE'. If the permission is missing, aborts the handler.

Examples:

     ## Not run:

     observeEvent(input$run_task, {
       aa_require(auth, "Run", provider, on_event = log_event)
       # ... the action ...
     })
     ## End(Not run)
```

## aa_events

```text
Catalog of authorization events

Description:

     The package reports events to the 'on_event(event, user, session_id, value)' hook
     defined by the application (writing to a log, a messenger notification, etc.). This
     function returns the full list of events the package can send.

Usage:

     aa_events(lang = c("en", "ru"))

Arguments:

    lang: Language of the 'description' and 'value' columns: '"en"' (default) or '"ru"'.

Details:

     The 'user' field in the hook is the login on whose behalf the event happens (for a
     failed sign-in it is the entered login, and if there is no login, '"anonymous"'),
     and 'value' holds the detail described in the 'value' column. Passwords and tokens
     never appear in events.

Value:

     A data frame with columns 'event' (key), 'description' (what happened) and 'value'
     (what is in the 'value' field).

Examples:

     aa_events()
     aa_events()$event
```

## aa_event_logger

```text
Ready-made event handler for writing to a log

Description:

     The package reports events to the function 'on_event(event, user, session_id,
     value)' (catalog: 'aa_events()'). This function builds such a handler from a
     'writer' function, so that the application does not have to write the same code
     every time: selecting the events needed, action names for your log, switching
     writing on and off, and transforming the value.

Usage:

     aa_event_logger(
       writer,
       actions = NULL,
       events = NULL,
       enabled = TRUE,
       format_value = NULL
     )

Arguments:

  writer: Writer function function(action, user, session_id, value): writes a row to your
          database, file, messenger, etc. All four arguments are strings.

 actions: A named character vector: the name is an event key from 'aa_events()', the
          value is the action name in your log. If set, only the listed events are
          written. If 'NULL', all events are written and the event key serves as the
          action name.

  events: A vector of event keys to write. If 'NULL', all are taken (or those listed in
          'actions').

 enabled: Whether writing is on: 'TRUE', 'FALSE' or a function function(event) that
          decides by event (for example, by switches from a config). The function is
          called on every event, so config changes take effect immediately.

format_value: An optional function function(event, user, value) that returns the value to
          write (for example, keeps only the login in 'value'). By default 'value' is
          written as is.

Details:

     What the handler does for each event:

       1. skips the event if it is not in 'events' (when 'events' is set) or has no name
          in 'actions' (when 'actions' is set);

       2. asks 'enabled': if writing is off, writes nothing;

       3. determines the action name: from 'actions', and if 'actions' is not set, it is
          the event key;

       4. calls 'writer(action, user, session_id, value)', where 'value' has passed
          through 'format_value(event, user, value)' if that function is set.

     An error in 'writer' does not interrupt a package action (the package catches it and
     prints a message), so a logging failure does not get in the way of sign-in and of
     users' work.

Value:

     A function function(event, user, session_id, value) to pass as 'on_event' to the
     package modules.

Examples:

     # all events into memory
     rows <- list()
     handler <- aa_event_logger(function(action, user, session_id, value) {
       rows[[length(rows) + 1]] <<- c(action = action, user = user, value = value)
     })
     handler("login_failed", "boss", "s1", "")
     length(rows)

     # only selected events with their own action names and a switch
     log_on <- TRUE
     handler <- aa_event_logger(
       function(action, user, session_id, value) message(action, " ", user),
       actions = c(login_failed = "Login failed", user_added = "User add"),
       enabled = function(event) log_on
     )
     handler("login_failed", "boss", "s1", "")
     handler("logout", "boss", "s1", "")
```

