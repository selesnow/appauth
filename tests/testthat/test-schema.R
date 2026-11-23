test_that("on an empty database all tables are created and all migrations applied", {
  con <- new_db()

  expect_identical(aa_schema_version(con), 0L)

  res <- aa_init_db(con)

  expect_identical(res$applied, 1:10)
  expect_identical(res$version, 10L)
  expect_false(res$legacy)
  expect_identical(
    table_names(con),
    c(
      "appauth_migrations",
      "auth_sessions",
      "login_attempts",
      "oauth_states",
      "password_resets",
      "registrations",
      "totp_recovery",
      "users"
    )
  )
  expect_identical(aa_schema_version(con), 10L)
})

test_that("table columns match the schema of earlier versions", {
  con <- new_db()
  aa_init_db(con)

  expect_identical(
    columns_of(con, "users"),
    c(
      "id",
      "login",
      "password",
      "role",
      "blocked",
      "must_change",
      "created_at",
      "last_login_at",
      "email",
      "totp_secret",
      "totp_enabled",
      "totp_last_step"
    )
  )
  expect_identical(
    columns_of(con, "auth_sessions"),
    c("id", "user_login", "token_hash", "created_at", "expires_at", "revoked")
  )
  expect_identical(
    columns_of(con, "login_attempts"),
    c("id", "login", "success", "attempted_at")
  )
  expect_identical(
    columns_of(con, "registrations"),
    c(
      "id", "login", "email", "password", "role", "token_hash",
      "created_at", "expires_at", "used"
    )
  )
})

test_that("a new user has blocked 0 by default, login is unique", {
  con <- new_db()
  aa_init_db(con)

  texec(
    con,
    "INSERT INTO users (login, password, role) VALUES ('a', 'x', 'user')"
  )

  expect_identical(tquery(con, "SELECT blocked FROM users")$blocked, 0L)
  expect_error(
    texec(
      con,
      "INSERT INTO users (login, password, role) VALUES ('a', 'y', 'user')"
    )
  )
})

test_that("migrations are recorded in the service table", {
  con <- new_db()
  aa_init_db(con)

  migrations <- tquery(
    con,
    "SELECT version, name FROM appauth_migrations ORDER BY version"
  )

  expect_identical(migrations$version, 1:10)
  expect_identical(
    migrations$name,
    c(
      "users",
      "users_blocked_column",
      "auth_sessions",
      "login_attempts",
      "users_must_change_column",
      "users_created_and_last_login_columns",
      "password_resets_and_email",
      "totp_two_factor",
      "oauth_states",
      "registrations"
    )
  )
})

test_that("a repeated run changes nothing", {
  con <- new_db()
  aa_init_db(con)

  texec(
    con,
    "INSERT INTO users (login, password, role) VALUES ('a', 'x', 'admin')"
  )
  before <- lapply(
    c("users", "auth_sessions", "login_attempts", "appauth_migrations"),
    \(t) rows_of(con, t)
  )

  res <- aa_init_db(con)

  after <- lapply(
    c("users", "auth_sessions", "login_attempts", "appauth_migrations"),
    \(t) rows_of(con, t)
  )

  expect_identical(res$applied, integer())
  expect_identical(res$version, 10L)
  expect_identical(before, after)
})

test_that("production schema from before login protection: completed, data unchanged", {
  skip_if_not_sqlite()
  con <- new_db()
  fixture_legacy_full(con)

  users_before <- rows_of(con, "users")
  sessions_before <- rows_of(con, "auth_sessions")

  res <- aa_init_db(con)

  expect_true(res$legacy)
  expect_identical(res$applied, 1:10)
  expect_true("blocked" %in% columns_of(con, "users"))
  expect_true("login_attempts" %in% table_names(con))

  users_after <- rows_of(con, "users")
  expect_identical(users_after[, names(users_before)], users_before)
  expect_true(all(users_after$blocked == 0))
  expect_identical(rows_of(con, "auth_sessions"), sessions_before)
})

test_that("an old dev schema without an id column is completed too", {
  skip_if_not_sqlite()
  con <- new_db()
  fixture_legacy_old(con)

  users_before <- rows_of(con, "users")

  res <- aa_init_db(con)

  expect_true(res$legacy)
  expect_false("id" %in% columns_of(con, "users"))
  expect_true("blocked" %in% columns_of(con, "users"))

  users_after <- rows_of(con, "users")
  expect_identical(users_after[, names(users_before)], users_before)
  expect_true(all(users_after$blocked == 0))
})

test_that("home-grown schema: plain-text passwords and root/root stay as is, application tables are untouched", {
  skip_if_not_sqlite()
  con <- new_db()
  fixture_legacy_plain(con)

  users_before <- rows_of(con, "users")
  log_before <- rows_of(con, "action_log")

  res <- aa_init_db(con)

  expect_true(res$legacy)
  expect_identical(
    table_names(con),
    c(
      "action_log",
      "appauth_migrations",
      "auth_sessions",
      "login_attempts",
      "oauth_states",
      "password_resets",
      "registrations",
      "totp_recovery",
      "users"
    )
  )

  users_after <- rows_of(con, "users")
  expect_identical(users_after[, names(users_before)], users_before)
  expect_true("root" %in% users_after$login)
  expect_identical(rows_of(con, "action_log"), log_before)
})

test_that("a repeated run on old schemas changes nothing either", {
  skip_if_not_sqlite()
  for (fixture in list(
    fixture_legacy_full,
    fixture_legacy_old,
    fixture_legacy_plain
  )) {
    con <- new_db()
    fixture(con)
    aa_init_db(con)

    tables <- setdiff(table_names(con), "appauth_migrations")
    before <- lapply(tables, \(t) rows_of(con, t))

    res <- aa_init_db(con)

    expect_identical(res$applied, integer())
    expect_false(res$legacy)
    expect_identical(lapply(tables, \(t) rows_of(con, t)), before)
  }
})

test_that("on a migration error the changes are rolled back in one transaction", {
  con <- new_db()
  # in MySQL every DDL command ends the transaction implicitly, table creation cannot be rolled back
  # (migrations are idempotent, so a repeated run will complete the schema)
  testthat::skip_if(
    aa_dialect(con) == "mysql",
    "DDL in MySQL is not rolled back"
  )

  testthat::local_mocked_bindings(
    aa_migrations = function() {
      list(
        list(version = 1L, name = "ok", up = function(conn) {
          DBI::dbExecute(conn, "CREATE TABLE users (login TEXT)")
        }),
        list(version = 2L, name = "boom", up = function(conn) {
          stop("migration failure")
        })
      )
    }
  )

  expect_error(aa_init_db(con), "migration failure")
  expect_identical(table_names(con), character())
})

test_that("aa_init_db and aa_schema_version reject unsupported databases and closed connections", {
  expect_error(aa_init_db(list()), class = "appauth_error_connection")
  expect_error(
    aa_schema_version("not a connection"),
    class = "appauth_error_connection"
  )

  con <- new_db()
  DBI::dbDisconnect(con)

  expect_error(aa_init_db(con), class = "appauth_error_connection")
})

test_that("aa_cleanup deletes only stale attempts and tokens", {
  con <- new_db()
  aa_init_db(con)

  texec(
    con,
    "
    INSERT INTO login_attempts (login, success, attempted_at) VALUES
      ('old',  0, datetime('now', '-25 hours')),
      ('new',  0, datetime('now', '-1 hours'))"
  )
  texec(
    con,
    "
    INSERT INTO auth_sessions (user_login, token_hash, created_at, expires_at, revoked) VALUES
      ('u', 'expired_long',  datetime('now', '-90 days'), datetime('now', '-60 days'), 0),
      ('u', 'revoked_long',  datetime('now', '-50 days'), datetime('now', '+10 days'), 1),
      ('u', 'revoked_new',   datetime('now', '-2 days'),  datetime('now', '+28 days'), 1),
      ('u', 'expired_new',   datetime('now', '-35 days'), datetime('now', '-5 days'),  0),
      ('u', 'active',        datetime('now', '-1 days'),  datetime('now', '+29 days'), 0)"
  )
  add_registration <- function(token, created, expires, used) {
    aa_execute(
      con,
      "INSERT INTO registrations
        (login, email, password, role, token_hash, created_at, expires_at, used)
       VALUES (?, ?, 'hash', 'viewer', ?, ?, ?, ?)",
      params = list(paste0("u_", token), paste0(token, "@example.com"), token, created, expires, used)
    )
  }
  add_registration("old_used", aa_utc(-90 * 86400), aa_utc(86400), 1)
  add_registration("old_expired", aa_utc(-50 * 86400), aa_utc(-2 * 86400), 0)
  add_registration("fresh_used", aa_utc(-12 * 3600), aa_utc(86400), 1)
  add_registration("active", aa_utc(-3600), aa_utc(86400), 0)

  res <- aa_cleanup(con, aa_settings())

  expect_identical(res$login_attempts, 1L)
  expect_identical(res$auth_sessions, 2L)
  expect_identical(res$registrations, 2L)
  expect_identical(tquery(con, "SELECT login FROM login_attempts")$login, "new")
  expect_setequal(
    tquery(con, "SELECT token_hash FROM auth_sessions")$token_hash,
    c("revoked_new", "expired_new", "active")
  )
  expect_setequal(
    tquery(con, "SELECT token_hash FROM registrations")$token_hash,
    c("fresh_used", "active")
  )
})

test_that("aa_cleanup honors retention periods from the settings", {
  con <- new_db()
  aa_init_db(con)

  texec(
    con,
    "
    INSERT INTO login_attempts (login, success, attempted_at) VALUES
      ('a', 0, datetime('now', '-3 hours')),
      ('b', 0, datetime('now', '-30 minutes'))"
  )

  res <- aa_cleanup(con, aa_settings(attempts_retention_hours = 2))

  expect_identical(res$login_attempts, 1L)
  expect_identical(tquery(con, "SELECT login FROM login_attempts")$login, "b")
})

test_that("aa_prepare_db prepares the database and does not throw errors", {
  con <- new_db()

  expect_true(suppressMessages(aa_prepare_db(con, aa_settings())))
  expect_identical(aa_schema_version(con), 10L)

  expect_message(
    aa_prepare_db(new_db(), aa_settings()),
    "schema migrations applied"
  )
})

test_that("aa_prepare_db on error returns FALSE and writes a warning to the log", {
  con <- new_db()
  DBI::dbDisconnect(con)

  expect_message(res <- aa_prepare_db(con, aa_settings()), "WARNING")
  expect_false(res)

  expect_message(res2 <- aa_prepare_db(list(), aa_settings()), "WARNING")
  expect_false(res2)
})
