# Features of version 0.3.0: creation and last sign-in dates, weak password
# policy, a ready-made event handler, confirmation of user deletion.

# ---- creation and last sign-in dates -------------------------------------------

test_that("a new user gets created_at (UTC), last_login_at is empty", {
  con <- users_db()
  aa_create_user(con, "ivan", "secret123", "user")

  u <- aa_get_user(con, "ivan")

  expect_named(u, c("login", "role", "blocked", "created_at", "last_login_at"))
  expect_match(u$created_at, "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$")
  expect_lt(abs(as.numeric(difftime(as.POSIXct(u$created_at, tz = "UTC"), Sys.time(), units = "secs"))), 120)
  expect_true(is.na(u$last_login_at))
  expect_named(aa_list_users(con), c("login", "role", "blocked", "created_at", "last_login_at"))
})

test_that("the first administrator gets created_at too", {
  con <- users_db()
  aa_create_first_admin(con, "boss", "secret123")

  expect_false(is.na(aa_get_user(con, "boss")$created_at))
})

test_that("the migration completes the columns in an existing database, data is kept", {
  skip_if_not_sqlite()
  con <- new_db()
  texec(con, "CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, login TEXT UNIQUE NOT NULL,
                        password TEXT NOT NULL, role TEXT NOT NULL, blocked INTEGER NOT NULL DEFAULT 0)")
  texec(con, "INSERT INTO users (login, password, role) VALUES ('old', 'x', 'user')")

  # before the migration reading works, the dates are unknown
  before <- aa_list_users(con)
  expect_true(is.na(before$created_at) && is.na(before$last_login_at))

  aa_init_db(con)

  expect_true(all(c("created_at", "last_login_at") %in% columns_of(con, "users")))
  after <- aa_get_user(con, "old")
  expect_equal(after$login, "old")
  expect_true(is.na(after$created_at))
  expect_identical(aa_schema_version(con), 9L)
})

test_that("password sign-in updates last_login_at, cookie sign-in does not", {
  con <- auth_db()
  token <- aa_issue_token(con, "ivan")

  run_auth(con, {
    session$setInputs(cookie = token)
    expect_true(session$returned$logged_in())
  })
  expect_true(is.na(aa_get_user(con, "ivan")$last_login_at))

  run_auth(con, {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    expect_true(session$returned$logged_in())
  })
  expect_match(aa_get_user(con, "ivan")$last_login_at, "^[0-9]{4}-[0-9]{2}-[0-9]{2} ")
  expect_true(is.na(aa_get_user(con, "alsey")$last_login_at))
})

test_that("a wrong password does not change last_login_at", {
  con <- auth_db()

  run_auth(con, {
    session$setInputs(login = "ivan", password = "wrong-pass", login_btn = 1)
  })

  expect_true(is.na(aa_get_user(con, "ivan")$last_login_at))
})

test_that("creating the first administrator through the module records last_login_at", {
  con <- users_db()

  run_auth(con, {
    session$flushReact()
    session$setInputs(setup_login = "boss", setup_password = "secret123", setup_confirm = "secret123", setup_btn = 1)
    expect_true(session$returned$logged_in())
  })

  expect_false(is.na(aa_get_user(con, "boss")$last_login_at))
})

test_that("aa_format_db_time converts UTC to local time and fills in text for empty values", {
  withr::local_timezone("Asia/Tokyo")

  out <- appauth:::aa_format_db_time(c("2026-01-01 00:00:00", NA, ""), "none")

  expect_identical(out[2:3], c("none", "none"))
  expect_match(out[1], "^2026-01-01 [0-9]{2}:[0-9]{2}$")
  # a 9-hour difference if the TZ time zone was applied; otherwise at least the format is right
  if (identical(Sys.timezone(), "Asia/Tokyo")) expect_identical(out[1], "2026-01-01 09:00")
})

test_that("users overview: dates for display and texts for unknown dates", {
  con <- users_db()
  raw_user(con, "legacy")
  aa_create_user(con, "fresh", "secret123", "user")
  texec(con, "UPDATE users SET last_login_at = '2026-03-04 10:20:30' WHERE login = 'fresh'")

  ov <- aa_users_overview(con)

  expect_identical(ov$created[1], "unknown")
  expect_identical(ov$last_login[1], "never signed in")
  expect_match(ov$created[2], "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$")
  expect_match(ov$last_login[2], "^2026-03-0[34] ")
  expect_identical(ov$last_login_at[2], "2026-03-04 10:20:30")

  ru <- aa_users_overview(con, aa_settings(texts = aa_texts("ru")))
  expect_identical(ru$created[1], aa_text(aa_texts("ru"), "date_unknown"))
  expect_identical(ru$last_login[1], aa_text(aa_texts("ru"), "date_never"))
})

# ---- weak password policy -------------------------------------------------------

test_that("the password_policy setting: default value and validation", {
  expect_identical(aa_settings()$password_policy, "warn")
  expect_identical(aa_settings(password_policy = "reject")$password_policy, "reject")
  expect_identical(aa_settings_from_list(list(password_policy = "off"))$password_policy, "off")

  for (bad in list("strict", NA_character_, 1, c("off", "warn"), NULL, "")) {
    expect_error(aa_settings(password_policy = bad), class = "appauth_error_settings")
  }

  expect_output(print(aa_settings(password_policy = "reject")), "rejected")
})

test_that("password weaknesses: list, login, single character, case", {
  weak <- appauth:::aa_password_weakness

  expect_identical(weak("123456"), "password_common")
  expect_identical(weak("PassWord"), "password_common")
  expect_identical(weak("Morgan", login = "morgan"), "password_equals_login")
  expect_identical(weak("aaaaaaaa"), "password_repeated")
  expect_identical(weak("morgan", login = "someone"), NULL)
  expect_null(weak("long-and-unusual-phrase"))
  expect_null(weak("long-and-unusual-phrase", login = "ivan"))
  expect_null(weak(NULL))
  expect_null(weak(NA_character_))
})

test_that("off: a weak password is accepted without a warning", {
  s <- aa_settings(password_policy = "off")
  con <- users_db()

  expect_null(aa_validate_password("123456", s))
  expect_null(aa_weak_password_warning("123456", s))
  expect_no_error(aa_create_user(con, "ivan", "123456", "user", s))
})

test_that("warn: the password is accepted, the warning gives the reason text", {
  s <- aa_settings()
  con <- users_db()

  expect_null(aa_validate_password("123456", s))
  expect_no_error(aa_create_user(con, "ivan", "123456", "user", s))
  expect_match(aa_weak_password_warning("123456", s), "weak.*common")
  expect_match(aa_weak_password_warning("morgan", s, login = "Morgan"), "same as the login")
  expect_match(aa_weak_password_warning("zzzzzz", s), "single repeated character")
  expect_null(aa_weak_password_warning("long-and-unusual-phrase", s))
  expect_false(identical(
    aa_weak_password_warning("123456", s),
    aa_weak_password_warning("123456", aa_settings(texts = aa_texts("ru")))
  ))
})

test_that("reject: a weak password is rejected on creation, reset, change and for the first administrator", {
  s <- aa_settings(password_policy = "reject")
  con <- users_db()

  expect_error(aa_create_first_admin(con, "boss", "123456", s), class = "appauth_error_user")
  expect_equal(count_users(con), 0)
  expect_true(aa_create_first_admin(con, "boss", "strong-passphrase", s))

  err <- tryCatch(aa_create_user(con, "ivan", "qwerty123", "user", s), appauth_error_user = identity)
  expect_s3_class(err, "appauth_error_user")
  expect_identical(err$reason, "password_common")
  expect_equal(count_users(con), 1)

  err <- tryCatch(aa_create_user(con, "Morgan", "morgan", "user", s), appauth_error_user = identity)
  expect_identical(err$reason, "password_equals_login")

  aa_create_user(con, "ivan", "strong-passphrase", "user", s)
  expect_error(aa_set_password(con, "ivan", "password", s), class = "appauth_error_user")
  expect_error(aa_change_own_password(con, "ivan", "strong-passphrase", "1234567", s), class = "appauth_error_user")
  expect_false(is.null(aa_authenticate(con, "ivan", "strong-passphrase")))

  expect_match(aa_validate_password("123456", s), "common")
  expect_match(aa_validate_password("ivan11", aa_settings(password_policy = "reject", password_min = 4), login = "IVAN11"), "same as the login")
  expect_null(aa_validate_password("long-and-unusual-phrase", s))
})

test_that("length rules are checked before weaknesses", {
  s <- aa_settings(password_policy = "reject")

  expect_match(aa_validate_password("123", s), "at least")
})

test_that("users module: warn lets a weak password through and reports it with an event", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(add = 1)
    session$setInputs(new_login = "weak1", new_user_password = "123456", new_user_confirm = "123456", new_user_role = "user", add_confirm = 1)
  })

  expect_false(is.null(aa_get_user(con, "weak1")))
  expect_equal(log$names(), c("user_added", "weak_password_set"))
  expect_equal(log$events[[2]]$value, "weak1: password_common")
})

test_that("users module: a strong password gives no weak password event", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(add = 1)
    session$setInputs(new_login = "strong1", new_user_password = "long-and-unusual-phrase", new_user_confirm = "long-and-unusual-phrase", new_user_role = "user", add_confirm = 1)
  })

  expect_equal(log$names(), "user_added")
})

test_that("users module: reject rejects a weak password on adding and on reset", {
  con <- users_fixture()
  s <- aa_settings(password_policy = "reject")

  log <- run_users(con, {
    session$setInputs(add = 1)
    session$setInputs(new_login = "weak1", new_user_password = "123456", new_user_confirm = "123456", new_user_role = "user", add_confirm = 1)
    expect_match(output$add_message, "common")

    session$setInputs(open = "ivan")
    session$setInputs(new_password = "password", new_password_confirm = "password", reset_password = 1)
  }, settings = s)

  expect_null(aa_get_user(con, "weak1"))
  expect_false(is.null(aa_authenticate(con, "ivan", "secret123")))
  expect_length(log$events, 0)
})

test_that("users module: resetting to a weak password in warn mode gives an event", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(new_password = "password", new_password_confirm = "password", reset_password = 1)
  })

  expect_equal(log$names(), c("password_reset", "weak_password_set"))
  expect_equal(log$events[[2]]$value, "ivan: password_common")
})

test_that("sign-in module: a weak password of the first administrator and of a password change gives an event", {
  con <- users_db()

  log <- run_auth(con, {
    session$flushReact()
    session$setInputs(setup_login = "boss", setup_password = "123456", setup_confirm = "123456", setup_btn = 1)
    expect_true(session$returned$logged_in())
  })
  expect_true("weak_password_set" %in% log$names())

  con <- users_db()
  aa_create_user(con, "ann", "secret123", "user", must_change = TRUE)
  log <- run_auth(con, {
    session$setInputs(login = "ann", password = "secret123", login_btn = 1)
    session$setInputs(change_password = "password", change_confirm = "password", change_btn = 1)
    expect_true(session$returned$logged_in())
  })
  expect_true("weak_password_set" %in% log$names())
  expect_equal(log$events[[which(log$names() == "weak_password_set")]]$value, "ann: password_common")
})

test_that("password change module: a weak new password in warn mode is accepted and gives an event", {
  con <- users_db()
  aa_create_user(con, "ann", "secret123", "user")
  auth <- fake_auth("ann", "user")
  auth$token <- function() NULL

  log <- password_run(con, auth, {
    session$flushReact()
    session$setInputs(old = "secret123", new = "123456", confirm = "123456", change = 1)
  })

  expect_equal(log$names(), c("password_changed", "weak_password_set"))
  expect_false(is.null(aa_authenticate(con, "ann", "123456")))
})

# ---- confirmation of user deletion ----------------------------------------------

test_that("the \"Delete\" button only opens the confirmation, the user stays", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(delete = 1)
  })

  expect_false(is.null(aa_get_user(con, "ivan")))
  expect_length(log$events, 0)
})

test_that("canceling the deletion confirmation: the user stays, a confirmation after cancel does not work", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(delete = 1)
    session$setInputs(delete_cancel = 1)
    session$setInputs(delete_confirm = 1)
  })

  expect_false(is.null(aa_get_user(con, "ivan")))
  expect_length(log$events, 0)
})

test_that("a confirmation without pressing \"Delete\" deletes nothing (forged request)", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(delete_confirm = 1)
  })

  expect_equal(count_users(con), 3)
  expect_length(log$events, 0)
})

test_that("the confirmation deletes only the user the window was shown for", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(delete = 1)
    session$setInputs(open = "boss") # another card was opened while the window was up
    session$setInputs(delete_confirm = 1)
  })

  expect_false(is.null(aa_get_user(con, "ivan")))
  expect_false(is.null(aa_get_user(con, "boss")))
  expect_length(log$events, 0)
})

test_that("the deletion confirmation works once", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(delete = 1)
    session$setInputs(delete_confirm = 1)
    session$setInputs(delete_confirm = 2)
  })

  expect_null(aa_get_user(con, "ivan"))
  expect_equal(log$names(), "user_removed")
})

test_that("a non-administrator cannot confirm a deletion", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(delete = 1)
    session$setInputs(delete_confirm = 1)
  }, auth = fake_auth("ivan", "user"))

  expect_equal(count_users(con), 3)
  expect_true(all(log$names() == "access_denied"))
})

# ---- ready-made event handler ---------------------------------------------------

collect_writer <- function() {
  rows <- new.env()
  rows$items <- list()
  rows$writer <- function(action, user, session_id, value) {
    rows$items[[length(rows$items) + 1]] <- list(action = action, user = user, session_id = session_id, value = value)
  }
  rows
}

test_that("aa_event_logger: without settings writes all events under event keys", {
  rows <- collect_writer()
  handler <- aa_event_logger(rows$writer)

  handler("login_failed", "boss", "s1", "")
  handler("user_added", "boss", "s1", "olga (user)")

  expect_length(rows$items, 2)
  expect_identical(rows$items[[1]], list(action = "login_failed", user = "boss", session_id = "s1", value = ""))
  expect_identical(rows$items[[2]]$value, "olga (user)")
})

test_that("aa_event_logger: actions renames and filters events", {
  rows <- collect_writer()
  handler <- aa_event_logger(rows$writer, actions = c(login_failed = "Login failed", user_added = "User add"))

  handler("login_failed", "boss", "s1", "")
  handler("logout", "boss", "s1", "")
  handler("user_added", "boss", "s1", "x")

  expect_identical(vapply(rows$items, `[[`, "", "action"), c("Login failed", "User add"))
})

test_that("aa_event_logger: events filters events, enabled switches on and off on the fly", {
  rows <- collect_writer()
  on <- TRUE
  handler <- aa_event_logger(rows$writer, events = c("login_failed", "logout"), enabled = function(event) on)

  handler("login_failed", "a", "s", "")
  handler("user_added", "a", "s", "")
  on <- FALSE
  handler("logout", "a", "s", "")
  on <- TRUE
  handler("logout", "a", "s", "")

  expect_identical(vapply(rows$items, `[[`, "", "action"), c("login_failed", "logout"))

  off <- aa_event_logger(rows$writer, enabled = FALSE)
  n <- length(rows$items)
  off("login_failed", "a", "s", "")
  expect_length(rows$items, n)
})

test_that("aa_event_logger: format_value transforms the value", {
  rows <- collect_writer()
  handler <- aa_event_logger(
    rows$writer,
    format_value = function(event, user, value) if (event == "user_added") sub(" \\(.*\\)$", "", value) else value
  )

  handler("user_added", "boss", "s", "olga (user)")
  handler("user_removed", "boss", "s", "ivan")

  expect_identical(rows$items[[1]]$value, "olga")
  expect_identical(rows$items[[2]]$value, "ivan")
})

test_that("aa_event_logger: settings errors are clear, unknown events are caught", {
  w <- function(action, user, session_id, value) NULL

  expect_error(aa_event_logger("not a function"), class = "appauth_error_settings")
  expect_error(aa_event_logger(w, actions = c("a", "b")), class = "appauth_error_settings")
  expect_error(aa_event_logger(w, actions = c(no_such_event = "x")), "unknown events")
  expect_error(aa_event_logger(w, events = "no_such_event"), "unknown events")
  expect_error(aa_event_logger(w, enabled = NA), class = "appauth_error_settings")
  expect_error(aa_event_logger(w, enabled = "yes"), class = "appauth_error_settings")
  expect_error(aa_event_logger(w, format_value = "x"), class = "appauth_error_settings")
})

test_that("aa_event_logger in a module: a write failure does not interrupt the package action", {
  con <- auth_db()
  handler <- aa_event_logger(function(action, user, session_id, value) stop("log unavailable"))

  expect_message(
    run_auth(con, {
      session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
      expect_true(session$returned$logged_in())
    }, log = list(hook = handler)),
    "error in on_event"
  )
})

test_that("aa_event_logger works as on_event of the modules and writes real events", {
  con <- users_fixture()
  rows <- collect_writer()
  handler <- aa_event_logger(rows$writer, actions = c(user_blocked = "User block"))

  run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(block = 1)
  }, log = list(hook = handler))

  expect_length(rows$items, 1)
  expect_identical(rows$items[[1]]$action, "User block")
  expect_identical(rows$items[[1]]$user, "alsey")
  expect_identical(rows$items[[1]]$value, "ivan")
})

test_that("the event catalog contains weak_password_set", {
  expect_true("weak_password_set" %in% aa_events()$event)
})
