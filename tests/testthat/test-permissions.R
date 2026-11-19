matrix_sm <- list(
  Tasks = c("admin", "user", "viewer"),
  Run = c("admin", "user"),
  Access = "admin",
  News = "admin"
)
u_admin <- list(login = "root", role = "admin")
u_user <- list(login = "ivan", role = "user")
u_viewer <- list(login = "olga", role = "viewer")

test_that("the matrix turns into role permissions, a scalar value works too", {
  provider <- aa_permissions_from_matrix(matrix_sm)

  expect_setequal(provider(u_admin), c("Tasks", "Run", "Access", "News"))
  expect_setequal(provider(u_user), c("Tasks", "Run"))
  expect_equal(provider(u_viewer), "Tasks")
})

test_that("an unknown, empty and corrupted role gets no permissions", {
  provider <- aa_permissions_from_matrix(matrix_sm)

  expect_equal(provider(list(login = "x", role = "ghost")), character(0))
  expect_equal(provider(list(login = "x", role = "")), character(0))
  expect_equal(provider(list(login = "x", role = NA_character_)), character(0))
  expect_equal(provider(list(login = "x", role = c("admin", "user"))), character(0))
  expect_equal(provider(list(login = "x")), character(0))
  expect_equal(provider(NULL), character(0))
})

test_that("the administrator role gets no permissions by itself", {
  provider <- aa_permissions_from_matrix(list(Tasks = "user"))

  expect_false(aa_can(u_admin, "Tasks", provider))
})

test_that("a permission with an empty role list or NULL is available to nobody", {
  provider <- aa_permissions_from_matrix(list(A = NULL, B = character(0), C = "user"))

  expect_equal(provider(u_user), "C")
})

test_that("a matrix function is read on every check (permission editor)", {
  current <- list(Run = "admin")
  provider <- aa_permissions_from_matrix(function() current)

  expect_false(aa_can(u_user, "Run", provider))
  current <- list(Run = c("admin", "user"))
  expect_true(aa_can(u_user, "Run", provider))
})

test_that("an invalid matrix is rejected", {
  expect_error(aa_permissions_from_matrix(c("admin", "user")), class = "appauth_error_permissions")
  expect_error(aa_permissions_from_matrix(list("admin", "user")), class = "appauth_error_permissions")
  expect_error(aa_permissions_from_matrix(NULL), class = "appauth_error_permissions")
})

test_that("a broken matrix function closes access instead of opening it", {
  provider <- aa_permissions_from_matrix(function() "garbage")

  expect_false(suppressMessages(aa_can(u_admin, "Tasks", provider)))
  expect_message(aa_can(u_admin, "Tasks", provider), "permission provider failed")
})

test_that("aa_can: the permission is held only by the listed roles", {
  provider <- aa_permissions_from_matrix(matrix_sm)

  expect_true(aa_can(u_admin, "Access", provider))
  expect_false(aa_can(u_user, "Access", provider))
  expect_false(aa_can(u_viewer, "Run", provider))
  expect_false(aa_can(u_admin, "Unknown", provider))
})

test_that("aa_can is closed by default on any uncertainty", {
  provider <- aa_permissions_from_matrix(matrix_sm)

  expect_false(aa_can(NULL, "Access", provider))
  expect_false(aa_can("admin", "Access", provider))
  expect_false(aa_can(u_admin, NULL, provider))
  expect_false(aa_can(u_admin, "", provider))
  expect_false(aa_can(u_admin, NA_character_, provider))
  expect_false(aa_can(u_admin, c("Access", "Tasks"), provider))
  expect_false(aa_can(u_admin, 1, provider))
})

test_that("aa_can: a provider with an error or garbage gives FALSE", {
  expect_false(suppressMessages(aa_can(u_admin, "Access", function(user) stop("database unavailable"))))
  expect_false(aa_can(u_admin, "Access", function(user) NULL))
  expect_false(aa_can(u_admin, "Access", function(user) 1))
  expect_false(aa_can(u_admin, "Access", function(user) NA_character_))
  expect_message(aa_can(u_admin, "Access", function(user) stop("database unavailable")), "database unavailable")
})

test_that("aa_can: a missing provider is a programmer error, not a denial", {
  expect_error(aa_can(u_admin, "Access", NULL), class = "appauth_error_permissions")
  expect_error(aa_can(u_admin, "Access", list(Access = "admin")), class = "appauth_error_permissions")
})

test_that("a custom provider (per-user permissions) works the same way", {
  grants <- list(ivan = c("Run", "Export"), olga = character(0))
  provider <- function(user) grants[[user$login]] %||% character(0)

  expect_true(aa_can(u_user, "Export", provider))
  expect_false(aa_can(u_viewer, "Export", provider))
  expect_false(aa_can(list(login = "stranger", role = "admin"), "Export", provider))
})

test_that("aa_require lets through with the permission and does not call the hook", {
  provider <- aa_permissions_from_matrix(matrix_sm)
  events <- list()
  hook <- function(event, user, session_id, value) events[[length(events) + 1]] <<- event

  expect_true(aa_require(u_admin, "Access", provider, on_event = hook))
  expect_length(events, 0)
})

test_that("aa_require without the permission quietly aborts the handler and sends access_denied", {
  provider <- aa_permissions_from_matrix(matrix_sm)
  got <- NULL
  hook <- function(event, user, session_id, value) got <<- list(event, user, session_id, value)

  expect_error(
    suppressMessages(aa_require(u_user, "Access", provider, on_event = hook)),
    class = "shiny.silent.error"
  )
  expect_equal(got, list("access_denied", "ivan", "", "Access"))
})

test_that("aa_require accepts an auth object with a reactive user", {
  provider <- aa_permissions_from_matrix(matrix_sm)
  auth <- list(user = function() u_admin)

  expect_true(aa_require(auth, "Access", provider))

  auth_user <- list(user = function() u_user)
  expect_error(suppressMessages(aa_require(auth_user, "Access", provider)), class = "shiny.silent.error")
})

test_that("aa_require without a user (not logged in) denies as anonymous", {
  provider <- aa_permissions_from_matrix(matrix_sm)
  got <- NULL
  hook <- function(event, user, session_id, value) got <<- user

  expect_error(
    suppressMessages(aa_require(list(user = function() NULL), "Tasks", provider, on_event = hook)),
    class = "shiny.silent.error"
  )
  expect_equal(got, "anonymous")
})

test_that("a broken hook does not cancel the denial or crash the handler with another error", {
  provider <- aa_permissions_from_matrix(matrix_sm)
  hook <- function(event, user, session_id, value) stop("log unavailable")

  expect_error(
    suppressMessages(aa_require(u_user, "Access", provider, on_event = hook)),
    class = "shiny.silent.error"
  )
})

test_that("aa_require inside a Shiny session: denial, session id in the hook", {
  provider <- aa_permissions_from_matrix(matrix_sm)
  seen <- new.env()
  hook <- function(event, user, session_id, value) seen$session <- session_id

  server <- function(input, output, session) {
    observeEvent(input$go, {
      aa_require(u_user, "Access", provider, on_event = hook)
      seen$ran <- TRUE
    })
  }

  suppressMessages(shiny::testServer(server, {
    session$setInputs(go = 1)
  }))

  expect_null(seen$ran)
  expect_true(nzchar(seen$session))
})
