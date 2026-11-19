# Recipe: guarding handlers and validating input

Hiding buttons and tabs is not protection: any request to Shiny can be forged from the browser. So in EVERY action handler permissions are checked on the server, and data from `input` is treated as untrusted.

## 1. The permission is the first line of the handler

```r
observeEvent(input$run_task, {
  require_permission(auth, conf_rv, "Run", session$token)      # or aa_require(auth, "Run", provider, on_event = log_event)
  ...action...
})
```

When the permission is missing, `aa_require()` silently aborts the handler, shows the user a notification and sends an `access_denied` event to the hook. The role comes from `auth$user()`, which is filled only by the server-side login code, not from `input`.

If an action has its own permission (for example separate permissions such as `Run tasks`, `Activate tasks`, `Manage services`, `View code`, `AI analysis`), check exactly that one, not only the tab permission.

## 2. Data from input: allow-lists instead of trust

* Check names of tasks, services, files and actions against a list the server knows (an app table, `get_tasks()`) instead of accepting them as is.
* For values from drop-down lists check membership in the allowed set: `req(input$role %in% auth_settings$roles)`.
* Coerce and validate numbers and dates (`as.integer`, range).

```r
# a name from a user or an AI assistant: allowed characters and existence
is_safe_task_name <- function(x) {
  is.character(x) && length(x) == 1 && !is.na(x) && nzchar(x) && nchar(x) <= 260 &&
    !grepl('["\\x00-\\x1f]', x, perl = TRUE)
}
task_exists <- function(x, known) is_safe_task_name(x) && x %in% known
```

## 3. Running commands

Never concatenate a command string from user data (`system(paste("cmd", input$x))`, `shell()`). Use `system2()` with an argument vector, values checked against an allow-list, and absolute paths:

```r
req(task_exists(input$task, tasks$TaskName))
out <- system2("schtasks", c("/run", "/tn", shQuote(input$task)), stdout = TRUE, stderr = TRUE)
```

A command line (CMD) and similar "run anything" tabs are acceptable only for the most trusted role and always with a log entry. They are always behind a permission, and the server part is registered only for that role.

## 4. Files and paths

Normalise a path that comes from the user and check that it lies inside the allowed folder:

```r
safe_path <- function(user_path, root) {
  p <- normalizePath(file.path(root, user_path), winslash = "/", mustWork = FALSE)
  r <- normalizePath(root, winslash = "/", mustWork = TRUE)
  if (!startsWith(tolower(p), tolower(paste0(r, "/")))) NULL else p
}
```

Do not read or delete files by a path from `input` without such a check (`../` escapes the folder). Do not serve the app's database file for download: recipes/database-download.md.

## 5. The app's SQL

Only parameterised queries: `DBI::dbGetQuery(con, "SELECT ... WHERE login = ?", params = list(x))`. No `paste0("... '", input$x, "'")`, no `glue("... {input$x}")`. Take table and column names from `input` only from an allow-list.

## 6. Output

* In `DT::datatable(escape = FALSE)` and `HTML(paste0(...))` do not insert foreign data (logins, titles, comments), otherwise the HTML will execute in the administrator's browser.
* For links and highlighting build tags with `tags$a()`, `tags$span()`, not strings.

## 7. What not to do

| Anti-pattern | Why it is bad | The right way |
| --- | --- | --- |
| Hid the button and consider it protected | the handler can be called from the browser | `require_permission()` in the handler |
| `if (input$role == "admin")` | the role can be forged | the role from `auth$user()$role` |
| Permissions in a global variable (`user_role <<- ...`) | shared by all sessions, one session sees another's role | state in `auth` (reactive, per session) |
| `eval(parse(text = input$code))` | arbitrary code execution | do not use |
| Permission only on the tab, with dangerous actions inside it | a user with the tab permission can do everything | separate permissions for actions |

## 8. Tests

```r
test_that("running a task without the permission is rejected", {
  provider <- aa_permissions_from_matrix(list(Run = "admin"))
  auth <- list(user = function() list(login = "olga", role = "viewer"))
  expect_error(suppressMessages(aa_require(auth, "Run", provider)), class = "shiny.silent.error")
})
```

In an app test, check that there was no side effect (no record added, no task started), and that the hook received `access_denied`.
