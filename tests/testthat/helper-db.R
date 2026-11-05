# Помощники тестов: временные базы и фикстуры "старых" схем.
#
# Тесты идут на той базе, которую задаёт переменная окружения APPAUTH_TEST_DB:
# sqlite (по умолчанию), duckdb, mysql или postgres. Для mysql и postgres
# нужны переменные APPAUTH_TEST_MYSQL_* / APPAUTH_TEST_PG_* (HOST, PORT, USER,
# PASSWORD, DBNAME); без них такие тесты пропускаются. Каждый тест получает
# пустую базу: в серверных базах перед тестом и после него удаляются все таблицы
# тестовой схемы, поэтому DBNAME должен указывать на отдельную тестовую схему.

test_backend <- function() tolower(Sys.getenv("APPAUTH_TEST_DB", "sqlite"))

# Тест использует SQL или фикстуры, специфичные для SQLite.
skip_if_not_sqlite <- function() {
  testthat::skip_if(test_backend() != "sqlite", "тест только для SQLite")
}

# Переменная окружения серверной базы или пропуск теста.
test_env <- function(prefix, name) {
  value <- Sys.getenv(paste0("APPAUTH_TEST_", prefix, "_", name), "")
  testthat::skip_if(!nzchar(value) && name %in% c("HOST", "USER", "DBNAME"),
                    paste0("не задана APPAUTH_TEST_", prefix, "_", name))
  value
}

# Удалить все таблицы тестовой серверной базы.
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

# Новая пустая база, закрывается автоматически в конце теста.
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
    stop("Неизвестная база для тестов: ", backend)
  )

  drop_all_tables(con)

  # тест может закрыть подключение сам, поэтому проверяем перед закрытием
  withr::defer({
    if (DBI::dbIsValid(con)) {
      drop_all_tables(con)
      if (backend == "duckdb") DBI::dbDisconnect(con, shutdown = TRUE) else DBI::dbDisconnect(con)
    }
  }, envir = env)

  con
}

# База со схемой авторизации, закрывается в конце теста.
users_db <- function(env = parent.frame()) {
  con <- new_db(env)
  aa_init_db(con)
  con
}

# SQL тестов: datetime('now', '-1 hours') заменяется на UTC-литерал, плейсхолдеры
# приводятся к виду базы. Так одни и те же запросы идут на всех базах.
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
# Результат запроса: целые значения приводятся к integer, как их отдаёт SQLite
# (DuckDB возвращает COUNT(*) числом double).
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

# Названия таблиц без служебных.
table_names <- function(con) {
  setdiff(sort(DBI::dbListTables(con)), "sqlite_sequence")
}

# Названия колонок таблицы.
columns_of <- function(con, table) {
  aa_table_columns(con, table)
}

# Содержимое таблицы, упорядоченное для сравнения.
rows_of <- function(con, table, order_by = NULL) {
  if (is.null(order_by)) {
    order_by <- if (aa_dialect(con) == "sqlite") "rowid" else if ("id" %in% columns_of(con, table)) "id" else "1"
  }

  tquery(con, sprintf("SELECT * FROM %s ORDER BY %s", table, order_by))
}

# Создаёт пользователя без проверок и без медленного хеширования
# (для тестов, где важна только структура данных, а не пароль).
raw_user <- function(con, login, role = "user", blocked = 0, password = "x") {
  aa_execute(
    con, "INSERT INTO users (login, password, role, blocked) VALUES (?, ?, ?, ?)",
    params = list(login, password, role, blocked)
  )
}

# Токен автовхода пользователя, действует 30 дней.
raw_token <- function(con, login, hash, revoked = 0) {
  aa_execute(
    con,
    "INSERT INTO auth_sessions (user_login, token_hash, created_at, expires_at, revoked)
     VALUES (?, ?, ?, ?, ?)",
    params = list(login, hash, aa_utc(), aa_utc(30 * 86400), revoked)
  )
}

# Сколько дней осталось у выданного токена автовхода.
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

# Попытка входа с заданным временем (UTC): минуты или секунды назад.
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

# Фикстура: Server Manager на проде до релиза с защитой входа.
# Таблица users с id, хеши паролей, есть auth_sessions, нет blocked и login_attempts.
fixture_server_manager_prod <- function(con) {
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

# Фикстура: старая схема dev Server Manager, login это PRIMARY KEY, колонки id нет.
fixture_server_manager_dev_old <- function(con) {
  DBI::dbExecute(con, "CREATE TABLE users (login TEXT PRIMARY KEY, password TEXT, role TEXT)")
  DBI::dbExecute(con, "
    INSERT INTO users VALUES
      ('alsey',  '$7$C6..../....hash-alsey', 'admin'),
      ('tester', 'tester',                   'user')")

  invisible(con)
}

# Фикстура: приложение рекрутинга (схема воспроизведена вручную по create_db.R).
# Пароли в открытом виде, строка root/root, нет остальных таблиц авторизации,
# есть прикладные таблицы с данными.
fixture_recruitment <- function(con) {
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
