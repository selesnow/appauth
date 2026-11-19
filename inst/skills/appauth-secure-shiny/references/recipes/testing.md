# Recipe: tests for an app with appauth

The package's rules are verified by its own automated tests (1400+ checks). In app tests we check the WIRING: the app loads, permissions and tabs work, handlers refuse without the permission, events are written to the log, the database schema migrates. Templates of ready tests: `assets/tests/test_auth_smoke.R` (an app with `config.yaml` and a permission matrix, like the `assets/app-skeleton` skeleton) and `assets/app-skeleton-db-permissions/tests/test_auth_light.R` (a lightweight variant for apps without `config.yaml`: permissions from the database, custom roles; take it as the base also for an app after migration from home-grown authentication).

More for the developer: the package vignette `testing-your-app` (`vignette("testing-your-app", package = "appauth")`).

## 1. Load the app THE WAY runApp DOES: into its own environment

`shiny::runApp(folder)` loads `app.R` into its own environment, not the global one. If a test runs `eval(parse("app.R"), envir = globalenv())`, variables from `app.R` become global, and an error like "a function from `R/` does not see a variable from `app.R`" (for example `object 'auth_settings' not found`) will not reproduce in the test, although in the running app the tab is empty. That is how an "Access" tab once broke while the test stayed green.

```r
app_env <- new.env(parent = globalenv())
app_obj <- eval(parse(text = app_code), envir = app_env)      # do not print: print() starts the app
server <- app_env$server
```

And check the tab contents under the administrator: after login `output[["access-users-main"]]$html` must contain the users table. A test without this check will miss an empty tab.

## 1a. Running R in this environment and the Shiny load order

* If `Rscript` fails on `library(reticulate)` or picks up libraries of another project (`R_LIBS_USER`, `RENV_PROJECT` from a neighbouring project, someone else's `.Rprofile`), run it with the flags `--no-init-file --no-site-file`, and for `R CMD INSTALL` set `R_PROFILE_USER` to an empty file. Do not run checks from the folder of another project with `renv`.
* **Shiny itself auto-loads `R/*.R` BEFORE running `app.R`.** If a file from `R/` calls a package function at top level (for example `aa_permissions_from_matrix(...)`), it needs its own `library(appauth)`, otherwise a production `runApp()` fails with `could not find function`, while a test that loads only `app.R` stays green. That is why in the templates package functions in `R/` are called only inside functions.
* Specify temporary files in tests and R scripts on Windows as `tempdir()` or `Sys.getenv("TEMP")`, not as `/tmp/...` (a bash-style path will not open inside R).
* Wrap calls like `file.copy()` in tests in `invisible()`, otherwise stray `[1] TRUE` lines end up in the output.

## 2. Helpers for testServer

```r
new_db <- function(env = parent.frame()) {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(if (DBI::dbIsValid(con)) DBI::dbDisconnect(con), envir = env)
  appauth::aa_init_db(con)
  con
}

run_auth <- function(con, expr, settings = aa_settings(), on_event = NULL) {
  rlang::inject(shiny::testServer(
    aa_auth_server, args = list(conn = con, settings = settings, on_event = on_event),
    expr = !!rlang::enquo(expr)))                              # expr must be passed as an expression
}
```

Identifiers in a module test have no prefix (`login`, `login_btn`); in a whole-app test they carry the module prefix (`auth-login`, `users-open`). The full list of module identifiers: `references/ui-ids.md` of the `appauth` skill.

**Always pass `settings` to `aa_create_user()`, `aa_create_first_admin()` and `aa_set_role()`** if the app has its own roles: without it the role is validated against the default roles (`admin`, `user`, `viewer`) and you will get "Invalid role".

## 3. What to check

* Login: a wrong password (the same message for a wrong password and a non-existent login), locking after a series of failures, a correct password does not let in while locked.
* The first administrator on an empty database.
* Permissions: each role sees its own tabs; a handler without the permission is rejected (`expect_error(aa_require(...), class = "shiny.silent.error")`), there is no side effect, the hook received `access_denied`.
* Forced logout: after blocking, deleting, changing the role the open session is closed (`session$elapse(31000)`).
* Cookie auto-login: an ordinary user signs in, a blocked one does not.
* Events: every package event is mapped to a log entry (a test on `aa_events()`).
* Migration of working databases: copies of databases "as in production" are prepared by `aa_prepare_db()` without losing users, hashes and tokens.
* The database file is not locked after sessions close (`file.rename`).
* Permission consistency: all permissions the code uses are present in the config defaults.

## 4. Speed

scrypt is intentionally slow (a fraction of a second per password): create only those users who really log in. If a user is needed only as a table row (for checking permissions, statuses), insert it with an SQL query (such a user cannot log in, but is fine for everything else):

```r
DBI::dbExecute(con, "INSERT INTO users (login, password, role) VALUES (?, ?, ?)", params = list("ivan", "x", "user"))
```

## 5. Modal window contents

`showModal()` is not rendered in `testServer`. Mock the function and check the window's HTML:

```r
html <- NULL
testthat::local_mocked_bindings(showModal = function(ui, ...) html <<- paste(as.character(ui), collapse = ""), .package = "shiny")
```

## 6. Checking in a real browser

`testServer` does not check JavaScript: the auto-login cookie, row highlighting, login on Enter. Before a release walk through the scenario in Chrome (Playwright, Python): login, the administrator tab, adding a user, blocking (a red row), logout and auto-login. The app for the check MUST be started as in production, through `shiny::runApp(folder)`, not `source("app.R")`: otherwise environment errors disappear (item 1).

```python
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)       # or executable_path=... for a system Chrome
    page = browser.new_page(); page.goto("http://127.0.0.1:8790")
    page.wait_for_selector("#auth-setup_btn")           # empty database: creating the administrator
    ...
```

Element identifiers for Playwright (`auth-setup_*`, `auth-login*`, `users-*`, `password-*`), choosing a role in selectize, closing windows and forging a `Shiny.setInputValue(...)` request are described in `references/ui-ids.md` of the `appauth` skill. Forging a request checks the server-side protection: for a user without the permission the handler must refuse (no changes in the database, a refusal event in the log).

Rules for browser checks:

* use temporary copies of the project and databases, do not touch the working `app.db` and `config.yaml`;
* background `future` processes in the check copy can be replaced by a stub (`plan(sequential)`);
* after the check delete the temporary files and stop ONLY your own processes (by exact command line): production apps and bots may be running on the same machine.
