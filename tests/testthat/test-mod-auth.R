# The sign-in module through testServer. Passwords are hashed with scrypt, so users
# are created only where they are needed. Helpers are in helper-modules.R.

test_that("with existing users the sign-in form is shown and disappears after sign-in", {
  con <- auth_db()

  run_auth(con, {
    session$flushReact()
    html <- form_html(output)
    expect_match(html, "login_btn", fixed = TRUE)
    expect_match(html, "Authorization", fixed = TRUE)
    expect_false(grepl("setup_btn", html, fixed = TRUE))
    expect_false(logged_in <- session$returned$logged_in())

    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    expect_true(session$returned$logged_in())
    expect_equal(session$returned$user(), list(login = "ivan", role = "user"))
    expect_equal(session$returned$role(), "user")
    expect_true(is.null(output$form$html) || !nzchar(form_html(output)))
  })
})

test_that("successful sign-in issues a token, sends a cookie and an event", {
  con <- auth_db()

  log <- run_auth(con, {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
  })

  expect_equal(log$names(), "login_success")
  expect_equal(log$events[[1]]$user, "ivan")
  expect_equal(count_rows <- nrow(rows_of(con, "auth_sessions")), 1)
  expect_equal(count_attempts(con), 1)
})

test_that("the login comes from the database and the role cannot be spoofed", {
  con <- auth_db()

  run_auth(con, {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    expect_equal(session$returned$user()$login, "ivan")
    expect_equal(session$returned$user()$role, "user")
  })
})

test_that("wrong password: message, event, attempt recorded, no sign-in", {
  con <- auth_db()

  log <- run_auth(con, {
    session$setInputs(login = "ivan", password = "wrong-pass", login_btn = 1)
    expect_equal(output$message, "Incorrect login or password")
    expect_false(session$returned$logged_in())
  })

  expect_equal(log$names(), "login_failed")
  expect_equal(nrow(rows_of(con, "auth_sessions")), 0)
  expect_equal(count_attempts(con), 1)
})

test_that("a nonexistent login is indistinguishable from a wrong password", {
  con <- auth_db()

  run_auth(con, {
    session$setInputs(login = "ghost", password = "secret123", login_btn = 1)
    expect_equal(output$message, "Incorrect login or password")
  })
})

test_that("empty fields are neither a sign-in nor an attempt", {
  con <- auth_db()

  log <- run_auth(con, {
    session$setInputs(login = "", password = "", login_btn = 1)
    expect_equal(output$message, "Incorrect login or password")
  })

  expect_length(log$events, 0)
  expect_equal(count_attempts(con), 0)
})

test_that("after a series of failures the login is locked, the correct password does not let in either", {
  con <- auth_db()
  settings <- aa_settings(max_failed_logins = 3)

  log <- run_auth(con, settings = settings, {
    for (i in 1:2) {
      session$setInputs(login = "ivan", password = "bad", login_btn = i)
      expect_equal(output$message, "Incorrect login or password")
    }
    session$setInputs(login = "ivan", password = "bad", login_btn = 3)
    expect_match(output$message, "Too many failed sign-in attempts")

    session$setInputs(login = "ivan", password = "secret123", login_btn = 4)
    expect_match(output$message, "Too many failed sign-in attempts")
    expect_false(session$returned$logged_in())
  })

  expect_equal(
    log$names(),
    c("login_failed", "login_failed", "login_locked", "login_locked")
  )
  # attempts during a lock are not recorded and do not extend it
  expect_equal(count_attempts(con), 3)
})

test_that("locking one login does not affect another, login case matters", {
  con <- auth_db()
  raw_user(con, "Ivan", "user")
  aa_set_password(con, "Ivan", "other-pass1")
  settings <- aa_settings(max_failed_logins = 2)

  run_auth(con, settings = settings, {
    session$setInputs(login = "ivan", password = "bad", login_btn = 1)
    session$setInputs(login = "ivan", password = "bad", login_btn = 2)
    expect_match(output$message, "Too many")

    session$setInputs(login = "Ivan", password = "other-pass1", login_btn = 3)
    expect_true(session$returned$logged_in())
    expect_equal(session$returned$user()$login, "Ivan")
  })
})

test_that("the global failure limit per minute stops sign-in", {
  con <- auth_db()
  settings <- aa_settings(
    max_failed_logins_per_minute = 2,
    max_failed_logins = 50
  )

  log <- run_auth(con, settings = settings, {
    session$setInputs(login = "a", password = "x", login_btn = 1)
    session$setInputs(login = "b", password = "x", login_btn = 2)
    session$setInputs(login = "ivan", password = "secret123", login_btn = 3)
    expect_match(output$message, "Too many sign-in attempts")
    expect_false(session$returned$logged_in())
  })

  expect_equal(log$names()[3], "login_throttled")
})

test_that("blocked by an administrator: message only with the correct password, no token", {
  con <- auth_db()
  aa_set_blocked(con, "ivan", TRUE, acting_login = "alsey")

  log <- run_auth(con, {
    session$setInputs(login = "ivan", password = "bad-pass", login_btn = 1)
    expect_equal(output$message, "Incorrect login or password")

    session$setInputs(login = "ivan", password = "secret123", login_btn = 2)
    expect_match(output$message, "blocked by an administrator")
    expect_false(session$returned$logged_in())
  })

  expect_equal(log$names(), c("login_failed", "login_blocked_user"))
  expect_equal(nrow(rows_of(con, "auth_sessions")), 0)
})

test_that("successful sign-in resets the failure counter", {
  con <- auth_db()
  settings <- aa_settings(max_failed_logins = 3)

  run_auth(con, settings = settings, {
    session$setInputs(login = "ivan", password = "bad", login_btn = 1)
    session$setInputs(login = "ivan", password = "bad", login_btn = 2)
    session$setInputs(login = "ivan", password = "secret123", login_btn = 3)
    expect_true(session$returned$logged_in())
  })

  expect_equal(aa_login_lock_remaining(con, "ivan", settings), 0)
})

test_that("empty database: administrator creation form, checks and creation", {
  con <- users_db()

  log <- run_auth(con, {
    session$flushReact()
    html <- form_html(output)
    expect_match(html, "setup_btn", fixed = TRUE)
    expect_match(html, "Create administrator", fixed = TRUE)
    expect_false(grepl("login_btn", html, fixed = TRUE))

    session$setInputs(
      setup_login = "boss",
      setup_password = "secret123",
      setup_confirm = "other",
      setup_btn = 1
    )
    expect_equal(output$message, "Passwords do not match")
    expect_equal(count_users(con), 0)

    session$setInputs(
      setup_login = "boss",
      setup_password = "123",
      setup_confirm = "123",
      setup_btn = 2
    )
    expect_match(output$message, "Password")
    expect_equal(count_users(con), 0)

    session$setInputs(
      setup_login = "boss",
      setup_password = "secret123",
      setup_confirm = "secret123",
      setup_btn = 3
    )
    expect_true(session$returned$logged_in())
    expect_equal(session$returned$user(), list(login = "boss", role = "admin"))
  })

  expect_equal(log$names(), "first_admin_created")
  expect_equal(count_users(con), 1)
  expect_equal(nrow(rows_of(con, "auth_sessions")), 1)
})

test_that("administrator creation does not work if a user has appeared already", {
  con <- users_db()

  run_auth(con, {
    session$flushReact()
    aa_create_user(con, "early", "secret123", "admin")
    session$setInputs(
      setup_login = "late",
      setup_password = "secret123",
      setup_confirm = "secret123",
      setup_btn = 1
    )
    expect_false(session$returned$logged_in())
  })

  expect_equal(count_users(con), 1)
})

test_that("auto-login by cookie works, the token is not reissued", {
  con <- auth_db()
  token <- aa_issue_token(con, "ivan")

  log <- run_auth(con, settings = aa_settings(cookie_mode = "legacy"), {
    session$setInputs(cookie = token)
    expect_true(session$returned$logged_in())
    expect_equal(session$returned$user()$login, "ivan")
  })

  expect_equal(log$names(), "login_success")
  expect_equal(log$events[[1]]$value, "cookie")
  expect_equal(nrow(rows_of(con, "auth_sessions")), 1)
})

test_that("a cookie cannot bypass mandatory 2FA enrollment (#noissue)", {
  con <- auth_db()
  token <- aa_issue_token(con, "ivan")
  settings <- aa_settings(
    totp_enabled = TRUE,
    totp_key = "a-long-random-key-for-the-tests",
    totp_required_roles = "user",
    cookie_mode = "legacy"
  )

  run_auth(con, settings = settings, {
    session$setInputs(cookie = token)
    expect_false(session$returned$logged_in())
    expect_null(session$returned$token())
    expect_true(grepl("login_btn", form_html(output), fixed = TRUE))
  })

  expect_null(aa_find_session_user(con, token))
})

test_that("a foreign, revoked and blocked user's token does not let in", {
  con <- auth_db()
  revoked <- aa_issue_token(con, "ivan")
  aa_revoke_token(con, revoked)
  raw_user(con, "boss", "admin")
  blocked_token <- aa_issue_token(con, "alsey")
  aa_set_blocked(con, "alsey", TRUE, acting_login = "ivan")

  for (token in c("not-a-token", revoked, blocked_token)) {
    run_auth(con, settings = aa_settings(cookie_mode = "legacy"), {
      session$setInputs(cookie = token)
      expect_false(session$returned$logged_in())
    })
  }
})

test_that("with auto-login off the cookie is ignored, tokens are not issued", {
  con <- auth_db()
  token <- aa_issue_token(con, "ivan")

  run_auth(
    con,
    settings = aa_settings(autologin = FALSE, cookie_mode = "legacy"),
    {
      session$setInputs(cookie = token)
      expect_false(session$returned$logged_in())

      session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
      expect_true(session$returned$logged_in())
    }
  )

  expect_equal(nrow(rows_of(con, "auth_sessions")), 1)
})

test_that("sign-out revokes the token, resets the user and sends logout", {
  con <- auth_db()

  log <- run_auth(con, {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    expect_true(session$returned$logged_in())

    session$returned$logout()
    expect_false(session$returned$logged_in())
    expect_null(session$returned$user())
  })

  expect_equal(log$names(), c("login_success", "logout"))
  expect_equal(rows_of(con, "auth_sessions")$revoked, 1)
})

test_that("forced sign-out sends session_forced_logout with the reason", {
  con <- auth_db()

  log <- run_auth(con, {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    session$returned$logout(reason = "role_changed")
  })

  expect_equal(log$names(), c("login_success", "session_forced_logout"))
  expect_equal(log$events[[2]]$value, "role_changed")
})

test_that("after sign-out the cookie no longer works", {
  con <- auth_db()
  token <- NULL

  run_auth(con, settings = aa_settings(cookie_mode = "legacy"), {
    session$setInputs(cookie = aa_issue_token(con, "ivan"))
    token <- rows_of(con, "auth_sessions")$token_hash
    session$returned$logout()
  })

  expect_equal(rows_of(con, "auth_sessions")$revoked, 1)
})

test_that("title and texts come from the settings, logo and Russian language", {
  con <- auth_db()

  run_auth(
    con,
    settings = aa_settings(texts = aa_texts("ru")),
    title = "My App",
    logo = "logo.png",
    {
      session$flushReact()
      html <- form_html(output)
      expect_match(html, "My App", fixed = TRUE)
      expect_match(html, "logo.png", fixed = TRUE)
      expect_match(html, aa_text(aa_texts("ru"), "login_button"), fixed = TRUE)
      expect_false(grepl("Sign in", html, fixed = TRUE))
    }
  )
})

test_that("an event hook failure does not prevent sign-in", {
  con <- auth_db()
  log <- auth_events()
  log$hook <- function(event, user, session_id, value) stop("log unavailable")

  suppressMessages(run_auth(con, log = log, {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    expect_true(session$returned$logged_in())
  }))
})

test_that("sign-out on all devices revokes all of the user's tokens, sends an event and signs out", {
  con <- auth_db()
  other_device <- aa_issue_token(con, "ivan")
  other_user <- aa_issue_token(con, "alsey")

  log <- run_auth(con, {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    own <- session$returned$token()
    expect_false(is.null(aa_find_session_user(con, other_device)))

    session$returned$logout_all(reload = FALSE)

    expect_false(session$returned$logged_in())
    expect_null(aa_find_session_user(con, own))
    expect_null(aa_find_session_user(con, other_device))
  })

  expect_false(is.null(aa_find_session_user(con, other_user)))
  expect_equal(log$names(), c("login_success", "sessions_revoked", "logout"))
  expect_equal(log$events[[2]]$user, "ivan")
  expect_equal(log$events[[2]]$value, "ivan")
})

test_that("sign-out on all devices without sign-in does nothing", {
  con <- auth_db()
  token <- aa_issue_token(con, "ivan")

  log <- run_auth(con, {
    expect_false(session$returned$logout_all(reload = FALSE))
  })

  expect_length(log$events, 0)
  expect_false(is.null(aa_find_session_user(con, token)))
})

test_that("after sign-out on all devices the cookie of the open session no longer works", {
  con <- auth_db()

  run_auth(con, settings = aa_settings(cookie_mode = "legacy"), {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    own <- session$returned$token()
    session$returned$logout_all(reload = FALSE)
    session$setInputs(cookie = own)
    expect_false(session$returned$logged_in())
  })
})

# --- self-registration -------------------------------------------------------

auth_reg_box <- function() {
  box <- new.env(parent = emptyenv())
  box$sent <- list()
  box
}

auth_reg_settings <- function(box = auth_reg_box(), ..., verify = TRUE) {
  args <- list(
    registration_enabled = TRUE,
    registration_verify_email = verify,
    registration_role = "viewer",
    reset_base_url = "https://apps.example.com/my_app",
    send_reset = function(email, link, login) {
      box$sent[[length(box$sent) + 1]] <- list(
        email = email,
        link = link,
        login = login
      )
    }
  )
  do.call(aa_settings, utils::modifyList(args, list(...)))
}

with_auth_url <- function(search, env = parent.frame()) {
  testthat::local_mocked_bindings(
    aa_url_search = function(session) search,
    .package = "appauth",
    .env = env
  )
}

test_that("the registration link and form have stable markup", {
  con <- auth_db()
  settings <- auth_reg_settings()

  run_auth(con, settings = settings, {
    session$flushReact()
    html <- form_html(output)
    expect_match(html, "register_link", fixed = TRUE)
    expect_match(html, aa_text(settings, "registration_link"), fixed = TRUE)
    expect_snapshot(html)

    session$setInputs(register_link = 1)
    html <- form_html(output)
    expect_match(html, "register_login", fixed = TRUE)
    expect_match(html, "register_email", fixed = TRUE)
    expect_match(html, "register_password", fixed = TRUE)
    expect_match(html, "register_confirm", fixed = TRUE)
    expect_match(html, "register_btn", fixed = TRUE)
    expect_snapshot(html)
  })
})

test_that("registration without email confirmation signs the visitor in with the configured role", {
  con <- auth_db()
  box <- auth_reg_box()
  settings <- auth_reg_settings(box, verify = FALSE)

  log <- run_auth(con, settings = settings, {
    session$setInputs(register_link = 1)
    session$setInputs(
      register_login = "worker",
      register_email = "worker@example.com",
      register_password = "Zx7!qLm2@wR9#pKs",
      register_confirm = "Zx7!qLm2@wR9#pKs",
      register_btn = 1
    )
    expect_true(session$returned$logged_in())
    expect_equal(session$returned$user(), list(login = "worker", role = "viewer"))
  })

  expect_equal(log$names(), c("registration_requested", "registration_confirmed", "login_success"))
  expect_equal(log$events[[1]]$value, "created")
  expect_equal(log$events[[3]]$value, "registration")
  expect_length(box$sent, 0)
  expect_equal(
    tquery(con, "SELECT email, role FROM users WHERE login = ?", params = list("worker")),
    data.frame(email = "worker@example.com", role = "viewer", stringsAsFactors = FALSE)
  )
})

test_that("registration with email confirmation shows a generic answer and creates no account", {
  con <- auth_db()
  box <- auth_reg_box()
  settings <- auth_reg_settings(box)

  log <- run_auth(con, settings = settings, {
    session$setInputs(register_link = 1)
    session$setInputs(
      register_login = "worker",
      register_email = "worker@example.com",
      register_password = "Zx7!qLm2@wR9#pKs",
      register_confirm = "Zx7!qLm2@wR9#pKs",
      register_btn = 1
    )
    expect_match(output$message, "If the address is available", fixed = TRUE)
    expect_match(form_html(output), "login_btn", fixed = TRUE)
    expect_false(session$returned$logged_in())
  })

  expect_equal(log$names(), "registration_requested")
  expect_equal(log$events[[1]]$value, "sent")
  expect_length(box$sent, 1)
  expect_null(aa_get_user(con, "worker"))
  expect_equal(tquery(con, "SELECT login, email, used FROM registrations")$login, "worker")
})

test_that("the ?register= link confirms the account and signs the visitor in", {
  con <- auth_db()
  box <- auth_reg_box()
  settings <- auth_reg_settings(box)
  aa_register_user(con, "worker", "Zx7!qLm2@wR9#pKs", "worker@example.com", settings)
  token <- sub("^.*register=", "", box$sent[[1]]$link)
  with_auth_url(paste0("?register=", token))

  log <- run_auth(con, settings = settings, {
    session$flushReact()
    expect_true(session$returned$logged_in())
    expect_equal(session$returned$user(), list(login = "worker", role = "viewer"))
    expect_false(grepl("register=", form_html(output), fixed = TRUE))
  })

  expect_equal(log$names(), c("registration_confirmed", "login_success"))
  expect_equal(log$events[[2]]$value, "registration")
  expect_false(is.null(aa_get_user(con, "worker")))
  expect_null(aa_registration_token_login(con, token))
  expect_equal(tquery(con, "SELECT used FROM registrations")$used, 1L)
})
