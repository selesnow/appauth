# ---- login key --------------------------------------------------------------------

test_that("the login key is the exact login: case and whitespace are kept", {
  s <- aa_settings()

  expect_identical(aa_login_key("Alsey", s), "Alsey")
  expect_identical(aa_login_key("alsey", s), "alsey")
  expect_identical(aa_login_key(" alsey", s), " alsey")
  expect_identical(
    aa_login_key("\u0418\u0432\u0430\u043d", s),
    "\u0418\u0432\u0430\u043d"
  )
})

test_that("empty logins and non-strings have no key", {
  s <- aa_settings()

  for (bad in list("", "   ", "\t", NA_character_, NULL, 5, c("a", "b"))) {
    expect_identical(aa_login_key(bad, s), "")
  }
})

test_that("a too long login is truncated to login_max characters", {
  expect_identical(nchar(aa_login_key(strrep("a", 500), aa_settings())), 64L)
  expect_identical(
    nchar(aa_login_key(strrep("\u044f", 500), aa_settings(login_max = 10))),
    10L
  )
})

# ---- recording attempts -----------------------------------------------------------------

test_that("aa_record_attempt records the exact login and result", {
  con <- users_db()

  expect_true(aa_record_attempt(con, "Alsey", FALSE))
  expect_true(aa_record_attempt(con, "Alsey", TRUE))

  rows <- tquery(con, "SELECT login, success FROM login_attempts ORDER BY id")

  expect_identical(rows$login, c("Alsey", "Alsey"))
  expect_identical(rows$success, c(0L, 1L))
})

test_that("attempts with an empty login are not recorded", {
  con <- users_db()

  for (bad in list("", "   ", NA_character_, NULL, 5)) {
    expect_false(withVisible(aa_record_attempt(con, bad, FALSE))$value)
  }

  expect_identical(count_attempts(con), 0L)
  expect_false(withVisible(aa_record_attempt(con, "a", FALSE))$visible)
})

test_that("aa_record_attempt validates its arguments", {
  con <- users_db()

  expect_error(
    aa_record_attempt(con, "a", NA),
    class = "appauth_error_settings"
  )
  expect_error(
    aa_record_attempt(con, "a", "yes"),
    class = "appauth_error_settings"
  )
  expect_error(
    aa_record_attempt(list(), "a", FALSE),
    class = "appauth_error_connection"
  )
})

# ---- login lockout --------------------------------------------------------------

test_that("login is allowed below the limit and blocked for about lockout_minutes after it", {
  con <- users_db()

  for (i in 1:4) {
    aa_record_attempt(con, "alsey", FALSE)
  }
  expect_identical(aa_login_lock_remaining(con, "alsey"), 0L)

  aa_record_attempt(con, "alsey", FALSE)
  remaining <- aa_login_lock_remaining(con, "alsey")

  expect_type(remaining, "integer")
  expect_gt(remaining, 14 * 60)
  expect_lte(remaining, 15 * 60)
})

test_that("another login is not blocked", {
  con <- users_db()
  for (i in 1:5) {
    aa_record_attempt(con, "alsey", FALSE)
  }

  expect_gt(aa_login_lock_remaining(con, "alsey"), 0)
  expect_identical(aa_login_lock_remaining(con, "ida"), 0L)
})

test_that("the login is matched EXACTLY: other case and whitespace are different logins with separate counters", {
  con <- users_db()
  for (i in 1:5) {
    aa_record_attempt(con, "alsey", FALSE)
  }

  expect_gt(aa_login_lock_remaining(con, "alsey"), 0)
  expect_identical(aa_login_lock_remaining(con, "Alsey"), 0L)
  expect_identical(aa_login_lock_remaining(con, "ALSEY"), 0L)
  expect_identical(aa_login_lock_remaining(con, " alsey"), 0L)
  expect_identical(aa_login_lock_remaining(con, "alsey "), 0L)

  # failures for a non-existent "Alsey" do not block the real "alsey"
  con2 <- users_db()
  for (i in 1:10) {
    aa_record_attempt(con2, "Alsey", FALSE)
  }

  expect_identical(aa_login_lock_remaining(con2, "alsey"), 0L)
  expect_gt(aa_login_lock_remaining(con2, "Alsey"), 0)
})

test_that("login pairs differing in case (like kiruka and Kiruka in a legacy app) do not interfere", {
  con <- users_db()

  for (i in 1:5) {
    aa_record_attempt(con, "Kiruka", FALSE)
  }
  for (i in 1:2) {
    aa_record_attempt(con, "kiruka", FALSE)
  }

  expect_gt(aa_login_lock_remaining(con, "Kiruka"), 0)
  expect_identical(aa_login_lock_remaining(con, "kiruka"), 0L)

  # a success of one does not reset the counter of the other
  aa_record_attempt(con, "kiruka", TRUE)
  expect_gt(aa_login_lock_remaining(con, "Kiruka"), 0)
})

test_that("non-ASCII logins are matched exactly", {
  con <- users_db()
  for (i in 1:5) {
    aa_record_attempt(con, "\u0418\u0432\u0430\u043d", FALSE)
  }

  expect_gt(aa_login_lock_remaining(con, "\u0418\u0432\u0430\u043d"), 0)
  expect_identical(aa_login_lock_remaining(con, "\u0438\u0432\u0430\u043d"), 0L)
})

test_that("a non-existent login is blocked the same way, an empty login never", {
  con <- users_db()
  for (i in 1:5) {
    aa_record_attempt(con, "no_such_user", FALSE)
  }

  expect_gt(aa_login_lock_remaining(con, "no_such_user"), 0)

  for (bad in list("", "   ", NA_character_, NULL)) {
    expect_identical(aa_login_lock_remaining(con, bad), 0L)
  }
})

test_that("a successful login resets the counter even if all records are made within one second", {
  con <- users_db()

  for (i in 1:3) {
    aa_record_attempt(con, "ida", FALSE)
  }
  aa_record_attempt(con, "ida", TRUE)
  for (i in 1:4) {
    aa_record_attempt(con, "ida", FALSE)
  }

  expect_identical(aa_login_lock_remaining(con, "ida"), 0L)

  aa_record_attempt(con, "ida", FALSE)

  expect_gt(aa_login_lock_remaining(con, "ida"), 0)
})

test_that("a success of another login does not reset the counter", {
  con <- users_db()

  for (i in 1:5) {
    aa_record_attempt(con, "alsey", FALSE)
  }
  aa_record_attempt(con, "ida", TRUE)

  expect_gt(aa_login_lock_remaining(con, "alsey"), 0)
})

test_that("window: old failures are not counted, the lockout is counted from the last failure", {
  con <- users_db()

  for (i in 1:5) {
    add_attempt(con, "old20", FALSE, minutes_ago = 20)
  }
  expect_identical(aa_login_lock_remaining(con, "old20"), 0L)

  for (i in 1:5) {
    add_attempt(con, "old16", FALSE, minutes_ago = 16)
  }
  expect_identical(aa_login_lock_remaining(con, "old16"), 0L)

  for (i in 1:4) {
    add_attempt(con, "mid", FALSE, minutes_ago = 14)
  }
  add_attempt(con, "mid", FALSE, minutes_ago = 10)
  remaining <- aa_login_lock_remaining(con, "mid")

  expect_gt(remaining, 4 * 60)
  expect_lte(remaining, 5 * 60 + 5)
})

test_that("thresholds come from the settings", {
  con <- users_db()
  s <- aa_settings(max_failed_logins = 3, lockout_minutes = 5)

  for (i in 1:2) {
    aa_record_attempt(con, "u", FALSE, s)
  }
  expect_identical(aa_login_lock_remaining(con, "u", s), 0L)

  aa_record_attempt(con, "u", FALSE, s)
  remaining <- aa_login_lock_remaining(con, "u", s)

  expect_gt(remaining, 4 * 60)
  expect_lte(remaining, 5 * 60)

  # with the default settings the same 3 attempts are not enough
  expect_identical(aa_login_lock_remaining(con, "u"), 0L)
})

test_that("logins sharing a prefix longer than login_max share one key (documented behavior)", {
  con <- users_db()
  s <- aa_settings(login_max = 10)

  for (i in 1:5) {
    aa_record_attempt(con, paste0(strrep("a", 10), "x"), FALSE, s)
  }

  expect_gt(aa_login_lock_remaining(con, paste0(strrep("a", 10), "y"), s), 0)
})

# ---- clearing a lockout --------------------------------------------------------------

test_that("aa_clear_attempts clears the lockout, successful attempts and other logins stay", {
  con <- users_db()
  for (i in 1:5) {
    aa_record_attempt(con, "alsey", FALSE)
  }
  for (i in 1:5) {
    aa_record_attempt(con, "ida", FALSE)
  }
  aa_record_attempt(con, "alsey", TRUE) # the success comes AFTER the failures: the counter would be reset anyway
  texec(con, "DELETE FROM login_attempts WHERE login = 'alsey' AND success = 1")

  expect_gt(aa_login_lock_remaining(con, "alsey"), 0)

  removed <- withVisible(aa_clear_attempts(con, "alsey"))

  expect_false(removed$visible)
  expect_equal(removed$value, 5)
  expect_identical(aa_login_lock_remaining(con, "alsey"), 0L)
  expect_gt(aa_login_lock_remaining(con, "ida"), 0)
})

test_that("aa_clear_attempts keeps successful attempts and leaves other case alone", {
  con <- users_db()
  aa_record_attempt(con, "alsey", TRUE)
  for (i in 1:3) {
    aa_record_attempt(con, "alsey", FALSE)
  }
  for (i in 1:3) {
    aa_record_attempt(con, "Alsey", FALSE)
  }

  aa_clear_attempts(con, "alsey")

  expect_identical(
    tquery(
      con,
      "SELECT COUNT(*) AS n FROM login_attempts WHERE login = 'alsey'"
    )$n,
    1L
  )
  expect_identical(
    tquery(
      con,
      "SELECT COUNT(*) AS n FROM login_attempts WHERE login = 'Alsey'"
    )$n,
    3L
  )
  expect_equal(aa_clear_attempts(con, ""), 0)
  expect_equal(aa_clear_attempts(con, NA_character_), 0)
})

# ---- global limit --------------------------------------------------------------------

test_that("global limit: 29 failures a minute across logins is not yet the limit, 30 is", {
  con <- users_db()

  for (i in 1:29) {
    add_attempt(con, paste0("spray", i), FALSE, seconds_ago = 5)
  }
  expect_false(aa_global_throttled(con))

  add_attempt(con, "spray30", FALSE, seconds_ago = 5)
  expect_true(aa_global_throttled(con))
})

test_that("the global limit does not count old failures or successful logins", {
  con <- users_db()

  for (i in 1:40) {
    add_attempt(con, paste0("old", i), FALSE, seconds_ago = 120)
  }
  for (i in 1:40) {
    add_attempt(con, paste0("ok", i), TRUE, seconds_ago = 5)
  }

  expect_false(aa_global_throttled(con))
})

test_that("the global limit comes from the settings", {
  con <- users_db()
  s <- aa_settings(max_failed_logins_per_minute = 2)

  add_attempt(con, "a", FALSE, seconds_ago = 5)
  expect_false(aa_global_throttled(con, s))

  add_attempt(con, "b", FALSE, seconds_ago = 5)
  expect_true(aa_global_throttled(con, s))
  expect_false(aa_global_throttled(con))
})

# ---- login gate ---------------------------------------------------------------------

test_that("the gate lets login through while there are no lockouts", {
  con <- users_db()

  gate <- aa_login_gate(con, "alsey")

  expect_true(gate$allowed)
  expect_true(is.na(gate$reason))
  expect_identical(gate$seconds, 0L)
  expect_true(is.na(gate$message))
  expect_identical(names(gate), c("allowed", "reason", "seconds", "message"))
})

test_that("the gate reports a login lockout with minutes in the right language", {
  con <- users_db()
  for (i in 1:5) {
    aa_record_attempt(con, "alsey", FALSE)
  }

  gate <- aa_login_gate(con, "alsey")

  expect_false(gate$allowed)
  expect_identical(gate$reason, "locked")
  expect_gt(gate$seconds, 14 * 60)
  expect_identical(gate$message, aa_text(aa_settings(), "locked", 15L))

  ru <- aa_settings(texts = aa_texts("ru"))
  gate_ru <- aa_login_gate(con, "alsey", ru)
  expect_identical(gate_ru$message, aa_text(ru, "locked", 15L))
  expect_false(identical(gate_ru$message, gate$message))

  # another login can still sign in
  expect_true(aa_login_gate(con, "ida")$allowed)
})

test_that("minutes in the message are rounded up and never zero", {
  con <- users_db()
  for (i in 1:4) {
    add_attempt(con, "u", FALSE, minutes_ago = 14)
  }
  add_attempt(con, "u", FALSE, seconds_ago = 14 * 60 + 40) # the lockout ends in less than a minute

  gate <- aa_login_gate(con, "u")

  expect_false(gate$allowed)
  expect_lte(gate$seconds, 60)
  expect_identical(gate$message, aa_text(aa_settings(), "locked", 1L))
})

test_that("under the global limit login is closed for everyone and this takes priority over a login lockout", {
  con <- users_db()
  for (i in 1:30) {
    add_attempt(con, paste0("spray", i), FALSE, seconds_ago = 5)
  }

  gate <- aa_login_gate(con, "innocent")

  expect_false(gate$allowed)
  expect_identical(gate$reason, "throttled")
  expect_identical(gate$message, aa_text(aa_settings(), "throttled"))

  for (i in 1:5) {
    aa_record_attempt(con, "alsey", FALSE)
  }
  expect_identical(aa_login_gate(con, "alsey")$reason, "throttled")
})

test_that("the gate does not lock login if the attempts table is missing (fail-open) and logs the reason", {
  con <- users_db()
  texec(con, "DROP TABLE login_attempts")

  expect_message(
    gate <- aa_login_gate(con, "alsey"),
    "login lockout check is unavailable"
  )

  expect_true(gate$allowed)
})

test_that("the gate rejects a non-SQLite connection", {
  expect_error(aa_login_gate(list(), "a"), class = "appauth_error_connection")
})

# ---- users with statuses ----------------------------------------------------

test_that("users overview: states, statuses and lockout seconds", {
  con <- users_db()
  raw_user(con, "boss", "admin")
  raw_user(con, "worker", "user", blocked = 1)
  raw_user(con, "viewer1", "viewer")
  raw_user(con, "both", "user", blocked = 1)
  for (i in 1:5) {
    aa_record_attempt(con, "viewer1", FALSE)
  }
  for (i in 1:5) {
    aa_record_attempt(con, "both", FALSE)
  }

  ov <- aa_users_overview(con)

  expect_identical(
    names(ov),
    c(
      "login",
      "role",
      "blocked",
      "state",
      "lock_seconds",
      "status",
      "created_at",
      "last_login_at",
      "created",
      "last_login",
      "has_email",
      "totp_on",
      "autologins"
    )
  )
  expect_identical(ov$login, c("boss", "worker", "viewer1", "both"))
  expect_identical(ov$state, c("ok", "blocked", "locked", "blocked"))
  expect_identical(ov$status[1], "")
  expect_identical(ov$status[2], aa_text(aa_settings(), "status_blocked"))
  expect_identical(ov$status[3], aa_text(aa_settings(), "status_locked", 15L))
  # a block by an administrator takes priority, but the attempt lockout seconds are visible too
  expect_identical(ov$status[4], aa_text(aa_settings(), "status_blocked"))
  expect_gt(ov$lock_seconds[3], 14 * 60)
  expect_identical(ov$lock_seconds[1], 0L)
})

test_that("users overview in another language and with an empty table", {
  con <- users_db()

  empty <- aa_users_overview(con)
  expect_identical(nrow(empty), 0L)
  expect_identical(
    names(empty),
    c(
      "login",
      "role",
      "blocked",
      "state",
      "lock_seconds",
      "status",
      "created_at",
      "last_login_at",
      "created",
      "last_login",
      "has_email",
      "totp_on",
      "autologins"
    )
  )

  raw_user(con, "worker", "user", blocked = 1)
  ru <- aa_settings(texts = aa_texts("ru"))
  ov_ru <- aa_users_overview(con, ru)
  expect_identical(ov_ru$status, aa_text(ru, "status_blocked"))
  expect_false(identical(
    ov_ru$status,
    aa_text(aa_settings(), "status_blocked")
  ))
})

test_that("users overview does not fail if the attempts table is missing", {
  con <- users_db()
  raw_user(con, "boss", "admin")
  raw_user(con, "worker", "user", blocked = 1)
  texec(con, "DROP TABLE login_attempts")

  ov <- aa_users_overview(con)

  expect_identical(ov$state, c("ok", "blocked"))
  expect_identical(ov$lock_seconds, c(0L, 0L))
})

test_that("users overview does not reveal passwords and rejects a non-SQLite connection", {
  con <- users_db()
  raw_user(con, "boss", "admin", password = "secret-hash")

  expect_false("password" %in% names(aa_users_overview(con)))
  expect_error(aa_users_overview(list()), class = "appauth_error_connection")
})

test_that("aa_users_overview: email, 2FA and autologins per user", {
  con <- users_db()
  settings <- aa_settings(
    totp_enabled = TRUE,
    totp_key = "a-long-random-key-for-the-tests"
  )
  raw_user(con, "ivan")
  raw_user(con, "olga")
  raw_user(con, "boss")

  aa_set_email(con, "ivan", "ivan@example.com", settings)
  setup <- aa_totp_setup(con, "olga", settings)
  aa_totp_enable(con, "olga", aa_totp_code(setup$secret), settings)
  aa_issue_token(con, "ivan")
  aa_issue_token(con, "ivan")
  aa_issue_token(con, "boss")

  data <- aa_users_overview(con, settings)
  row <- function(login) data[data$login == login, ]

  expect_identical(row("ivan")$has_email, 1L)
  expect_identical(row("olga")$has_email, 0L)
  expect_identical(row("ivan")$totp_on, 0L)
  expect_identical(row("olga")$totp_on, 1L)
  expect_identical(row("ivan")$autologins, 2L)
  expect_identical(row("boss")$autologins, 1L)
  expect_identical(row("olga")$autologins, 0L)

  # the address and the secret are not in the summary
  expect_false(any(c("email", "totp_secret") %in% names(data)))
  expect_false(any(grepl("ivan@example.com", unlist(data), fixed = TRUE)))
})

test_that("aa_users_overview: an empty table and an old schema without email and 2FA", {
  skip_if_not_sqlite()
  con <- users_db()
  empty <- aa_users_overview(con)
  expect_identical(nrow(empty), 0L)
  expect_true(all(c("has_email", "totp_on", "autologins") %in% names(empty)))

  # old schema: no email and totp_enabled columns, the overview does not fail, the flags are zero
  old <- new_db()
  DBI::dbExecute(
    old,
    "CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, login TEXT, password TEXT, role TEXT, blocked INTEGER DEFAULT 0, created_at TEXT, last_login_at TEXT)"
  )
  DBI::dbExecute(
    old,
    "INSERT INTO users (login, password, role) VALUES ('ivan', 'x', 'user')"
  )
  data <- aa_users_overview(old)
  expect_identical(data$has_email, 0L)
  expect_identical(data$totp_on, 0L)
  expect_identical(data$autologins, 0L)
})
