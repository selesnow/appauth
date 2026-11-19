# Recipe: per-user permissions from the database (instead of a matrix)

When permissions do not boil down to "role -> set of permissions" (each person has their own set: reports, export, projects), the permission source is a `function(user)` that reads a database table. The other package functions (`aa_can()`, `aa_require()`, `aa_register_module()`) work with it the same way as with a matrix. A complete ready-made sample: `assets/app-skeleton-db-permissions/` (an app, a lightweight test, a README). A live package example: `system.file("examples/custom-permissions-app/app.R", package = "appauth")`.

In this case you do NOT need a `config.yaml` with a matrix, `create_config.R`, a role permission editor or `ensure_log_tables()`: permissions are edited in the user card.

## 1. Roles and settings (own roles, permanent password)

```r
auth_settings <<- aa_settings(
  roles = c("owner", "editor", "viewer"),
  admin_role = "owner",
  must_change_default = FALSE,        # a password set by the owner is permanent
  texts = aa_texts("en")
)
```

**`settings` must be passed to the user functions and to tests**: `aa_create_user(con, "ed", "pass", "editor", auth_settings)`, `aa_create_first_admin(con, ..., auth_settings)`, `aa_set_role(con, ..., auth_settings)`. A role is validated against `settings$roles`, and without `settings` custom roles produce "Invalid role".

Settings can also be kept in `config.yaml` (`security: {roles: [...], admin_role: owner}`) and read with `aa_settings_from_list()`: the keys `roles` and `admin_role` are allowed in the list.

## 2. The permissions table: created at app START, not in a session

```r
ensure_permissions_table <- function(con) {
  DBI::dbExecute(con, "CREATE TABLE IF NOT EXISTS user_permissions (
    login TEXT NOT NULL, permission TEXT NOT NULL, PRIMARY KEY (login, permission))")
}

prepare_app_db <- function(path, settings) {          # once at process start (app.R)
  con <- DBI::dbConnect(RSQLite::SQLite(), path); on.exit(DBI::dbDisconnect(con))
  aa_prepare_db(con, settings)
  ensure_permissions_table(con)
}
```

The table belongs to the app, not the package, and lives next to the `appauth` tables.

## 3. The permission source

```r
APP_PERMISSIONS <- c("reports", "export")

make_permission_provider <- function(conn, settings) {
  function(user) {
    if (identical(user$role, settings$admin_role)) return(c(APP_PERMISSIONS, "users"))   # the owner: all permissions and user management
    if (is.null(user$login) || !nzchar(user$login)) return(character(0))
    intersect(DBI::dbGetQuery(conn, "SELECT permission FROM user_permissions WHERE login = ?",
                              params = list(user$login))$permission, APP_PERMISSIONS)
  }
}
```

`intersect(..., APP_PERMISSIONS)` drops unknown permissions from the database. The query is parameterised (a login with quotes is safe). If the provider fails, `aa_can()` returns `FALSE` (closed by default).

## 4. Tabs and registration

```r
provider <- make_permission_provider(conn, auth_settings)

# the user management tab: the server part only with the "users" permission (the owner)
aa_register_module(auth, "users", provider, function() {
  aa_users_server("users", conn, auth, auth_settings, on_event = log_auth_event,
                  extra_card_ui = card_ui, extra_card_server = card_server)
})

# tabs by permission
if (aa_can(user, "reports", provider)) tabPanel("Reports", ...)
if (aa_can(user, "users", provider)) tabPanel("Users", aa_users_ui("users"))

# an action: the permission in the handler itself
observeEvent(input$export, {
  aa_require(auth, "export", provider, on_event = log_auth_event, settings = auth_settings)
  ...
})
```

## 5. The card slot: a "Permissions" block (granting permissions by the owner)

The slot handlers are factored into factories in `R/auth_setup.R` (`make_card_ui(conn)`, `make_card_server(conn, auth)`), so that a test can substitute a non-owner role:

```r
make_card_ui <- function(conn) function(login, ns) div(class = "aa-card-section", h5("Permissions"),
  checkboxGroupInput(ns("permissions"), NULL, choices = APP_PERMISSIONS, selected = user_permissions_of(conn, login)),
  actionButton(ns("save_permissions"), "Save permissions", class = "btn btn-primary btn-sm"))

make_card_server <- function(conn, auth) function(input, output, session, login) {
  observeEvent(input$save_permissions, {
    user <- isolate(auth$user())
    req(identical(user$role, auth_settings$admin_role), login())     # the role from server state, not from input
    save_user_permissions(conn, login(), input$permissions)          # inside: the user exists, intersect with APP_PERMISSIONS, a transaction
    log_auth_event("permissions_changed", user$login, session$token, login())
  })
}
```

In `server`: `aa_users_server(..., extra_card_ui = make_card_ui(conn), extra_card_server = make_card_server(conn, auth))`.

The slot is app code: **the role check in the slot handler is mandatory**, the package is not responsible for it.

## 6. Tests

```r
# the permission source
expect_setequal(prov(list(login = "boss", role = "owner")), c("reports", "export", "users"))
expect_length(prov(list(login = "ed", role = "editor")), 0)                   # no permissions yet
save_user_permissions(con, "ed", c("reports", "bogus"))
expect_identical(prov(list(login = "ed", role = "editor")), "reports")        # unknown permissions dropped
expect_length(prov(list(login = "x' OR '1'='1", role = "viewer")), 0)         # the login does not break SQL

# Export without the permission is rejected on the server, with it it runs
run_app({ login_as(session, "ed", "edpass123"); session$setInputs(export = 1) })

# the "Users" server part is registered only for the owner
run_app({ login_as(session, "boss", "bosspass1"); session$flushReact()
          expect_match(as.character(output$`users-main`$html), "users-table", fixed = TRUE) })
run_app({ login_as(session, "ed", "edpass123"); session$flushReact()
          expect_false(nzchar(tryCatch(as.character(output$`users-main`$html), error = function(e) ""))) })
```

The "an editor cannot grant permissions" test through the whole app may be empty: for an editor the user module's server part is not registered, and the slot handler is not called. Verify the slot's protection separately, feeding the module a manually set role (verified in `assets/app-skeleton-db-permissions/tests/test_auth_light.R`):

```r
fake_editor <- list(user = function() list(login = "ed", role = "editor"))
suppressMessages(testServer(aa_users_server,
  args = list(conn = con, auth = fake_editor, settings = auth_settings,
              extra_card_server = make_card_server(con, fake_editor)), {
    session$setInputs(open = "vi", permissions = c("reports", "export"), save_permissions = 1)
  }))
expect_length(prov(list(login = "vi", role = "viewer")), 0)                  # the editor granted nothing
```

The same test with the owner role (`fake_owner`) must grant the permissions.

## 7. Playwright: choosing a role in selectize

The `<select>` element is hidden: `page.evaluate("document.querySelector('#users-new_user_role').selectize.setValue('editor')")`, or click `#users-new_user_role-selectized` and choose `.selectize-dropdown-content .option[data-value="editor"]`. Other identifiers: `references/ui-ids.md` of the `appauth` skill.
