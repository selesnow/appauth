# Recipe: tab server modules only when the permission is held

If a tab's server part is registered for any session, a forged request from a user without the permission will find its handlers (this is how a CMD tab and a file search once ended up reachable without logging in to one app). So server modules are attached only for those who hold the tab permission. This protects against needless work and against reaching someone else's handlers, but it is not a replacement for `aa_require()` inside the handlers themselves (recipes/handler-guards.md).

## Option 1: `aa_register_module()` for each module

```r
aa_register_module(auth, "Tasks",  provider, function() mod_tasks_server("tasks", auth = auth, conf_rv = conf_rv))
aa_register_module(auth, "Access", provider, function() mod_access_server("access", conn, auth, session$token, conf_rv))
```

`aa_register_module()` calls the function once per session, when the signed-in user gains the permission. Registered modules cannot be removed from a session, so make logout reload the page: `auth$logout(reload = TRUE)`.

## Option 2: a common block after login

When there are many modules and they need shared data, it is convenient to gather the registration into one `observeEvent(auth$logged_in(), ...)`:

```r
observeEvent(auth$logged_in(), {
  req(auth$logged_in())
  can <- function(permission) user_can(auth$user()$role, permission, conf_rv())

  if (can("Tasks"))  mod_tasks_server("tasks", all_tasks, auth, session_id = session$token, conf_rv)
  if (can("Stats"))  mod_stats_server("stats", all_tasks, conf_rv)
  if (can("Logs"))   mod_logs_server("logs", auth, session_id = session$token, conf_rv)
})
```

## Option 3: an administrator-only tab, regardless of the matrix

User and permission management must not be handed out through the matrix: otherwise granting a permission to another role would give it these functions. For such tabs use an "`admin_role` only" provider:

```r
# R/access.R
admin_only_provider <- function(user) {
  if (identical(user$role, auth_settings$admin_role)) "Access" else character(0)
}

aa_register_module(auth, "Access", admin_only_provider, function() {
  mod_access_server("access", conn, auth, session$token, conf_rv)
})
```

Inside the module, `aa_users_server()` in any case checks the administrator role on the server and compares it with the database on every action.

## Tab UI

We show tabs by permission (`user_can(...)`) in `renderUI`, but that is only a convenience. Example:

```r
output$app_ui <- renderUI({
  req(auth$logged_in())
  user <- auth$user()
  tabs <- list(
    if (user_can(user$role, "Tasks", conf_rv())) mod_tasks_ui("tasks"),
    if (identical(user$role, auth_settings$admin_role)) tabPanel("Access", mod_access_ui("access"))
  )
  do.call(tabsetPanel, Filter(Negate(is.null), tabs))
})
```

## Common mistakes

* A tab's server part is registered in `server` unconditionally: before login and for all roles.
* The module is registered by `input$role` rather than by `auth$user()$role`.
* Registration is done, but the module's handlers have no `aa_require()`: a user with the tab permission gets all of its actions, even if their role has no permission for a specific action (for example separate permissions such as `Run tasks`, `View code`, etc.).
* If the provider fails with an error (for example `auth_settings` is not visible), the permission is considered absent and the tab stays empty; look in the console for the package message `appauth: источник прав завершился ошибкой` (the permission source failed with an error).

## Verification

In an app test under the administrator role, check that the server part is registered: after login `output[["access-users-main"]]$html` contains the users table. A test that does not open the tabs as the administrator will miss an empty tab.
