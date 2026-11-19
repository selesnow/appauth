# Password recovery by email: user emails, link request, password change
# by token and the sign-in module UI. Emails are intercepted by the mailbox() box.

mailbox <- function() {
  box <- new.env()
  box$sent <- list()
  box$send <- function(email, link, login) {
    box$sent[[length(box$sent) + 1]] <- list(email = email, link = link, login = login)
  }
  box$token <- function(i = length(box$sent)) {
    sub(".*reset=", "", box$sent[[i]]$link)
  }
  box
}

reset_settings <- function(box, ...) {
  aa_settings(
    reset_enabled  = TRUE,
    reset_base_url = "https://apps.example.com/my_app",
    send_reset     = box$send,
    ...
  )
}

# database: user ann with an address, bob without an address
reset_db <- function(env = parent.frame()) {
  con <- users_db(env)
  raw_user(con, "ann", password = aa_hash_password("old-password"))
  raw_user(con, "bob")
  aa_set_email(con, "ann", "Ann@Example.com")
  con
}

# replaces the page address bar: the mock Shiny session has no configurable one
with_url <- function(search, env = parent.frame()) {
  testthat::local_mocked_bindings(aa_url_search = function(session) search, .package = "appauth", .env = env)
}

reset_tokens_of <- function(con, login) {
  tquery(con, "SELECT * FROM password_resets WHERE user_login = ? ORDER BY id", params = list(login))
}

# --- user emails --------------------------------------------------------------

test_that("aa_set_email stores the address in lower case and removes it with an empty value", {
  con <- reset_db()

  expect_identical(aa_get_email(con, "ann"), "ann@example.com")
  expect_true(is.na(aa_get_email(con, "bob")))
  expect_true(is.na(aa_get_email(con, "nobody")))

  expect_true(aa_set_email(con, "bob", "  Bob@Example.COM "))
  expect_identical(aa_get_email(con, "bob"), "bob@example.com")

  expect_false(aa_set_email(con, "bob", NULL))
  expect_true(is.na(aa_get_email(con, "bob")))

  aa_set_email(con, "bob", "bob@example.com")
  expect_false(aa_set_email(con, "bob", ""))
  expect_true(is.na(aa_get_email(con, "bob")))
})

test_that("aa_set_email rejects a bad format, a taken address and an unknown user", {
  con <- reset_db()

  for (bad in c("no-at-sign", "a@b", "a b@example.com", "@example.com", "a@@example.com", "a@example.")) {
    expect_error(aa_set_email(con, "bob", bad), class = "appauth_error_user", info = bad)
  }

  err <- tryCatch(aa_set_email(con, "bob", "ANN@example.com"), appauth_error_user = identity)
  expect_s3_class(err, "appauth_error_user")
  expect_identical(err$reason, "email_exists")

  # one's own address is not considered taken
  expect_true(aa_set_email(con, "ann", "ann@example.com"))

  err <- tryCatch(aa_set_email(con, "nobody", "x@example.com"), appauth_error_user = identity)
  expect_identical(err$reason, "user_not_found")

  expect_true(is.na(aa_get_email(con, "bob")))
})

test_that("aa_create_user accepts an email and checks it before creating the user", {
  con <- reset_db()

  aa_create_user(con, "carl", "secret123", "user", email = "Carl@Example.com")
  expect_identical(aa_get_email(con, "carl"), "carl@example.com")

  expect_error(aa_create_user(con, "dina", "secret123", "user", email = "broken"), class = "appauth_error_user")
  expect_error(aa_create_user(con, "dina", "secret123", "user", email = "ann@example.com"), class = "appauth_error_user")
  expect_null(aa_get_user(con, "dina"))

  aa_create_user(con, "erik", "secret123", "user", email = "")
  expect_true(is.na(aa_get_email(con, "erik")))
})

# --- settings -------------------------------------------------------------------

test_that("recovery settings: off by default, enabling requires a function and an address", {
  s <- aa_settings()
  expect_false(s$reset_enabled)
  expect_null(s$send_reset)
  expect_equal(s$reset_ttl_minutes, 60)
  expect_equal(s$reset_max_per_hour, 3)

  expect_error(aa_settings(reset_enabled = TRUE), class = "appauth_error_settings")
  expect_error(aa_settings(reset_enabled = TRUE, send_reset = function(email, link, login) NULL), class = "appauth_error_settings")
  expect_error(aa_settings(reset_enabled = TRUE, reset_base_url = "https://x.test"), class = "appauth_error_settings")
  expect_error(aa_settings(send_reset = "mail"), class = "appauth_error_settings")
  expect_error(aa_settings(reset_base_url = 1), class = "appauth_error_settings")
  expect_error(aa_settings(reset_ttl_minutes = 0), class = "appauth_error_settings")
  expect_error(aa_settings(reset_max_per_hour = -1), class = "appauth_error_settings")

  ok <- reset_settings(mailbox())
  expect_true(ok$reset_enabled)
  expect_output(print(ok), "Password recovery by email: enabled")
  expect_output(print(s), "Password recovery by email: disabled")
})

test_that("aa_settings_from_list understands recovery settings", {
  s <- aa_settings_from_list(list(reset_ttl_minutes = 15, reset_max_per_hour = 1))
  expect_equal(s$reset_ttl_minutes, 15)
  expect_equal(s$reset_max_per_hour, 1)
})

# --- link request ---------------------------------------------------------------

test_that("a request by login and by email sends an email with a link and stores only the hash", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)

  res <- aa_request_password_reset(con, "ann", settings)
  expect_true(res$sent)
  expect_identical(res$reason, "sent")
  expect_identical(res$login, "ann")

  expect_length(box$sent, 1)
  expect_identical(box$sent[[1]]$email, "ann@example.com")
  expect_identical(box$sent[[1]]$login, "ann")
  expect_match(box$sent[[1]]$link, "^https://apps\\.example\\.com/my_app/\\?reset=[0-9a-f]{64}$")

  rows <- reset_tokens_of(con, "ann")
  expect_equal(nrow(rows), 1)
  expect_false(grepl(box$token(), paste(unlist(rows), collapse = " "), fixed = TRUE))
  expect_identical(rows$token_hash, aa_token_hash(box$token()))
  expect_equal(rows$used, 0)

  # the address is entered in any case and with spaces
  res <- aa_request_password_reset(con, "  ANN@example.com ", settings)
  expect_true(res$sent)
  expect_identical(res$login, "ann")
  expect_length(box$sent, 2)
})

test_that("the link is built from the app address with a trailing slash and with parameters", {
  con <- reset_db()
  box <- mailbox()

  aa_request_password_reset(con, "ann", aa_settings(
    reset_enabled = TRUE, send_reset = box$send, reset_base_url = "https://apps.example.com/app/"
  ))
  expect_match(box$sent[[1]]$link, "^https://apps\\.example\\.com/app/\\?reset=")

  aa_request_password_reset(con, "ann", aa_settings(
    reset_enabled = TRUE, send_reset = box$send, reset_base_url = "https://apps.example.com/?app=1"
  ))
  expect_match(box$sent[[2]]$link, "^https://apps\\.example\\.com/\\?app=1&reset=")
})

test_that("no email is sent if the user does not exist, has no address, is blocked or the feature is off", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)

  expect_identical(aa_request_password_reset(con, "nobody", settings)$reason, "no_user")
  expect_identical(aa_request_password_reset(con, "nobody@example.com", settings)$reason, "no_user")
  expect_identical(aa_request_password_reset(con, "", settings)$reason, "no_user")
  expect_identical(aa_request_password_reset(con, NULL, settings)$reason, "no_user")
  expect_identical(aa_request_password_reset(con, "bob", settings)$reason, "no_email")

  aa_set_blocked(con, "ann", TRUE)
  expect_identical(aa_request_password_reset(con, "ann", settings)$reason, "blocked")

  expect_identical(aa_request_password_reset(con, "ann", aa_settings())$reason, "disabled")

  expect_length(box$sent, 0)
  expect_equal(nrow(reset_tokens_of(con, "ann")), 0)
})

test_that("a new request consumes the previous link", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)

  aa_request_password_reset(con, "ann", settings)
  aa_request_password_reset(con, "ann", settings)

  expect_null(aa_reset_token_login(con, box$token(1)))
  expect_identical(aa_reset_token_login(con, box$token(2)), "ann")
})

test_that("limits: per user per hour and overall per minute", {
  con <- reset_db()
  box <- mailbox()

  settings <- reset_settings(box, reset_max_per_hour = 2)
  expect_true(aa_request_password_reset(con, "ann", settings)$sent)
  expect_true(aa_request_password_reset(con, "ann", settings)$sent)
  res <- aa_request_password_reset(con, "ann", settings)
  expect_false(res$sent)
  expect_identical(res$reason, "throttled")
  expect_length(box$sent, 2)

  # requests older than an hour do not count toward the limit
  texec(con, "UPDATE password_resets SET created_at = datetime('now', '-2 hours')")
  expect_true(aa_request_password_reset(con, "ann", settings)$sent)

  # overall limit across all users
  con <- reset_db()
  aa_set_email(con, "bob", "bob@example.com")
  box <- mailbox()
  settings <- reset_settings(box, reset_max_per_minute = 1)
  expect_true(aa_request_password_reset(con, "ann", settings)$sent)
  expect_identical(aa_request_password_reset(con, "bob", settings)$reason, "throttled")
})

test_that("an email sending error does not abort the request and consumes the token", {
  con <- reset_db()
  settings <- aa_settings(
    reset_enabled = TRUE, reset_base_url = "https://x.test",
    send_reset = function(email, link, login) stop("smtp is down")
  )

  expect_message(res <- aa_request_password_reset(con, "ann", settings), "smtp is down")
  expect_false(res$sent)
  expect_identical(res$reason, "send_failed")
  expect_equal(reset_tokens_of(con, "ann")$used, 1)
})

# --- password change by link ----------------------------------------------------

test_that("password change by link: the password changes, sign-in works, the token is one-time", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)
  aa_request_password_reset(con, "ann", settings)
  token <- box$token()

  expect_identical(aa_reset_token_login(con, token), "ann")
  expect_identical(aa_reset_password_with_token(con, token, "brand-new-pass", settings), "ann")

  expect_null(aa_authenticate(con, "ann", "old-password"))
  expect_equal(aa_authenticate(con, "ann", "brand-new-pass")$login, "ann")

  expect_null(aa_reset_token_login(con, token))
  err <- tryCatch(aa_reset_password_with_token(con, token, "another-pass-1", settings), appauth_error_user = identity)
  expect_identical(err$reason, "reset_link_invalid")
  expect_null(aa_authenticate(con, "ann", "another-pass-1"))
})

test_that("after a change by link sessions are revoked, other links consumed, the lock and must_change cleared", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)

  session_token <- aa_issue_token(con, "ann")
  texec(con, "UPDATE users SET must_change = 1 WHERE login = 'ann'")
  for (i in 1:5) aa_record_attempt(con, "ann", FALSE, settings)
  expect_gt(aa_login_lock_remaining(con, "ann", settings), 0)

  aa_request_password_reset(con, "ann", settings)
  # the second link consumes the first, so we simulate two live links manually
  texec(
    con, "INSERT INTO password_resets (user_login, token_hash, expires_at) VALUES ('ann', 'other', datetime('now', '+1 hours'))"
  )

  aa_reset_password_with_token(con, box$token(), "brand-new-pass", settings)

  expect_null(aa_find_session_user(con, session_token))
  expect_true(all(reset_tokens_of(con, "ann")$used == 1))
  expect_equal(aa_login_lock_remaining(con, "ann", settings), 0)
  expect_equal(aa_authenticate(con, "ann", "brand-new-pass")$must_change, 0)
})

test_that("a wrong, expired and foreign token does not change the password", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)
  aa_request_password_reset(con, "ann", settings)
  token <- box$token()

  for (bad in list(NULL, NA_character_, "", "abc", strrep("0", 64), toupper(token))) {
    expect_error(aa_reset_password_with_token(con, bad, "brand-new-pass", settings), class = "appauth_error_user")
  }

  texec(con, "UPDATE password_resets SET expires_at = datetime('now', '-1 minutes')")
  expect_null(aa_reset_token_login(con, token))
  err <- tryCatch(aa_reset_password_with_token(con, token, "brand-new-pass", settings), appauth_error_user = identity)
  expect_identical(err$reason, "reset_link_invalid")

  expect_equal(aa_authenticate(con, "ann", "old-password")$login, "ann")
})

test_that("a weak password is rejected without spending the token", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box, password_policy = "reject")
  aa_request_password_reset(con, "ann", settings)
  token <- box$token()

  expect_error(aa_reset_password_with_token(con, token, "short", settings), class = "appauth_error_user")
  expect_error(aa_reset_password_with_token(con, token, "password", settings), class = "appauth_error_user")
  expect_identical(aa_reset_token_login(con, token), "ann")

  expect_identical(aa_reset_password_with_token(con, token, "brand-new-pass", settings), "ann")
})

test_that("the token of a blocked or deleted user does not work", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)
  aa_request_password_reset(con, "ann", settings)
  token <- box$token()

  aa_set_blocked(con, "ann", TRUE)
  expect_null(aa_reset_token_login(con, token))
  expect_error(aa_reset_password_with_token(con, token, "brand-new-pass", settings), class = "appauth_error_user")

  aa_set_blocked(con, "ann", FALSE)
  expect_identical(aa_reset_token_login(con, token), "ann")

  aa_delete_user(con, "ann")
  expect_equal(nrow(reset_tokens_of(con, "ann")), 0)
  expect_null(aa_reset_token_login(con, token))
})

test_that("an administrator's password reset and a password change consume recovery links", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)

  aa_request_password_reset(con, "ann", settings)
  aa_set_password(con, "ann", "admin-chosen-1", settings)
  expect_null(aa_reset_token_login(con, box$token()))
})

test_that("aa_cleanup deletes old recovery tokens and keeps fresh ones", {
  con <- reset_db()
  texec(con, "
    INSERT INTO password_resets (user_login, token_hash, created_at, expires_at, used) VALUES
      ('ann', 'old_expired', datetime('now', '-3 days'), datetime('now', '-3 days', '+1 hours'), 0),
      ('ann', 'old_used',    datetime('now', '-3 days'), datetime('now', '+1 hours'),            1),
      ('ann', 'fresh_used',  datetime('now'),            datetime('now', '+1 hours'),            1),
      ('ann', 'fresh',       datetime('now'),            datetime('now', '+1 hours'),            0)")

  res <- aa_cleanup(con)

  expect_identical(res$password_resets, 2L)
  expect_identical(sort(reset_tokens_of(con, "ann")$token_hash), c("fresh", "fresh_used"))
})

test_that("migration 7 completes an old database and does not touch users", {
  skip_if_not_sqlite()
  con <- new_db()
  fixture_legacy_full(con)
  before <- rows_of(con, "users")

  res <- aa_init_db(con)

  expect_true(7L %in% res$applied)
  expect_true("email" %in% columns_of(con, "users"))
  expect_true("password_resets" %in% table_names(con))
  expect_identical(rows_of(con, "users")[, names(before)], before)
  expect_true(all(is.na(rows_of(con, "users")$email)))

  # a repeated run changes nothing
  expect_identical(aa_init_db(con)$applied, integer())
})

test_that("at the database level the address is unique, but many users may have no address", {
  con <- reset_db()
  raw_user(con, "carl")

  expect_error(texec(con, "UPDATE users SET email = 'ann@example.com' WHERE login = 'bob'"), "UNIQUE|Duplicate|duplicate")
  expect_no_error(texec(con, "UPDATE users SET email = NULL"))
})

# --- sign-in module --------------------------------------------------------------

test_that("the \"Forgot password?\" link exists only when recovery is enabled", {
  con <- reset_db()

  run_auth(con, {
    session$flushReact()
    expect_false(grepl("forgot_link", form_html(output), fixed = TRUE))
  })

  box <- mailbox()
  run_auth(con, settings = reset_settings(box), {
    session$flushReact()
    expect_true(grepl("forgot_link", form_html(output), fixed = TRUE))
  })
})

test_that("module: a link request shows one answer for a found and a not found user", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)
  log <- auth_events()

  run_auth(con, settings = settings, log = log, {
    session$setInputs(forgot_link = 1)
    session$flushReact()
    expect_true(grepl("forgot_identifier", form_html(output), fixed = TRUE))

    session$setInputs(forgot_identifier = "ann", forgot_btn = 1)
    found <- output$message

    session$setInputs(forgot_identifier = "ghost", forgot_btn = 2)
    missing <- output$message

    expect_identical(found, missing)
    expect_match(found, "60 min")

    session$setInputs(forgot_identifier = "bob", forgot_btn = 3)
    expect_identical(output$message, found)
  })

  expect_length(box$sent, 1)
  expect_identical(
    vapply(log$events, `[[`, character(1), "value"),
    c("sent", "no_user", "no_email")
  )
  expect_identical(vapply(log$events, `[[`, character(1), "user"), c("ann", "anonymous", "bob"))
  expect_true(all(log$names() == "password_reset_requested"))
})

test_that("module: the link from the email opens the new password form, the password changes, the token is consumed", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)
  aa_request_password_reset(con, "ann", settings)
  token <- box$token()
  log <- auth_events()

  with_url(paste0("?reset=", token))
  run_auth(con, settings = settings, log = log, {
    session$flushReact()

    html <- form_html(output)
    expect_true(grepl("reset_password", html, fixed = TRUE))
    expect_false(grepl("login_btn", html, fixed = TRUE))

    session$setInputs(reset_password = "brand-new-pass", reset_confirm = "different", reset_btn = 1)
    expect_identical(output$message, aa_text(settings, "passwords_mismatch"))
    expect_identical(aa_reset_token_login(con, token), "ann")

    session$setInputs(reset_password = "brand-new-pass", reset_confirm = "brand-new-pass", reset_btn = 2)
    expect_identical(output$message, aa_text(settings, "reset_done"))
    expect_true(grepl("login_btn", form_html(output), fixed = TRUE))
    expect_false(logged_in <- session$returned$logged_in())
  })

  expect_equal(aa_authenticate(con, "ann", "brand-new-pass")$login, "ann")
  expect_null(aa_reset_token_login(con, token))
  expect_identical(log$names(), "password_reset_done")
})

test_that("module: a wrong link shows a message and the sign-in form", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)
  log <- auth_events()

  with_url("?reset=0000")
  run_auth(con, settings = settings, log = log, {
    session$flushReact()

    expect_identical(output$message, aa_text(settings, "reset_link_invalid"))
    expect_true(grepl("login_btn", form_html(output), fixed = TRUE))
  })

  expect_identical(log$names(), "password_reset_failed")
})

test_that("module: the reset parameter is ignored if recovery is off", {
  con <- reset_db()
  log <- auth_events()

  with_url("?reset=0000")
  run_auth(con, log = log, {
    session$flushReact()
    expect_true(grepl("login_btn", form_html(output), fixed = TRUE))
  })

  expect_length(log$events, 0)
})

test_that("module: a weak password in reject mode does not spend the link", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box, password_policy = "reject")
  aa_request_password_reset(con, "ann", settings)
  token <- box$token()

  with_url(paste0("?reset=", token))
  run_auth(con, settings = settings, {
    session$flushReact()

    session$setInputs(reset_password = "password", reset_confirm = "password", reset_btn = 1)
    expect_true(grepl("reset_password", form_html(output), fixed = TRUE))
    expect_true(nzchar(output$message))
    expect_identical(aa_reset_token_login(con, token), "ann")
  })
})

# --- users module -----------------------------------------------------------------

test_that("users module: an administrator sets and removes an email, events and checks", {
  con <- users_fixture()
  log <- users_events()

  shiny::testServer(
    aa_users_server,
    args = list(conn = con, auth = fake_auth(), on_event = log$hook),
    expr = {
      session$setInputs(open = "ivan")
      session$setInputs(email = "Ivan@Example.com", save_email = 1)
      expect_identical(aa_get_email(con, "ivan"), "ivan@example.com")

      session$setInputs(email = "broken", save_email = 2)
      expect_identical(aa_get_email(con, "ivan"), "ivan@example.com")

      session$setInputs(email = "", save_email = 3)
      expect_true(is.na(aa_get_email(con, "ivan")))
    }
  )

  expect_identical(log$names(), c("email_changed", "email_changed"))
})

test_that("users module: a non-administrator cannot change an email", {
  con <- users_fixture()
  log <- users_events()

  shiny::testServer(
    aa_users_server,
    args = list(conn = con, auth = fake_auth("ivan", "user"), on_event = log$hook),
    expr = {
      session$setInputs(open = "boss")
      suppressWarnings(try(session$setInputs(email = "x@example.com", save_email = 1), silent = TRUE))
    }
  )

  expect_true(is.na(aa_get_email(con, "boss")))
})

test_that("the event catalog and texts contain the new recovery keys", {
  expect_true(all(c(
    "password_reset_requested", "password_reset_done", "password_reset_failed", "email_changed"
  ) %in% aa_events()$event))

  keys <- c("forgot_link", "forgot_done", "reset_link_invalid", "reset_done", "email_invalid", "email_exists")
  expect_true(all(keys %in% aa_text_keys()))
  expect_identical(names(aa_texts("ru")), names(aa_texts("en")))
})
