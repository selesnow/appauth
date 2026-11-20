# Testing your app

Authorization needs to be tested together with the application: the
package is covered by its own automated tests, but errors more often
appear at the seams, for example a forgotten permission check in a
handler. This document collects techniques used in the package’s own
tests (`tests/testthat` in its sources) that also suit application
tests.

## A temporary database

The tests below run on an in-memory SQLite database. If your application
runs on MySQL, PostgreSQL, or DuckDB, test on the same database: connect
to an empty test schema (its tables may be dropped), and write queries
without SQLite-specific functions. An example of running the package’s
entire test suite on a chosen database is in `dev/run-tests-db.R` in its
sources.

An in-memory database is enough for the package functions:

``` r

new_db <- function(env = parent.frame()) {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(if (DBI::dbIsValid(con)) DBI::dbDisconnect(con), envir = env)
  appauth::aa_init_db(con)
  con
}
```

If the application needs a database file (as the examples do), create
`tempfile(fileext = ".db")`, pass the path through an environment
variable or config, and delete the file in
[`withr::defer()`](https://withr.r-lib.org/reference/defer.html).

**scrypt hashing is intentionally slow** (a fraction of a second per
password). In a test, create only the users who actually sign in. If a
user is needed only as a table row (permission and status checks),
insert them with an SQL query:

``` r

DBI::dbExecute(
  con, "INSERT INTO users (login, password, role) VALUES (?, ?, ?)",
  params = list("ivan", "x", "user")
)
```

Such a user cannot sign in (the password is not a hash), but is fine for
other checks.

## Functions without Shiny

User rules, permissions, tokens, and login protection are checked with
ordinary `expect_*`:

``` r

test_that("the last administrator cannot be deleted", {
  con <- new_db()
  aa_create_first_admin(con, "boss", "boss-password")
  aa_create_user(con, "ann", "ann-password", "admin")
  aa_delete_user(con, "ann", acting_login = "boss")

  expect_error(
    aa_delete_user(con, "boss", acting_login = "ann"),
    class = "appauth_error_user"
  )
})

test_that("permissions come from the matrix", {
  provider <- aa_permissions_from_matrix(list(Run = c("admin", "user"), Access = "admin"))

  expect_true(aa_can(list(login = "ivan", role = "user"), "Run", provider))
  expect_false(aa_can(list(login = "ivan", role = "user"), "Access", provider))
  expect_false(aa_can(NULL, "Run", provider))      # closed by default
})
```

Rule errors have the class `appauth_error_user` and a `reason` field;
the error text is in the language of the settings.

Time for login protection is easiest to set by inserting a record with
the needed time. Time is stored as text in UTC (`YYYY-MM-DD HH:MM:SS`),
so it is convenient to compute it in R: this way the query is the same
for all databases (there is no need for SQL functions like
`datetime('now')`, which exist only in SQLite):

``` r

three_minutes_ago <- format(Sys.time() - 180, "%Y-%m-%d %H:%M:%S", tz = "UTC")

DBI::dbExecute(
  con,
  "INSERT INTO login_attempts (login, success, attempted_at)
   VALUES (?, 0, ?)",
  params = list("ivan", three_minutes_ago)
)
aa_login_lock_remaining(con, "ivan", aa_settings(max_failed_logins = 1))
```

## Modules via testServer

The sign-in, user, and password change modules are tested through
[`shiny::testServer()`](https://rdrr.io/pkg/shiny/man/testServer.html).
It is convenient to wrap the call in a helper, because `expr` must be
passed as an expression:

``` r

run_auth <- function(con, expr, settings = aa_settings(), on_event = NULL, ...) {
  rlang::inject(shiny::testServer(
    aa_auth_server,
    args = list(conn = con, settings = settings, on_event = on_event, ...),
    expr = !!rlang::enquo(expr)
  ))
}

test_that("password sign-in", {
  con <- new_db()
  aa_create_user(con, "ivan", "ivan-password", "user")

  run_auth(con, {
    session$setInputs(login = "ivan", password = "wrong", login_btn = 1)
    expect_false(session$returned$logged_in())
    expect_equal(output$message, "Incorrect login or password")

    session$setInputs(login = "ivan", password = "ivan-password", login_btn = 2)
    expect_true(session$returned$logged_in())
    expect_equal(session$returned$user(), list(login = "ivan", role = "user"))
  })
})
```

For the users module, instead of a real `auth` an object with a reactive
`user` is enough:

``` r

fake_auth <- function(login = "boss", role = "admin") {
  list(user = shiny::reactiveVal(list(login = login, role = role)))
}
```

Identifiers in a module test have no prefix (`login`, `login_btn`); in a
whole-application test they carry the module prefix (`auth-login`,
`users-open`).

### Events

The hook collects events into a list, which shows what the package
emitted:

``` r

events <- list()
hook <- function(event, user, session_id, value) {
  events[[length(events) + 1]] <<- list(event = event, user = user, value = value)
}
```

### Dialog contents

Dialogs are opened through
[`shiny::showModal()`](https://rdrr.io/pkg/shiny/man/showModal.html) and
are not visible in testServer. Replace the function and get the HTML the
browser would see:

``` r

html <- NULL
testthat::local_mocked_bindings(
  showModal = function(ui, ...) html <<- paste(as.character(ui), collapse = ""),
  .package = "shiny"
)
```

This lets you check that the block button is not shown for oneself, that
the card slot is rendered, and that a login containing HTML is escaped.

### Time and the guard

In `testServer` the session time is advanced manually:

``` r

shiny::testServer(function(input, output, session) aa_session_guard(auth, con, settings), {
  session$flushReact()
  DBI::dbExecute(con, "UPDATE users SET blocked = 1 WHERE login = 'ivan'")
  session$elapse(35000)               # 35 seconds have passed
  expect_equal(logout_calls[[1]]$reason, "blocked")
})
```

## Whole-application test: load `app.R` the way `runApp()` does

`shiny::runApp(directory)` loads `app.R` into its own environment, not
the global one. If a test runs
`eval(parse("app.R"), envir = globalenv())`, variables created in
`app.R` become global, and an error such as “a function from `R/` does
not see a variable from `app.R`” will not reproduce in the test,
although in the running application the tab is broken. Load the
application into a separate environment:

``` r

app_env <- new.env(parent = globalenv())
app_obj <- eval(parse(text = app_code), envir = app_env)
server <- app_env$server
```

Do not rely only on such tests: load order errors (for example, a file
in `R/` calls a package function at top level without its own
[`library(appauth)`](https://alexey-seleznev.pro/appauth/), while Shiny
sources `R/` before `app.R`) show up only with a real
[`runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html). Before a
release, run the application as in production and open it in a browser.
If `Rscript` in your environment picks up another project’s `.Rprofile`
or `R_LIBS_USER`, run it with the `--no-init-file --no-site-file` flags.

Check that the server parts of tabs are registered for those who have
the permission: after an administrator signs in,
`output$`access-users-main\`\` must contain the users table. A test that
does not check tab contents under the administrator role will miss an
empty tab.

## Protecting your application’s handlers

For each action handler, write a “without the permission the handler
does not run” test:

``` r

test_that("running a task without the permission is rejected", {
  provider <- aa_permissions_from_matrix(list(Run = "admin"))
  auth <- list(user = function() list(login = "olga", role = "viewer"))

  expect_error(
    suppressMessages(aa_require(auth, "Run", provider)),
    class = "shiny.silent.error"
  )
})
```

In a whole-application test, check that the side effect did not happen
(no record added, no task started) and that the hook received
`access_denied`.

## Security test checklist for the application

- Sign-in: wrong password, nonexistent login (same message), empty
  fields.
- Lockout after a series of failures; the correct password does not let
  the user in while locked.
- A user blocked by the administrator cannot sign in, and their token
  does not work.
- Every action handler refuses without the permission (for each role
  lacking it).
- A user without the permission does not get the module’s server part.
- SQL injection in the login and password of the sign-in form does not
  let anyone in.
- A login containing HTML and scripts is escaped in all tables and
  dialogs of the application.
- The token of a revoked, deleted, or blocked user does not work.
- An open session ends after blocking, deletion, role change, or
  password reset.
- The database connection is closed when the session ends (the database
  file can be renamed after the sessions stop).

## Testing in a real browser

`testServer` does not test JavaScript: the auto-login cookie, row
highlighting, sign-in on Enter. For such checks the package sources
include Playwright and Chrome scenarios (`dev/e2e`): the application
starts on a temporary database, the scenario goes through sign-in,
blocking, the card, and sign-out, and saves screenshots. They can serve
as a basis for your own application. Run such a check on a copy of the
database with test users, not on the production database.
