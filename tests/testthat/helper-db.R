# Помощники тестов: временные базы SQLite и фикстуры "старых" схем.

# Новая пустая база в памяти, закрывается автоматически в конце теста.
new_db <- function(env = parent.frame()) {
  testthat::skip_if_not_installed("RSQLite")

  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  # тест может закрыть подключение сам, поэтому проверяем перед закрытием
  withr::defer(if (DBI::dbIsValid(con)) DBI::dbDisconnect(con), envir = env)

  con
}

# База со схемой авторизации, закрывается в конце теста.
users_db <- function(env = parent.frame()) {
  con <- new_db(env)
  aa_init_db(con)
  con
}

# Названия таблиц без служебной sqlite_sequence.
table_names <- function(con) {
  setdiff(sort(DBI::dbListTables(con)), "sqlite_sequence")
}

# Названия колонок таблицы.
columns_of <- function(con, table) {
  DBI::dbGetQuery(con, sprintf("SELECT name FROM pragma_table_info('%s')", table))$name
}

# Содержимое таблицы, упорядоченное для сравнения.
rows_of <- function(con, table, order_by = "rowid") {
  DBI::dbGetQuery(con, sprintf("SELECT * FROM %s ORDER BY %s", table, order_by))
}

# Создаёт пользователя без проверок и без медленного хеширования
# (для тестов, где важна только структура данных, а не пароль).
raw_user <- function(con, login, role = "user", blocked = 0, password = "x") {
  DBI::dbExecute(
    con, "INSERT INTO users (login, password, role, blocked) VALUES (?, ?, ?, ?)",
    params = list(login, password, role, blocked)
  )
}

# Токен автовхода пользователя, действует 30 дней.
raw_token <- function(con, login, hash, revoked = 0) {
  DBI::dbExecute(
    con,
    "INSERT INTO auth_sessions (user_login, token_hash, expires_at, revoked)
     VALUES (?, ?, datetime('now', '+30 days'), ?)",
    params = list(login, hash, revoked)
  )
}

revoked_of <- function(con, hash) {
  DBI::dbGetQuery(con, "SELECT revoked FROM auth_sessions WHERE token_hash = ?", params = list(hash))$revoked
}

count_users <- function(con) DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM users")$n

stored_password <- function(con, login) {
  DBI::dbGetQuery(con, "SELECT password FROM users WHERE login = ?", params = list(login))$password
}

# Попытка входа с заданным временем (UTC): минуты или секунды назад.
add_attempt <- function(con, login, success, minutes_ago = 0, seconds_ago = NULL) {
  offset <- if (!is.null(seconds_ago)) {
    sprintf("-%d seconds", as.integer(seconds_ago))
  } else {
    sprintf("-%d minutes", as.integer(minutes_ago))
  }

  DBI::dbExecute(
    con,
    "INSERT INTO login_attempts (login, success, attempted_at) VALUES (?, ?, datetime('now', ?))",
    params = list(login, as.integer(success), offset)
  )
}

count_attempts <- function(con) {
  DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM login_attempts")$n
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
