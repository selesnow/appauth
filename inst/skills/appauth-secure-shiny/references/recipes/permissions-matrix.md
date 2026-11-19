# Recipe: the "permission -> roles" matrix and a role permission editor

The package does not know your permissions and does not store a matrix: that is part of the app. The matrix lives in `config.yaml`, the permission source for the package is built from it, and the permission editor changes the file and the reactive value holding the config.

## 1. The matrix in config.yaml

```yaml
access_matrix:            # permission -> roles (a vector or a single string)
  Tasks: [admin, user, viewer]
  Run: [admin, user]
  Access: admin
```

A permission can be named anything (`Tasks`, `Run`); what matters is that the names in the matrix and in the code match.

## 2. The permission source and wrappers with clear names

A config that can be changed on the fly is kept in a `reactiveVal` (`conf_rv`), and the matrix is read by a function on every check:

```r
# R/access.R
conf_permissions <- function(conf_rv) {
  aa_permissions_from_matrix(function() conf_rv()$access_matrix)
}

# a wrapper with a stable signature: calls in modules stay short
require_permission <- function(auth, conf_rv, permission, session_id = "x0") {
  aa_require(auth, permission, conf_permissions(conf_rv),
             on_event = log_auth_event, settings = auth_settings, session_id = session_id)
}

user_can <- function(role, permission, conf) {
  aa_can(list(login = "", role = role), permission,
         aa_permissions_from_matrix(conf$access_matrix %||% list()))
}
```

`auth_settings` and `log_auth_event` must be visible to functions from `R/`: create `auth_settings` globally (`<<-`) if `app.R` is loaded through `runApp` (see SKILL.md, the environment mistake).

### Custom roles

Roles and the administrator role are set in the settings: with `security: {roles: [owner, editor, viewer], admin_role: owner}` in `config.yaml` read by `aa_settings_from_list(conf$security)`, or directly with `aa_settings(roles = ..., admin_role = ...)`. Use the same role names in the matrix. **`settings` must be passed to all user functions** (`aa_create_user(con, ..., settings)`, `aa_create_first_admin()`, `aa_set_role()`) and to tests, otherwise roles are validated against the defaults (`admin`, `user`, `viewer`) and custom roles are rejected as "Invalid role".

## 3. Tabs by permission

```r
tabs <- list(
  if (user_can(user$role, "Tasks", conf_rv())) mod_tasks_ui("tasks"),
  if (user_can(user$role, "Access", conf_rv())) tabPanel("Access", mod_access_ui("access"))
)
```

Register the server parts of tabs only when the permission is held: recipes/role-gated-modules.md. Permissions inside handlers: recipes/handler-guards.md.

## 4. The role permission editor (the "Access" tab, administrator only)

The interface is built from the matrix, and roles are taken from the settings (`auth_settings$roles`) rather than hard-coded:

```r
output$role_editor <- renderUI({
  tab_nodes <- conf_rv()$access_matrix
  nodes <- names(tab_nodes)
  rows <- split(nodes, ceiling(seq_along(nodes) / 4))            # 4 permissions per row
  tagList(lapply(rows, function(row_nodes) fluidRow(lapply(row_nodes, function(node) column(
    3, selectInput(ns(paste0("roles_", node)), label = node,
                   choices = auth_settings$roles, selected = tab_nodes[[node]], multiple = TRUE))))))
})

observeEvent(input$save_roles, {
  require_access_admin()                                          # see below
  new_conf <- conf_rv()
  for (node in names(new_conf$access_matrix)) {
    id <- paste0("roles_", node)
    if (!is.null(input[[id]])) new_conf$access_matrix[[node]] <- input[[id]]
  }
  conf_rv(new_conf)                                               # takes effect immediately, no restart
  yaml::write_yaml(new_conf, "config.yaml")
  showNotification("Role permissions updated", type = "message")
})
```

Protecting the editor so that nobody can raise their own privileges:

```r
require_access_admin <- function() {
  require_permission(auth, conf_rv, "Access", session_id)         # the tab permission from the matrix
  if (!identical(auth$user()$role, auth_settings$admin_role)) {   # AND the administrator role, regardless of the matrix
    showNotification("Insufficient permissions for this action", type = "error"); req(FALSE)
  }
}
```

This way, granting the `Access` permission to another role does not let it manage users and permissions. Register the editor's server part for `admin_role` (recipes/role-gated-modules.md, the "administrator only" provider).

## 5. If a matrix does not fit

Per-user permissions from the database, by group, from an external system: write a `function(user)` that returns a vector of permission names and pass it everywhere instead of `aa_permissions_from_matrix()`. A ready-made example with a `user_permissions` table and a slot in the card for granting permissions: `system.file("examples/custom-permissions-app/app.R", package = "appauth")`.

## 6. Tests

```r
provider <- aa_permissions_from_matrix(list(Run = c("admin", "user"), Access = "admin"))
expect_true(aa_can(list(login = "a", role = "user"), "Run", provider))
expect_false(aa_can(list(login = "a", role = "viewer"), "Run", provider))
expect_false(aa_can(list(login = "a", role = "admin"), "No such permission", provider))
```

Additionally check that all permissions the code uses are present in the config defaults (otherwise in a fresh installation the permission disappears for everyone, as a "Code" button once did in one app): the test collects names from `user_can(...)`, `require_permission(...)` and `access_matrix$...` and compares them with `default_config()`.
