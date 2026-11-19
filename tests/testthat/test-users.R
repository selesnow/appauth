# ---- reading ---------------------------------------------------------------------

test_that("aa_get_user and aa_list_users do not return the password, the login is compared exactly", {
  con <- users_db()
  raw_user(con, "alsey", "admin")
  raw_user(con, "Ida", "viewer", blocked = 1)

  expect_identical(names(aa_get_user(con, "alsey")), c("login", "role", "blocked", "created_at", "last_login_at"))
  expect_identical(aa_get_user(con, "alsey")$role, "admin")
  expect_identical(aa_get_user(con, "Ida")$blocked, 1L)
  expect_null(aa_get_user(con, "ida"))
  expect_null(aa_get_user(con, "Alsey"))
  expect_null(aa_get_user(con, " alsey"))

  for (bad in list(NULL, NA_character_, "", 5, c("alsey", "Ida"))) {
    expect_null(aa_get_user(con, bad))
  }

  users <- aa_list_users(con)
  expect_identical(names(users), c("login", "role", "blocked", "created_at", "last_login_at"))
  expect_identical(users$login, c("alsey", "Ida"))
})

test_that("aa_users_exist", {
  con <- users_db()

  expect_false(aa_users_exist(con))
  raw_user(con, "a")
  expect_true(aa_users_exist(con))
})

test_that("user functions reject a non-supported connection", {
  expect_error(aa_get_user(list(), "a"), class = "appauth_error_connection")
  expect_error(aa_list_users(list()), class = "appauth_error_connection")
  expect_error(aa_create_user(list(), "a", "password1", "user"), class = "appauth_error_connection")
  expect_error(aa_authenticate(list(), "a", "b"), class = "appauth_error_connection")
})

# ---- creation ---------------------------------------------------------------------

test_that("aa_create_user creates a user with a password hash and not blocked", {
  con <- users_db()

  res <- withVisible(aa_create_user(con, "worker", "worker-password", "user"))

  expect_false(res$visible)
  expect_true(res$value)

  user <- aa_get_user(con, "worker")
  expect_identical(user$role, "user")
  expect_identical(user$blocked, 0L)
  expect_true(aa_is_password_hash(stored_password(con, "worker")))
  expect_true(aa_verify_password("worker-password", stored_password(con, "worker")))
})

test_that("aa_create_user rejects invalid data with a reason and a text, creating nothing", {
  con <- users_db()

  cases <- list(
    list(args = list("", "worker-password", "user"),       reason = "login_empty"),
    list(args = list(" worker", "worker-password", "user"), reason = "login_whitespace"),
    list(args = list(strrep("a", 65), "worker-password", "user"), reason = "login_too_long"),
    list(args = list("worker", "short", "user"),           reason = "password_too_short"),
    list(args = list("worker", "", "user"),                reason = "password_empty"),
    list(args = list("worker", "worker-password", "boss"), reason = "invalid_role"),
    list(args = list("worker", "worker-password", NULL),   reason = "invalid_role"),
    list(args = list("worker", "worker-password", NA_character_), reason = "invalid_role")
  )

  for (case in cases) {
    err <- expect_error(do.call(aa_create_user, c(list(con), case$args)), class = "appauth_error_user", info = case$reason)
    expect_identical(err$reason, case$reason, info = case$reason)
  }

  expect_identical(count_users(con), 0L)

  err <- expect_error(aa_create_user(con, "worker", "short", "user"), class = "appauth_error_user")
  expect_identical(conditionMessage(err), "Password must be at least 6 characters long")
})

test_that("creation error texts in Russian", {
  con <- users_db()
  s <- aa_settings(texts = aa_texts("ru"))

  err <- expect_error(aa_create_user(con, "worker", "x", "user", s), class = "appauth_error_user")
  expect_identical(conditionMessage(err), aa_text(s, "password_too_short", 6))

  err <- expect_error(aa_create_user(con, "worker", "worker-password", "boss", s), class = "appauth_error_user")
  expect_identical(conditionMessage(err), aa_text(s, "invalid_role"))
})

test_that("the role is checked against the list from the settings", {
  con <- users_db()
  s <- aa_settings(roles = c("boss", "editor"), admin_role = "boss")

  expect_error(aa_create_user(con, "a", "password1", "user", s), class = "appauth_error_user")
  expect_no_error(aa_create_user(con, "a", "password1", "editor", s))
  expect_identical(aa_get_user(con, "a")$role, "editor")
})

test_that("a taken login is rejected: an exact match and a difference only in case (including Cyrillic)", {
  con <- users_db()
  aa_create_user(con, "Worker", "worker-password", "user")
  aa_create_user(con, "\u0418\u0432\u0430\u043d", "ivan-password", "user")

  expect_identical(
    expect_error(aa_create_user(con, "Worker", "other-password", "user"), class = "appauth_error_user")$reason,
    "user_exists"
  )

  for (login in c("worker", "WORKER", "wOrKeR", "\u0438\u0432\u0430\u043d", "\u0418\u0412\u0410\u041d")) {
    err <- expect_error(aa_create_user(con, login, "other-password", "user"), class = "appauth_error_user", info = login)
    expect_identical(err$reason, "user_exists_case", info = login)
  }

  expect_identical(count_users(con), 2L)

  expect_identical(
    conditionMessage(expect_error(aa_create_user(con, "worker", "other-password", "user"), class = "appauth_error_user")),
    "A user with this login already exists (logins differ only in letter case)"
  )
})

test_that("existing login pairs that differ in case are kept and work as different users", {
  con <- users_db()

  texec(con, "INSERT INTO users (login, password, role) VALUES (?, ?, 'user')",
                 params = list("kiruka", aa_hash_password("password-one")))
  texec(con, "INSERT INTO users (login, password, role) VALUES (?, ?, 'user')",
                 params = list("Kiruka", aa_hash_password("password-two")))

  expect_identical(aa_list_users(con)$login, c("kiruka", "Kiruka"))
  expect_identical(aa_authenticate(con, "kiruka", "password-one")$login, "kiruka")
  expect_identical(aa_authenticate(con, "Kiruka", "password-two")$login, "Kiruka")
  expect_null(aa_authenticate(con, "kiruka", "password-two"))
  expect_null(aa_authenticate(con, "KIRUKA", "password-one"))

  # a third spelling cannot be created
  expect_error(aa_create_user(con, "KIRUKA", "password-three", "user"), class = "appauth_error_user")
})

test_that("aa_validate_new_user returns the problem text and creates nothing", {
  con <- users_db()
  aa_create_user(con, "worker", "worker-password", "user")

  expect_null(aa_validate_new_user(con, "other", "other-password", "user"))
  expect_identical(aa_validate_new_user(con, "Worker", "other-password", "user"),
                   "A user with this login already exists (logins differ only in letter case)")
  expect_identical(aa_validate_new_user(con, "other", "x", "user"), "Password must be at least 6 characters long")
  expect_identical(aa_validate_new_user(con, "other", "other-password", "boss"), "Invalid role")
  expect_identical(count_users(con), 1L)
})

# ---- first administrator --------------------------------------------------------

test_that("the first administrator is created with the administrator role only on an empty table", {
  con <- users_db()

  expect_true(aa_create_first_admin(con, "boss", "boss-password"))

  boss <- aa_get_user(con, "boss")
  expect_identical(boss$role, "admin")
  expect_identical(boss$blocked, 0L)
  expect_true(aa_verify_password("boss-password", stored_password(con, "boss")))

  expect_false(aa_create_first_admin(con, "second", "second-password"))
  expect_identical(count_users(con), 1L)
  expect_null(aa_get_user(con, "second"))
})

test_that("the first administrator is not created if users already exist (including ones created otherwise)", {
  con <- users_db()
  raw_user(con, "existing")

  expect_false(aa_create_first_admin(con, "boss", "boss-password"))
  expect_identical(count_users(con), 1L)
})

test_that("for the first administrator the role comes from the settings, data is validated", {
  con <- users_db()
  s <- aa_settings(roles = c("owner", "user"), admin_role = "owner")

  expect_error(aa_create_first_admin(con, "", "boss-password", s), class = "appauth_error_user")
  expect_error(aa_create_first_admin(con, " boss", "boss-password", s), class = "appauth_error_user")
  expect_error(aa_create_first_admin(con, "boss", "short", s), class = "appauth_error_user")
  expect_identical(count_users(con), 0L)

  expect_true(aa_create_first_admin(con, "boss", "boss-password", s))
  expect_identical(aa_get_user(con, "boss")$role, "owner")
})

# ---- sign-in ---------------------------------------------------------------------

test_that("aa_authenticate: the correct password gives login, role and blocked without the password", {
  con <- users_db()
  aa_create_user(con, "worker", "worker-password", "user")

  res <- aa_authenticate(con, "worker", "worker-password")

  expect_identical(names(res), c("login", "role", "blocked", "must_change"))
  expect_identical(res$login, "worker")
  expect_identical(res$role, "user")
  expect_identical(res$blocked, 0L)
  expect_identical(nrow(res), 1L)
})

test_that("aa_authenticate: wrong data gives NULL, the login is compared exactly", {
  con <- users_db()
  aa_create_user(con, "worker", "worker-password", "user")

  expect_null(aa_authenticate(con, "worker", "wrong"))
  expect_null(aa_authenticate(con, "nobody", "worker-password"))
  expect_null(aa_authenticate(con, "Worker", "worker-password"))
  expect_null(aa_authenticate(con, " worker", "worker-password"))

  for (bad in list(NULL, NA_character_, "", 5, c("a", "b"))) {
    expect_null(aa_authenticate(con, bad, "worker-password"))
    expect_null(aa_authenticate(con, "worker", bad))
  }
})

test_that("aa_authenticate: SQL injections do not work", {
  con <- users_db()
  aa_create_user(con, "worker", "worker-password", "user")

  for (login in c("worker' --", "' OR '1'='1", "worker'; DROP TABLE users;--", "\" OR \"\"=\"")) {
    expect_null(aa_authenticate(con, login, "x"), info = login)
    expect_null(aa_authenticate(con, login, "' OR '1'='1"), info = login)
  }

  expect_null(aa_authenticate(con, "worker", "' OR '1'='1"))
  expect_identical(count_users(con), 1L)
  expect_true("users" %in% DBI::dbListTables(con))
})

test_that("aa_authenticate: a blocked user with the correct password is returned with blocked = 1, with a wrong one NULL", {
  con <- users_db()
  aa_create_user(con, "worker", "worker-password", "user")
  texec(con, "UPDATE users SET blocked = 1 WHERE login = 'worker'")

  res <- aa_authenticate(con, "worker", "worker-password")

  expect_identical(res$blocked, 1L)
  expect_null(aa_authenticate(con, "worker", "wrong"))
})

test_that("aa_authenticate: a plain-text password in the database is never accepted", {
  con <- users_db()
  raw_user(con, "legacy", password = "secret12")

  expect_null(aa_authenticate(con, "legacy", "secret12"))

  # and a hash is not accepted as a password either
  aa_create_user(con, "worker", "worker-password", "user")
  expect_null(aa_authenticate(con, "worker", stored_password(con, "worker")))
})

test_that("aa_authenticate: the check is performed for a nonexistent login too (against a dummy hash)", {
  con <- users_db()
  aa_create_user(con, "worker", "worker-password", "user")

  dummy <- aa_dummy_hash()
  worker_hash <- stored_password(con, "worker")
  calls <- character()

  testthat::local_mocked_bindings(
    aa_verify_password = function(password, stored) {
      calls <<- c(calls, stored)
      FALSE
    }
  )

  aa_authenticate(con, "nobody", "any-password")
  expect_identical(calls, dummy)

  calls <- character()
  aa_authenticate(con, "worker", "wrong")
  expect_identical(calls, worker_hash)
})

test_that("aa_authenticate also works without the blocked column (old schema)", {
  testthat::skip_if_not_installed("RSQLite")
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(con))

  texec(con, "CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, login TEXT UNIQUE NOT NULL, password TEXT NOT NULL, role TEXT NOT NULL)")
  texec(con, "INSERT INTO users (login, password, role) VALUES (?, ?, 'user')",
                 params = list("old", aa_hash_password("old-password")))

  res <- aa_authenticate(con, "old", "old-password")

  expect_identical(res$login, "old")
  expect_identical(res$blocked, 0L)
  expect_null(aa_authenticate(con, "old", "wrong"))
})

# ---- password change -----------------------------------------------------------

test_that("aa_set_password changes the password and revokes tokens of this user only", {
  con <- users_db()
  aa_create_user(con, "worker", "old-password", "user")
  aa_create_user(con, "other", "other-password", "user")
  raw_token(con, "worker", "t1"); raw_token(con, "worker", "t2"); raw_token(con, "other", "t3")

  expect_identical(aa_set_password(con, "worker", "new-password"), 1L)

  expect_null(aa_authenticate(con, "worker", "old-password"))
  expect_identical(aa_authenticate(con, "worker", "new-password")$login, "worker")
  expect_identical(revoked_of(con, "t1"), 1L)
  expect_identical(revoked_of(con, "t2"), 1L)
  expect_identical(revoked_of(con, "t3"), 0L)
  expect_identical(aa_authenticate(con, "other", "other-password")$login, "other")
})

test_that("aa_set_password: a weak password is rejected, nothing changes", {
  con <- users_db()
  aa_create_user(con, "worker", "old-password", "user")
  raw_token(con, "worker", "t1")
  before <- stored_password(con, "worker")

  err <- expect_error(aa_set_password(con, "worker", "short"), class = "appauth_error_user")

  expect_identical(err$reason, "password_too_short")
  expect_identical(stored_password(con, "worker"), before)
  expect_identical(revoked_of(con, "t1"), 0L)
})

test_that("aa_set_password for a nonexistent login returns 0 and does nothing", {
  con <- users_db()
  raw_token(con, "ghost", "t1")

  expect_identical(aa_set_password(con, "ghost", "new-password"), 0L)
  expect_identical(aa_set_password(con, NA_character_, "new-password"), 0L)
  expect_identical(revoked_of(con, "t1"), 0L)
})

# ---- role change -----------------------------------------------------------------

test_that("aa_set_role changes the role to a valid one", {
  con <- users_db()
  raw_user(con, "boss", "admin"); raw_user(con, "worker", "user")

  expect_identical(aa_set_role(con, "worker", "viewer"), 1L)
  expect_identical(aa_get_user(con, "worker")$role, "viewer")
  expect_null(aa_check_can_change_role(con, "worker", "admin"))
})

test_that("aa_set_role: an invalid role, an unknown and an empty user are rejected", {
  con <- users_db()
  raw_user(con, "worker", "user")

  expect_identical(expect_error(aa_set_role(con, "worker", "boss"), class = "appauth_error_user")$reason, "invalid_role")
  expect_identical(expect_error(aa_set_role(con, "ghost", "viewer"), class = "appauth_error_user")$reason, "user_not_found")
  expect_identical(expect_error(aa_set_role(con, NA_character_, "viewer"), class = "appauth_error_user")$reason, "user_not_specified")
  expect_identical(aa_get_user(con, "worker")$role, "user")
})

test_that("the administrator role cannot be removed from the last active administrator", {
  con <- users_db()
  raw_user(con, "boss", "admin")
  raw_user(con, "second", "admin", blocked = 1)
  raw_user(con, "worker", "user")

  err <- expect_error(aa_set_role(con, "boss", "user"), class = "appauth_error_user")

  expect_identical(err$reason, "cannot_change_last_admin_role")
  expect_identical(conditionMessage(err), "You cannot remove the administrator role from the last active administrator")
  expect_identical(aa_get_user(con, "boss")$role, "admin")

  # if there is another active administrator, the role can be removed
  raw_user(con, "third", "admin")
  expect_identical(aa_set_role(con, "boss", "user"), 1L)
  expect_identical(aa_get_user(con, "boss")$role, "user")

  # and the one who remained the only one cannot be changed again
  expect_error(aa_set_role(con, "third", "viewer"), class = "appauth_error_user")
})

test_that("changing an administrator to administrator and an ordinary user to any role is allowed", {
  con <- users_db()
  raw_user(con, "boss", "admin")

  expect_identical(aa_set_role(con, "boss", "admin"), 1L)
  expect_null(aa_check_can_change_role(con, "boss", "admin"))
  expect_identical(
    aa_check_can_change_role(con, "boss", "user"),
    "You cannot remove the administrator role from the last active administrator"
  )
})

# ---- blocking -----------------------------------------------------------------

test_that("aa_set_blocked blocks, revokes tokens and unblocks", {
  con <- users_db()
  raw_user(con, "boss", "admin"); raw_user(con, "worker", "user"); raw_user(con, "other", "user")
  raw_token(con, "worker", "t1"); raw_token(con, "other", "t2")

  expect_identical(aa_set_blocked(con, "worker", TRUE, acting_login = "boss"), 1L)

  expect_identical(aa_get_user(con, "worker")$blocked, 1L)
  expect_identical(revoked_of(con, "t1"), 1L)
  expect_identical(revoked_of(con, "t2"), 0L)

  expect_identical(aa_set_blocked(con, "worker", FALSE), 1L)
  expect_identical(aa_get_user(con, "worker")$blocked, 0L)
  # tokens revoked on blocking are not restored
  expect_identical(revoked_of(con, "t1"), 1L)
})

test_that("one cannot block oneself and the last active administrator", {
  con <- users_db()
  raw_user(con, "boss", "admin"); raw_user(con, "second", "admin"); raw_user(con, "worker", "user")

  expect_identical(
    expect_error(aa_set_blocked(con, "boss", TRUE, acting_login = "boss"), class = "appauth_error_user")$reason,
    "cannot_block_self"
  )

  expect_identical(aa_set_blocked(con, "second", TRUE, acting_login = "boss"), 1L)

  err <- expect_error(aa_set_blocked(con, "boss", TRUE, acting_login = "worker"), class = "appauth_error_user")
  expect_identical(err$reason, "cannot_block_last_admin")
  expect_identical(aa_get_user(con, "boss")$blocked, 0L)

  # without acting_login (a call from a script) the last administrator rule still applies
  expect_error(aa_set_blocked(con, "boss", TRUE), class = "appauth_error_user")
})

test_that("aa_set_blocked: an unknown user is an error on blocking, 0 on unblocking", {
  con <- users_db()
  raw_user(con, "boss", "admin")

  expect_identical(
    expect_error(aa_set_blocked(con, "ghost", TRUE), class = "appauth_error_user")$reason,
    "user_not_found"
  )
  expect_identical(aa_set_blocked(con, "ghost", FALSE), 0L)
  expect_error(aa_set_blocked(con, "boss", NA), class = "appauth_error_settings")
})

test_that("aa_check_can_block and aa_check_can_delete return clear texts", {
  con <- users_db()
  raw_user(con, "boss", "admin"); raw_user(con, "worker", "user")

  expect_null(aa_check_can_block(con, "worker", "boss"))
  expect_null(aa_check_can_delete(con, "worker", "boss"))
  expect_identical(aa_check_can_block(con, "boss", "boss"), "You cannot block yourself")
  expect_identical(aa_check_can_delete(con, "boss", "boss"), "You cannot delete yourself")
  expect_identical(aa_check_can_block(con, "boss", "worker"), "You cannot block the last active administrator")
  expect_identical(aa_check_can_delete(con, "boss", "worker"), "You cannot delete the last active administrator")
  expect_identical(aa_check_can_block(con, "ghost", "boss"), "User not found")
  expect_identical(aa_check_can_delete(con, "", "boss"), "User is not specified")
  expect_identical(aa_check_can_delete(con, NULL, "boss"), "User is not specified")

  ru <- aa_settings(texts = aa_texts("ru"))
  expect_identical(aa_check_can_block(con, "boss", "boss", ru), aa_text(ru, "cannot_block_self"))
  expect_identical(aa_check_can_delete(con, "boss", "worker", ru), aa_text(ru, "cannot_delete_last_admin"))
})

test_that("a blocked administrator is not considered active", {
  con <- users_db()
  raw_user(con, "boss", "admin")
  raw_user(con, "blocked_admin", "admin", blocked = 1)

  expect_identical(aa_check_can_block(con, "boss", "x"), "You cannot block the last active administrator")
  # a blocked administrator can be deleted while an active one exists
  expect_null(aa_check_can_delete(con, "blocked_admin", "boss"))
})

# ---- deletion -------------------------------------------------------------------

test_that("aa_delete_user deletes the user, their tokens and failed login attempts", {
  con <- users_db()
  raw_user(con, "boss", "admin"); raw_user(con, "worker", "user"); raw_user(con, "other", "user")
  raw_token(con, "worker", "t1"); raw_token(con, "worker", "t2", revoked = 1); raw_token(con, "other", "t3")
  texec(con, "INSERT INTO login_attempts (login, success) VALUES ('worker', 0), ('worker', 0), ('other', 0)")

  expect_identical(aa_delete_user(con, "worker", acting_login = "boss"), 1L)

  expect_null(aa_get_user(con, "worker"))
  expect_identical(tquery(con, "SELECT COUNT(*) AS n FROM auth_sessions WHERE user_login = 'worker'")$n, 0L)
  expect_identical(tquery(con, "SELECT COUNT(*) AS n FROM login_attempts WHERE login = 'worker'")$n, 0L)
  # data of other users is not affected
  expect_identical(tquery(con, "SELECT COUNT(*) AS n FROM auth_sessions WHERE user_login = 'other'")$n, 1L)
  expect_identical(tquery(con, "SELECT COUNT(*) AS n FROM login_attempts WHERE login = 'other'")$n, 1L)
  expect_identical(count_users(con), 2L)
})

test_that("one cannot delete oneself and the last active administrator", {
  con <- users_db()
  raw_user(con, "boss", "admin"); raw_user(con, "worker", "user")

  expect_identical(
    expect_error(aa_delete_user(con, "boss", acting_login = "boss"), class = "appauth_error_user")$reason,
    "cannot_delete_self"
  )
  expect_identical(
    expect_error(aa_delete_user(con, "boss", acting_login = "worker"), class = "appauth_error_user")$reason,
    "cannot_delete_last_admin"
  )
  expect_error(aa_delete_user(con, "boss"), class = "appauth_error_user")
  expect_identical(count_users(con), 2L)
})

test_that("deleting an administrator is allowed if another active one remains", {
  con <- users_db()
  raw_user(con, "boss", "admin"); raw_user(con, "second", "admin")

  expect_identical(aa_delete_user(con, "second", acting_login = "boss"), 1L)
  expect_identical(aa_list_users(con)$login, "boss")
})

test_that("aa_delete_user: an unknown and an empty user are rejected", {
  con <- users_db()
  raw_user(con, "boss", "admin")

  expect_identical(expect_error(aa_delete_user(con, "ghost"), class = "appauth_error_user")$reason, "user_not_found")
  expect_identical(expect_error(aa_delete_user(con, NA_character_), class = "appauth_error_user")$reason, "user_not_specified")
})

test_that("deletion works even if the login attempts table is missing", {
  con <- users_db()
  raw_user(con, "boss", "admin"); raw_user(con, "worker", "user")
  texec(con, "DROP TABLE login_attempts")

  expect_identical(aa_delete_user(con, "worker", acting_login = "boss"), 1L)
  expect_null(aa_get_user(con, "worker"))
})
