test_that("на пустой базе создаются все таблицы и применяются все миграции", {
  con <- new_db()

  expect_identical(aa_schema_version(con), 0L)

  res <- aa_init_db(con)

  expect_identical(res$applied, 1:5)
  expect_identical(res$version, 5L)
  expect_false(res$legacy)
  expect_identical(
    table_names(con),
    c("appauth_migrations", "auth_sessions", "login_attempts", "users")
  )
  expect_identical(aa_schema_version(con), 5L)
})

test_that("колонки таблиц соответствуют схеме Server Manager", {
  con <- new_db()
  aa_init_db(con)

  expect_identical(columns_of(con, "users"), c("id", "login", "password", "role", "blocked", "must_change"))
  expect_identical(
    columns_of(con, "auth_sessions"),
    c("id", "user_login", "token_hash", "created_at", "expires_at", "revoked")
  )
  expect_identical(columns_of(con, "login_attempts"), c("id", "login", "success", "attempted_at"))
})

test_that("у нового пользователя blocked по умолчанию 0, логин уникален", {
  con <- new_db()
  aa_init_db(con)

  DBI::dbExecute(con, "INSERT INTO users (login, password, role) VALUES ('a', 'x', 'user')")

  expect_identical(DBI::dbGetQuery(con, "SELECT blocked FROM users")$blocked, 0L)
  expect_error(
    DBI::dbExecute(con, "INSERT INTO users (login, password, role) VALUES ('a', 'y', 'user')")
  )
})

test_that("миграции записываются в служебную таблицу", {
  con <- new_db()
  aa_init_db(con)

  migrations <- DBI::dbGetQuery(con, "SELECT version, name FROM appauth_migrations ORDER BY version")

  expect_identical(migrations$version, 1:5)
  expect_identical(
    migrations$name,
    c("users", "users_blocked_column", "auth_sessions", "login_attempts", "users_must_change_column")
  )
})

test_that("повторный запуск ничего не меняет", {
  con <- new_db()
  aa_init_db(con)

  DBI::dbExecute(con, "INSERT INTO users (login, password, role) VALUES ('a', 'x', 'admin')")
  before <- lapply(c("users", "auth_sessions", "login_attempts", "appauth_migrations"), \(t) rows_of(con, t))

  res <- aa_init_db(con)

  after <- lapply(c("users", "auth_sessions", "login_attempts", "appauth_migrations"), \(t) rows_of(con, t))

  expect_identical(res$applied, integer())
  expect_identical(res$version, 5L)
  expect_identical(before, after)
})

test_that("Server Manager prod: старая схема достраивается, данные не меняются", {
  con <- new_db()
  fixture_server_manager_prod(con)

  users_before    <- rows_of(con, "users")
  sessions_before <- rows_of(con, "auth_sessions")

  res <- aa_init_db(con)

  expect_true(res$legacy)
  expect_identical(res$applied, 1:5)
  expect_true("blocked" %in% columns_of(con, "users"))
  expect_true("login_attempts" %in% table_names(con))

  users_after <- rows_of(con, "users")
  expect_identical(users_after[, names(users_before)], users_before)
  expect_true(all(users_after$blocked == 0))
  expect_identical(rows_of(con, "auth_sessions"), sessions_before)
})

test_that("старая схема dev без колонки id тоже достраивается", {
  con <- new_db()
  fixture_server_manager_dev_old(con)

  users_before <- rows_of(con, "users")

  res <- aa_init_db(con)

  expect_true(res$legacy)
  expect_false("id" %in% columns_of(con, "users"))
  expect_true("blocked" %in% columns_of(con, "users"))

  users_after <- rows_of(con, "users")
  expect_identical(users_after[, names(users_before)], users_before)
  expect_true(all(users_after$blocked == 0))
})

test_that("рекрутинг: пароли в открытом виде и root/root остаются как есть, прикладные таблицы не затронуты", {
  con <- new_db()
  fixture_recruitment(con)

  users_before <- rows_of(con, "users")
  log_before   <- rows_of(con, "action_log")

  res <- aa_init_db(con)

  expect_true(res$legacy)
  expect_identical(
    table_names(con),
    c("action_log", "appauth_migrations", "auth_sessions", "login_attempts", "users")
  )

  users_after <- rows_of(con, "users")
  expect_identical(users_after[, names(users_before)], users_before)
  expect_true("root" %in% users_after$login)
  expect_identical(rows_of(con, "action_log"), log_before)
})

test_that("повторный запуск на старых схемах тоже ничего не меняет", {
  for (fixture in list(fixture_server_manager_prod, fixture_server_manager_dev_old, fixture_recruitment)) {
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

test_that("при ошибке в миграции изменения откатываются одной транзакцией", {
  con <- new_db()

  testthat::local_mocked_bindings(
    aa_migrations = function() {
      list(
        list(version = 1L, name = "ok",   up = function(conn) DBI::dbExecute(conn, "CREATE TABLE users (login TEXT)")),
        list(version = 2L, name = "boom", up = function(conn) stop("сбой миграции"))
      )
    }
  )

  expect_error(aa_init_db(con), "сбой миграции")
  expect_identical(table_names(con), character())
})

test_that("aa_init_db и aa_schema_version отклоняют не SQLite и закрытые подключения", {
  expect_error(aa_init_db(list()), class = "appauth_error_connection")
  expect_error(aa_schema_version("not a connection"), class = "appauth_error_connection")

  con <- new_db()
  DBI::dbDisconnect(con)

  expect_error(aa_init_db(con), class = "appauth_error_connection")
})

test_that("aa_cleanup удаляет только устаревшие попытки и токены", {
  con <- new_db()
  aa_init_db(con)

  DBI::dbExecute(con, "
    INSERT INTO login_attempts (login, success, attempted_at) VALUES
      ('old',  0, datetime('now', '-25 hours')),
      ('new',  0, datetime('now', '-1 hours'))")
  DBI::dbExecute(con, "
    INSERT INTO auth_sessions (user_login, token_hash, created_at, expires_at, revoked) VALUES
      ('u', 'expired_long',  datetime('now', '-90 days'), datetime('now', '-60 days'), 0),
      ('u', 'revoked_long',  datetime('now', '-50 days'), datetime('now', '+10 days'), 1),
      ('u', 'revoked_new',   datetime('now', '-2 days'),  datetime('now', '+28 days'), 1),
      ('u', 'expired_new',   datetime('now', '-35 days'), datetime('now', '-5 days'),  0),
      ('u', 'active',        datetime('now', '-1 days'),  datetime('now', '+29 days'), 0)")

  res <- aa_cleanup(con, aa_settings())

  expect_identical(res$login_attempts, 1L)
  expect_identical(res$auth_sessions, 2L)
  expect_identical(DBI::dbGetQuery(con, "SELECT login FROM login_attempts")$login, "new")
  expect_setequal(
    DBI::dbGetQuery(con, "SELECT token_hash FROM auth_sessions")$token_hash,
    c("revoked_new", "expired_new", "active")
  )
})

test_that("aa_cleanup учитывает сроки хранения из настроек", {
  con <- new_db()
  aa_init_db(con)

  DBI::dbExecute(con, "
    INSERT INTO login_attempts (login, success, attempted_at) VALUES
      ('a', 0, datetime('now', '-3 hours')),
      ('b', 0, datetime('now', '-30 minutes'))")

  res <- aa_cleanup(con, aa_settings(attempts_retention_hours = 2))

  expect_identical(res$login_attempts, 1L)
  expect_identical(DBI::dbGetQuery(con, "SELECT login FROM login_attempts")$login, "b")
})

test_that("aa_prepare_db подготавливает базу и не бросает ошибок", {
  con <- new_db()

  expect_true(suppressMessages(aa_prepare_db(con, aa_settings())))
  expect_identical(aa_schema_version(con), 5L)

  expect_message(aa_prepare_db(new_db(), aa_settings()), "применены миграции схемы")
})

test_that("aa_prepare_db при ошибке возвращает FALSE и пишет предупреждение в лог", {
  con <- new_db()
  DBI::dbDisconnect(con)

  expect_message(res <- aa_prepare_db(con, aa_settings()), "ВНИМАНИЕ")
  expect_false(res)

  expect_message(res2 <- aa_prepare_db(list(), aa_settings()), "ВНИМАНИЕ")
  expect_false(res2)
})
