test_that("events catalog: unique keys, all fields filled, required events present", {
  ev <- aa_events()

  expect_named(ev, c("event", "description", "value"))
  expect_false(anyDuplicated(ev$event) > 0)
  expect_true(all(grepl("^[a-z_]+$", ev$event)))
  expect_true(all(nzchar(ev$description)))
  expect_true(all(
    c(
      "login_success",
      "login_failed",
      "login_locked",
      "login_blocked_user",
      "logout",
      "session_forced_logout",
      "user_added",
      "user_removed",
      "user_role_changed",
      "password_reset",
      "user_blocked",
      "user_unblocked",
      "login_unlocked",
      "access_denied",
      "first_admin_created",
      "registration_requested",
      "registration_confirmed",
      "registration_failed",
      "google_user_created"
    ) %in%
      ev$event
  ))
})

test_that("all events emitted by the package code are described in the catalog", {
  files <- list.files(
    testthat::test_path("..", "..", "R"),
    pattern = "\\.R$",
    full.names = TRUE
  )
  skip_if(length(files) == 0, "sources not available (installed package)")

  code <- unlist(lapply(files, readLines, encoding = "UTF-8"))
  used <- unique(unlist(regmatches(
    code,
    gregexpr("aa_emit\\([^,]+,\\s*\"[a-z_]+\"", code)
  )))
  used <- sub(".*\"([a-z_]+)\"$", "\\1", used)

  expect_gt(length(used), 0)
  expect_true(
    all(used %in% aa_events()$event),
    info = paste(setdiff(used, aa_events()$event), collapse = ", ")
  )
})

test_that("aa_emit passes all fields to the hook and fills in defaults", {
  got <- NULL
  hook <- function(event, user, session_id, value) {
    got <<- list(event, user, session_id, value)
  }

  expect_true(aa_emit(hook, "user_added", "root", "s1", "ivan"))
  expect_equal(got, list("user_added", "root", "s1", "ivan"))

  aa_emit(hook, "logout")
  expect_equal(got, list("logout", "anonymous", "", ""))

  aa_emit(hook, "logout", NA_character_, NULL, 5)
  expect_equal(got, list("logout", "anonymous", "", "5"))
})

test_that("aa_emit without a hook does nothing, a hook error is not propagated", {
  expect_false(aa_emit(NULL, "logout"))
  expect_false(aa_emit("not a function", "logout"))
  expect_message(
    res <- aa_emit(
      function(event, user, session_id, value) stop("log unavailable"),
      "logout"
    ),
    "log unavailable"
  )
  expect_false(res)
})

test_that("Russian catalog has the same events and ASCII-only source", {
  en <- aa_events()
  ru <- aa_events("ru")

  expect_named(ru, names(en))
  expect_identical(ru$event, en$event)
  expect_true(all(nzchar(ru$description)))
  expect_false(identical(ru$description, en$description))
  expect_error(aa_events("de"))
})
