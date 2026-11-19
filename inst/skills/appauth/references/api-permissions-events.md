# appauth reference: Permissions and events

Package version: 0.8.0. This file was generated automatically from the package help pages (`dev/skills/build_reference.R`) and is not edited by hand.

Functions in this section: 
`aa_permissions_from_matrix()`, `aa_can()`, `aa_require()`, `aa_events()`, `aa_event_logger()`

## aa_permissions_from_matrix

```text
Permission provider from a "permission -> roles" matrix

Description:

     Creates a permission source ('provider') for 'aa_can()' and 'aa_require()' from a
     simple scheme: a named list where the name is the permission and the value is the
     roles it is granted to (a vector or a single string).

Usage:

     aa_permissions_from_matrix(matrix)
     
Arguments:

  matrix: A named "permission -> roles" list, or a function without arguments that
          returns such a list.

Details:

     The administrator role does not get permissions automatically: a permission belongs
     only to the roles listed in the matrix.

     If the matrix changes while the application is running (a permission editor), pass a
     function without arguments that returns the current matrix, for example 'function()
     conf_rv()$access_managemet'. Then it is read on every check.

     A permission provider is any function function(user) that returns a vector of the
     user's permission names. If a matrix does not suit you (permissions per user from
     the database, by group), write such a function yourself: the other package functions
     work with it in the same way.

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

     A server-side permission check. Hiding buttons and tabs is not protection, so this
     must be called in every action handler (see 'aa_require()').

Usage:

     aa_can(user, permission, provider)
     
Arguments:

    user: The user: a list with the fields 'login' and 'role', for example 'auth$user()'.
          The role must be taken from the server state, not from 'input'.

permission: The permission name (one non-empty string).

provider: The permission source: a function function(user) that returns a vector of
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

     Called as the first line of a handler. If the permission is present, returns 'TRUE'.
     If not, reports the 'access_denied' event to the 'on_event' hook (the permission name
     in 'value'), shows the user a notification and quietly aborts the handler via
     'shiny::req()'.

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

    auth: The authentication object (a list with the reactive 'user' value, as returned
          by the sign-in module) or the user itself (a list with 'login' and 'role').

permission: The permission name.

provider: The permission source, see 'aa_can()'.

on_event: The event hook function(event, user, session_id, value) or 'NULL'.

settings: Settings, the result of 'aa_settings()' (language of the denial text).

session_id: The session identifier for the hook. By default it is taken from the current
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
Catalog of authentication events

Description:

     The package reports events to the 'on_event(event, user, session_id, value)' hook,
     which is defined by the application (writing to a log, a Telegram notification,
     etc.). The function returns the full list of events the package can send.

Usage:

     aa_events()
     
Details:

     The 'user' field in the hook is the login on whose behalf the event happens (for a
     failed sign-in it is the entered login, and if there is no login, '"anonymous"'),
     'value' holds the detail from the 'value' column. Passwords and tokens never get into
     events.

Value:

     A table with the columns 'event' (key), 'description' (what happened) and 'value'
     (what is in the 'value' field).

Examples:

     aa_events()
     aa_events()$event
```

## aa_event_logger

```text
Ready-made event handler for writing to a log

Description:

     The package reports events to the function 'on_event(event, user, session_id, value)'
     (catalog: 'aa_events()'). This function builds such a handler from the writer
     function 'writer', so that the application does not have to write the same thing
     every time: selecting the needed events, action names for your log, switching
     logging on and off, and transforming the value.

Usage:

     aa_event_logger(
       writer,
       actions = NULL,
       events = NULL,
       enabled = TRUE,
       format_value = NULL
     )
     
Arguments:

  writer: The writer function function(action, user, session_id, value): writes a row to
          your database, file, Telegram, etc. All four arguments are strings.

 actions: A named character vector: the name is the event key from 'aa_events()', the
          value is the action name in your log. If set, only the listed events are
          written. If 'NULL', all events are written, and the action name is the event
          key.

  events: A vector of event keys to write. If 'NULL', all are taken (or those listed in
          'actions').

 enabled: Whether logging is on: 'TRUE', 'FALSE' or a function function(event) that
          decides by event (for example, by switches from a config). The function is
          called on every event, so config changes take effect immediately.

format_value: An optional function function(event, user, value) that returns the value to
          write (for example, keeps only the login in 'value'). By default 'value' is
          written as is.

Details:

     What the handler does on each event:

       1. skips an event that is not in 'events' (if 'events' is set) or that has no name
          in 'actions' (if 'actions' is set);

       2. asks 'enabled': if logging is off, writes nothing;

       3. determines the action name: from 'actions', and if 'actions' is not set, it is
          the event key;

       4. calls 'writer(action, user, session_id, value)', where 'value' has passed
          through 'format_value(event, user, value)' if that function is set.

     An error in 'writer' does not interrupt the package action (the package catches it
     and prints it as a message), so a logging failure does not get in the way of
     sign-in and users' work.

Value:

     A function function(event, user, session_id, value) to pass to 'on_event' of the
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

