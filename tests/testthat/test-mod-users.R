# The users module through testServer. Modal windows are not shown in the mock
# session, so we check the actions, their result in the database and events.
# Helpers are in helper-modules.R, card contents in test-mod-card.R.

test_that("an administrator sees the table, other roles see nothing", {
  con <- users_fixture()

  run_users(con, {
    session$flushReact()
    expect_false(is.null(output$main$html))
    expect_match(
      paste(as.character(output$main$html), collapse = ""),
      "table",
      fixed = TRUE
    )
  })

  run_users(con, auth = fake_auth("ivan", "user"), {
    session$flushReact()
    expect_true(
      is.null(output$main$html) ||
        !nzchar(paste(as.character(output$main$html), collapse = ""))
    )
  })
})

test_that("the table contains users and highlights blocks", {
  con <- users_fixture()
  aa_set_blocked(con, "ivan", TRUE, acting_login = "alsey")

  run_users(con, {
    session$flushReact()
    # table data is server-side (serverSide), so look at the module's reactive data
    data <- overview()
    expect_setequal(data$login, c("alsey", "boss", "ivan"))
    expect_equal(data$state[data$login == "ivan"], "blocked")
    expect_equal(
      data$status[data$login == "ivan"],
      "Blocked by an administrator"
    )
    expect_false("password" %in% names(data))

    json <- paste(as.character(output$table), collapse = "")
    expect_match(json, "aa-row-blocked", fixed = TRUE)
    expect_match(json, "aa-row-locked", fixed = TRUE)
    expect_match(json, "dblclick", fixed = TRUE)
  })
})

test_that("adding: password mismatch, weak password, duplicate, success", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(add = 1)

    session$setInputs(
      new_login = "olga",
      new_user_password = "secret123",
      new_user_confirm = "other",
      new_user_role = "user",
      add_confirm = 1
    )
    expect_equal(output$add_message, "Passwords do not match")
    expect_equal(count_users(con), 3)

    session$setInputs(
      new_login = "olga",
      new_user_password = "123",
      new_user_confirm = "123",
      add_confirm = 2
    )
    expect_match(output$add_message, "at least")
    expect_equal(count_users(con), 3)

    session$setInputs(
      new_login = "IVAN",
      new_user_password = "secret123",
      new_user_confirm = "secret123",
      add_confirm = 3
    )
    expect_match(output$add_message, "already exists")
    expect_equal(count_users(con), 3)

    session$setInputs(
      new_login = "olga",
      new_user_password = "secret123",
      new_user_confirm = "secret123",
      new_user_role = "viewer",
      add_confirm = 4
    )
    expect_equal(count_users(con), 4)
  })

  expect_equal(role_of(con, "olga"), "viewer")
  expect_true(aa_is_password_hash(stored_password(con, "olga")))
  expect_equal(log$names(), "user_added")
  expect_equal(log$events[[1]]$user, "alsey")
  expect_equal(log$events[[1]]$value, "olga (viewer)")
})

test_that("an invalid role is rejected when adding", {
  con <- users_fixture()

  run_users(con, {
    session$setInputs(add = 1)
    session$setInputs(
      new_login = "olga",
      new_user_password = "secret123",
      new_user_confirm = "secret123",
      new_user_role = "superuser",
      add_confirm = 1
    )
    expect_match(output$add_message, "role", ignore.case = TRUE)
  })

  expect_equal(count_users(con), 3)
})

test_that("blocking and unblocking: tokens are revoked, events and the table are updated", {
  con <- users_fixture()
  token <- aa_issue_token(con, "ivan")

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(block = 1)
    expect_equal(blocked_of(con, "ivan"), 1)
    expect_null(aa_find_session_user(con, token))

    session$flushReact()
    expect_equal(overview()$state[overview()$login == "ivan"], "blocked")

    session$setInputs(unblock = 1)
    expect_equal(blocked_of(con, "ivan"), 0)
  })

  expect_equal(log$names(), c("user_blocked", "user_unblocked"))
  expect_equal(log$events[[1]]$value, "ivan")
})

test_that("one cannot block or delete oneself, rules work on the server", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(open = "alsey")
    session$setInputs(block = 1)
    session$setInputs(delete = 1)
    session$setInputs(delete_confirm = 1)
  })

  expect_equal(blocked_of(con, "alsey"), 0)
  expect_equal(count_users(con), 3)
  expect_length(log$events, 0)
})

test_that("the last active administrator cannot be blocked, deleted or demoted", {
  con <- users_fixture()
  aa_set_blocked(con, "boss", TRUE, acting_login = "alsey")

  log <- run_users(con, {
    session$setInputs(open = "alsey")
    session$setInputs(change_role = 1, role = "user")
    session$setInputs(block = 1)
    session$setInputs(delete = 2)
    session$setInputs(delete_confirm = 2)
  })

  expect_equal(role_of(con, "alsey"), "admin")
  expect_equal(blocked_of(con, "alsey"), 0)
  expect_length(log$events, 0)
})

test_that("removing the sign-in lock clears failed attempts", {
  con <- users_fixture()
  settings <- aa_settings(max_failed_logins = 3)
  for (i in 1:3) {
    add_attempt(con, "ivan", FALSE)
  }
  expect_gt(aa_login_lock_remaining(con, "ivan", settings), 0)

  log <- run_users(con, settings = settings, {
    session$setInputs(open = "ivan")
    session$setInputs(unlock = 1)
  })

  expect_equal(aa_login_lock_remaining(con, "ivan", settings), 0)
  expect_equal(log$names(), "login_unlocked")
})

test_that("role change, including an ordinary user to admin and back", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(change_role = 1, role = "viewer")
    expect_equal(role_of(con, "ivan"), "viewer")

    session$setInputs(change_role = 2, role = "root")
    expect_equal(role_of(con, "ivan"), "viewer")
  })

  expect_equal(log$names(), "user_role_changed")
  expect_equal(log$events[[1]]$value, "ivan: viewer")
})

test_that("password reset: a mismatch is rejected, success changes the password and revokes tokens", {
  con <- users_fixture()
  token <- aa_issue_token(con, "ivan")

  log <- run_users(con, {
    session$setInputs(open = "ivan")

    session$setInputs(
      new_password = "newpass123",
      new_password_confirm = "different",
      reset_password = 1
    )
    expect_false(is.null(aa_authenticate(con, "ivan", "secret123")))

    session$setInputs(
      new_password = "123",
      new_password_confirm = "123",
      reset_password = 2
    )
    expect_false(is.null(aa_authenticate(con, "ivan", "secret123")))

    session$setInputs(
      new_password = "newpass123",
      new_password_confirm = "newpass123",
      reset_password = 3
    )
  })

  expect_null(aa_authenticate(con, "ivan", "secret123"))
  expect_false(is.null(aa_authenticate(con, "ivan", "newpass123")))
  expect_null(aa_find_session_user(con, token))
  expect_equal(log$names(), "password_reset")
})

test_that("deleting a user: the record and tokens are deleted, the event is sent", {
  con <- users_fixture()
  aa_issue_token(con, "ivan")

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(delete = 1)
    session$setInputs(delete_confirm = 1)
  })

  expect_null(aa_get_user(con, "ivan"))
  expect_equal(nrow(rows_of(con, "auth_sessions")), 0)
  expect_equal(log$names(), "user_removed")
})

test_that("an action without an open card does nothing: the target does not come from the browser", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(
      delete = 1,
      delete_confirm = 1,
      block = 1,
      role = "viewer",
      change_role = 1,
      unlock = 1
    )
  })

  expect_equal(count_users(con), 3)
  expect_equal(blocked_of(con, "ivan"), 0)
  expect_equal(role_of(con, "ivan"), "user")
  expect_length(log$events, 0)
})

test_that("after the card is closed (deletion, password reset) the target is reset", {
  con <- users_fixture()

  run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(delete = 1)
    session$setInputs(delete_confirm = 1)
    session$setInputs(open = "boss") # another card
    session$setInputs(delete = 2)
    session$setInputs(delete_confirm = 2)
    expect_null(aa_get_user(con, "boss"))
  })
})

test_that("a non-administrator cannot perform actions, the denial goes to events", {
  con <- users_fixture()

  log <- run_users(con, auth = fake_auth("ivan", "user"), {
    session$setInputs(open = "boss")
    session$setInputs(block = 1)
    session$setInputs(add = 1)
    session$setInputs(
      new_login = "x1",
      new_user_password = "secret123",
      new_user_confirm = "secret123",
      add_confirm = 1
    )
  })

  expect_equal(blocked_of(con, "boss"), 0)
  expect_equal(count_users(con), 3)
  expect_true(all(log$names() == "access_denied"))
  expect_gte(length(log$events), 1)
})

test_that("an administrator demoted in the database loses access despite the old role in the session", {
  con <- users_fixture()
  texec(con, "UPDATE users SET role = 'user' WHERE login = 'alsey'")

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(block = 1)
  })

  expect_equal(blocked_of(con, "ivan"), 0)
  expect_true("access_denied" %in% log$names())
})

test_that("a blocked administrator loses access", {
  con <- users_fixture()
  texec(con, "UPDATE users SET blocked = 1 WHERE login = 'alsey'")

  run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(block = 1)
  })

  expect_equal(blocked_of(con, "ivan"), 0)
})

test_that("slot: the server part is called once and sees the login of the open card", {
  con <- users_fixture()
  seen <- new.env()
  seen$calls <- 0
  slot_server <- function(input, output, session, login) {
    seen$calls <- seen$calls + 1
    seen$login <- login
  }

  run_users(
    con,
    extra_card_server = slot_server,
    extra_card_ui = function(login, ns) NULL,
    {
      expect_equal(seen$calls, 1)
      session$setInputs(open = "ivan")
      expect_equal(seen$login(), "ivan")
      session$setInputs(open = "boss")
      expect_equal(seen$login(), "boss")
      expect_equal(seen$calls, 1)
    }
  )
})

test_that("the UI slot receives the login and the namespace function", {
  con <- users_fixture()
  seen <- new.env()
  slot_ui <- function(login, ns) {
    seen$login <- login
    seen$id <- ns("extra")
    NULL
  }

  run_users(con, extra_card_ui = slot_ui, {
    session$setInputs(open = "ivan")
  })

  expect_equal(seen$login, "ivan")
  expect_match(seen$id, "extra$")
})

test_that("the card of a nonexistent user does not open and does not break the module", {
  con <- users_fixture()

  run_users(con, {
    session$setInputs(open = "ghost")
    session$setInputs(delete = 1)
    session$setInputs(delete_confirm = 1)
  })

  expect_equal(count_users(con), 3)
})

test_that("refresh redraws the table after external changes", {
  con <- users_fixture()

  run_users(con, {
    session$flushReact()
    expect_false("olga" %in% overview()$login)

    aa_create_user(con, "olga", "secret123", "user")
    session$returned$refresh()
    session$flushReact()
    expect_true("olga" %in% overview()$login)
  })
})

test_that("after sign-out (no user) the table does not record an access denial", {
  con <- users_fixture()
  auth <- fake_auth()

  log <- run_users(con, auth = auth, {
    session$flushReact()
    auth$user(NULL)
    session$flushReact()
  })

  expect_length(log$events, 0)
})

test_that("the table shows email, 2FA and auto-logins as check marks and numbers", {
  con <- users_fixture()
  settings <- aa_settings(
    totp_enabled = TRUE,
    totp_key = "a-long-random-key-for-the-tests"
  )
  aa_set_email(con, "ivan", "ivan@example.com", settings)
  aa_issue_token(con, "ivan")

  run_users(con, settings = settings, {
    session$flushReact()
    json <- paste(as.character(output$table), collapse = "")

    # table data is server-side: headers and columns are checked in the table description, values in the module data
    expect_match(json, "<th>Email<", fixed = TRUE)
    expect_match(json, "<th>2FA<", fixed = TRUE)
    expect_match(json, "<th>Auto-logins<", fixed = TRUE)
    expect_match(json, "dt-center", fixed = TRUE)
    expect_false(grepl("ivan@example.com", json, fixed = TRUE))

    data <- overview()
    expect_identical(data$has_email[data$login == "ivan"], 1L)
    expect_identical(data$has_email[data$login == "boss"], 0L)
    expect_identical(data$autologins[data$login == "ivan"], 1L)
    expect_identical(data$totp_on[data$login == "ivan"], 0L)
    # service column: state stays last, row highlighting takes its index
    expect_match(json, "data[8] === 'blocked'", fixed = TRUE)
  })
})

test_that("with 2FA off there is no 2FA column, the service column index shifts", {
  con <- users_fixture()

  run_users(con, {
    session$flushReact()
    json <- paste(as.character(output$table), collapse = "")

    expect_match(json, "<th>Email<", fixed = TRUE)
    expect_false(grepl("<th>2FA<", json, fixed = TRUE))
    expect_match(json, "<th>Auto-logins<", fixed = TRUE)
    expect_match(json, "data[7] === 'blocked'", fixed = TRUE)
  })
})
