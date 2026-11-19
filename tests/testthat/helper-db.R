# Test helpers: temporary databases and "legacy" schema fixtures.
#
# Tests run on the database set by the APPAUTH_TEST_DB environment variable:
# sqlite (default), duckdb, mysql or postgres. For mysql and postgres
# the APPAUTH_TEST_MYSQL_* / APPAUTH_TEST_PG_* variables are needed (HOST, PORT, USER,
# PASSWORD, DBNAME); without them such tests are skipped. Each test gets an
# empty database: on server databases all tables of the test schema are dropped before and after
# the test, so DBNAME must point to a separate test schema.

test_backend <- function() tolower(Sys.getenv("APPAUTH_TEST_DB", "sqlite"))

# The test uses SQL or fixtures specific to SQLite.
skip_if_not_sqlite <- function() {
  testthat::skip_if(test_backend() != "sqlite", "SQLite-only test")
}

# Server database environment variable or skip the test.
test_env <- function(prefix, name) {
  value <- Sys.getenv(paste0("APPAUTH_TEST_", prefix, "_", name), "")
  testthat::skip_if(!nzchar(value) && name %in% c("HOST", "USER", "DBNAME"),
                    paste0("APPAUTH_TEST_", prefix, "_", name, " is not set"))
  value
}

# Drop all tables of the test server database.
drop_all_tables <- function(con) {
  dialect <- aa_dialect(con)

  if (dialect == "mysql") {
    DBI::dbExecute(con, "SET FOREIGN_KEY_CHECKS = 0")
    for (tbl in DBI::dbListTables(con)) {
      DBI::dbExecute(con, paste0("DROP TABLE IF EXISTS `", tbl, "`"))
    }
    DBI::dbExecute(con, "SET FOREIGN_KEY_CHECKS = 1")
  } else if (dialect == "postgres") {
    DBI::dbExecute(con, "DROP SCHEMA IF EXISTS public CASCADE")
    DBI::dbExecute(con, "CREATE SCHEMA public")
  }

  invisible(NULL)
}

# A new empty database, closed automatically at the end of the test.
new_db <- function(env = parent.frame()) {
  backend <- test_backend()

  con <- switch(
    backend,
    sqlite = {
      testthat::skip_if_not_installed("RSQLite")
      DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    },
    duckdb = {
      testthat::skip_if_not_installed("duckdb")
      DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), ":memory:")
    },
    mysql = {
      testthat::skip_if_not_installed("RMariaDB")
      DBI::dbConnect(
        RMariaDB::MariaDB(),
        host = test_env("MYSQL", "HOST"), port = as.integer(test_env("MYSQL", "PORT")),
        user = test_env("MYSQL", "USER"), password = test_env("MYSQL", "PASSWORD"),
        dbname = test_env("MYSQL", "DBNAME")
      )
    },
    postgres = {
      testthat::skip_if_not_installed("RPostgres")
      DBI::dbConnect(
        RPostgres::Postgres(),
        host = test_env("PG", "HOST"), port = as.integer(test_env("PG", "PORT")),
        user = test_env("PG", "USER"), password = test_env("PG", "PASSWORD"),
        dbname = test_env("PG", "DBNAME")
      )
    },
    stop("Unknown test database: ", backend)
  )

  drop_all_tables(con)

  # a test may close the connection itself, so check before closing
  withr::defer({
    if (DBI::dbIsValid(con)) {
      drop_all_tables(con)
      if (backend == "duckdb") DBI::dbDisconnect(con, shutdown = TRUE) else DBI::dbDisconnect(con)
    }
  }, envir = env)

  con
}

# A database with the authentication schema, closed at the end of the test.
users_db <- function(env = parent.frame()) {
  con <- new_db(env)
  aa_init_db(con)
  con
}

# Test SQL: datetime('now', '-1 hours') is replaced with a UTC literal, placeholders
# are converted to the database form. This way the same queries run on all databases.
sqlt <- function(sql) {
  pattern <- "datetime[(]'now'((?:,\\s*'[^']*')*)[)]"
  hits <- gregexpr(pattern, sql, perl = TRUE)

  regmatches(sql, hits) <- lapply(regmatches(sql, hits), function(found) {
    vapply(found, function(x) {
      mods <- regmatches(x, gregexpr("'[^']*'", x))[[1]][-1]
      seconds <- sum(vapply(gsub("'", "", mods), function(m) {
        parts <- strsplit(m, " ")[[1]]
        unit <- c(second = 1, seconds = 1, minutes = 60, hours = 3600, days = 86400)[[parts[2]]]
        as.numeric(parts[1]) * unit
      }, numeric(1)))
      paste0("'", aa_utc(seconds), "'")
    }, character(1), USE.NAMES = FALSE)
  })

  sql
}

texec <- function(con, sql, params = NULL) aa_execute(con, sqlt(sql), params)
# Query result: integer values are converted to integer, as SQLite returns them
# (DuckDB returns COUNT(*) as a double).
tquery <- function(con, sql, params = NULL) {
  res <- aa_query(con, sqlt(sql), params)

  for (i in seq_along(res)) {
    x <- res[[i]]
    if (is.double(x) && all(is.na(x) | (x == round(x) & abs(x) < .Machine$integer.max))) {
      res[[i]] <- as.integer(x)
    }
  }

  res
}

# Table names without service ones.
table_names <- function(con) {
  setdiff(sort(DBI::dbListTables(con)), "sqlite_sequence")
}

# Table column names.
columns_of <- function(con, table) {
  aa_table_columns(con, table)
}

# Table contents, ordered for comparison.
rows_of <- function(con, table, order_by = NULL) {
  if (is.null(order_by)) {
    order_by <- if (aa_dialect(con) == "sqlite") "rowid" else if ("id" %in% columns_of(con, table)) "id" else "1"
  }

  tquery(con, sprintf("SELECT * FROM %s ORDER BY %s", table, order_by))
}

# Creates a user without checks and without slow hashing
# (for tests where only the data structure matters, not the password).
raw_user <- function(con, login, role = "user", blocked = 0, password = "x") {
  aa_execute(
    con, "INSERT INTO users (login, password, role, blocked) VALUES (?, ?, ?, ?)",
    params = list(login, password, role, blocked)
  )
}

# Auto-login token of a user, valid for 30 days.
raw_token <- function(con, login, hash, revoked = 0) {
  aa_execute(
    con,
    "INSERT INTO auth_sessions (user_login, token_hash, created_at, expires_at, revoked)
     VALUES (?, ?, ?, ?, ?)",
    params = list(login, hash, aa_utc(), aa_utc(30 * 86400), revoked)
  )
}

# How many days an issued auto-login token has left.
token_days_left <- function(con) {
  expires <- aa_query(con, "SELECT expires_at FROM auth_sessions")$expires_at
  parsed <- as.POSIXct(expires, tz = "UTC", format = "%Y-%m-%d %H:%M:%S")
  as.numeric(difftime(parsed, Sys.time(), units = "days"))
}

revoked_of <- function(con, hash) {
  aa_query(con, "SELECT revoked FROM auth_sessions WHERE token_hash = ?", params = list(hash))$revoked
}

count_users <- function(con) tquery(con, "SELECT COUNT(*) AS n FROM users")$n

stored_password <- function(con, login) {
  aa_query(con, "SELECT password FROM users WHERE login = ?", params = list(login))$password
}

# Login attempt at a given time (UTC): minutes or seconds ago.
add_attempt <- function(con, login, success, minutes_ago = 0, seconds_ago = NULL) {
  ago <- if (!is.null(seconds_ago)) as.integer(seconds_ago) else as.integer(minutes_ago) * 60L

  aa_execute(
    con,
    "INSERT INTO login_attempts (login, success, attempted_at) VALUES (?, ?, ?)",
    params = list(login, as.integer(success), aa_utc(-ago))
  )
}

count_attempts <- function(con) {
  tquery(con, "SELECT COUNT(*) AS n FROM login_attempts")$n
}

# Fixture: a production app on a schema from before login protection was added.
# A users table with id, password hashes, auth_sessions exists, no blocked and login_attempts.
fixture_legacy_full <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      login TEXT UNIQUE NOT NULL,
      password TEXT NOT NULL,
      role TEXT NOT NULL
    )")
  DBI::dbExecute(con, "
    CREATE TABLE auth_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_login TEXT NOT NULL,
      token_hash TEXT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      expires_at DATETIME NOT NULL,
      revoked INTEGER DEFAULT 0
    )")
  DBI::dbExecute(con, "
    INSERT INTO users (login, password, role) VALUES
      ('alsey',    '$7$C6..../....hash-alsey',    'admin'),
      ('clarkson', '$7$C6..../....hash-clarkson', 'user'),
      ('ida',      '$7$C6..../....hash-ida',      'viewer')")
  DBI::dbExecute(con, "
    INSERT INTO auth_sessions (user_login, token_hash, expires_at, revoked) VALUES
      ('alsey', 'tok1', datetime('now', '+10 days'), 0),
      ('ida',   'tok2', datetime('now', '-3 days'),  0)")

  invisible(con)
}

# Fixture: an old dev schema, login is the PRIMARY KEY, no id column.
fixture_legacy_old <- function(con) {
  DBI::dbExecute(con, "CREATE TABLE users (login TEXT PRIMARY KEY, password TEXT, role TEXT)")
  DBI::dbExecute(con, "
    INSERT INTO users VALUES
      ('alsey',  '$7$C6..../....hash-alsey', 'admin'),
      ('tester', 'tester',                   'user')")

  invisible(con)
}

# Fixture: an app with a home-grown schema (reproduced by hand).
# Plain-text passwords, a root/root row, no other authentication tables,
# application tables with data exist.
fixture_legacy_plain <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      login TEXT UNIQUE NOT NULL,
      password TEXT NOT NULL,
      role TEXT NOT NULL
    )")
  DBI::dbExecute(con, "
    CREATE TABLE action_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      datetime DATETIME, func_name TEXT, user TEXT, session_id TEXT, value TEXT
    )")
  DBI::dbExecute(con, "
    INSERT INTO users (login, password, role) VALUES
      ('root',   'root',     'admin'),
      ('hr_one', 'secret12', 'user'),
      ('viewer', 'viewer1',  'viewer')")
  DBI::dbExecute(con, "
    INSERT INTO action_log (datetime, func_name, user, session_id, value)
    VALUES ('2026-10-01 10:00:00', 'Search', 'hr_one', 's1', 'python')")

  invisible(con)
}
