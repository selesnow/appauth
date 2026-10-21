# Схема таблиц авторизации и её версионные миграции.
#
# Пакет владеет четырьмя таблицами:
#   users             - пользователи (логин, хеш пароля, роль, признак блокировки);
#   auth_sessions     - токены автовхода (хранится sha256 токена);
#   login_attempts    - попытки входа для защиты от подбора пароля;
#   appauth_migrations - служебная таблица версий миграций.
#
# Имена и колонки таблиц совпадают с базами приложения Server Manager, поэтому
# работающие базы подключаются без переноса данных. Каждая миграция
# идемпотентна: она проверяет, что уже существует, и создаёт только
# недостающее, не изменяя существующие данные. Поэтому старые схемы (таблица
# users без колонки id или без blocked, база без остальных таблиц, пароли в
# открытом виде) распознаются и достраиваются без потерь.

#' Список миграций схемы
#'
#' @returns Список миграций, у каждой `version`, `name` и функция `up(conn)`.
#' @noRd
aa_migrations <- function() {
  list(
    list(
      version = 1L,
      name    = "users",
      up      = function(conn) {
        DBI::dbExecute(conn, "
          CREATE TABLE IF NOT EXISTS users (
            id       INTEGER PRIMARY KEY AUTOINCREMENT,
            login    TEXT UNIQUE NOT NULL,
            password TEXT NOT NULL,
            role     TEXT NOT NULL
          )
        ")
      }
    ),
    list(
      version = 2L,
      name    = "users_blocked_column",
      up      = function(conn) {
        cols <- DBI::dbGetQuery(conn, "SELECT name FROM pragma_table_info('users')")$name

        if (!"blocked" %in% cols) {
          DBI::dbExecute(conn, "ALTER TABLE users ADD COLUMN blocked INTEGER NOT NULL DEFAULT 0")
        }
      }
    ),
    list(
      version = 3L,
      name    = "auth_sessions",
      up      = function(conn) {
        DBI::dbExecute(conn, "
          CREATE TABLE IF NOT EXISTS auth_sessions (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            user_login TEXT NOT NULL,
            token_hash TEXT NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            expires_at DATETIME NOT NULL,
            revoked    INTEGER DEFAULT 0
          )
        ")
        DBI::dbExecute(conn, "
          CREATE INDEX IF NOT EXISTS idx_auth_sessions_token ON auth_sessions (token_hash)
        ")
        DBI::dbExecute(conn, "
          CREATE INDEX IF NOT EXISTS idx_auth_sessions_user ON auth_sessions (user_login)
        ")
      }
    ),
    list(
      version = 4L,
      name    = "login_attempts",
      up      = function(conn) {
        DBI::dbExecute(conn, "
          CREATE TABLE IF NOT EXISTS login_attempts (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            login        TEXT NOT NULL,
            success      INTEGER NOT NULL,
            attempted_at TEXT NOT NULL DEFAULT (datetime('now'))
          )
        ")
        DBI::dbExecute(conn, "
          CREATE INDEX IF NOT EXISTS idx_login_attempts_login ON login_attempts (login, attempted_at)
        ")
      }
    )
  )
}

#' Создать или обновить схему таблиц авторизации
#'
#' Применяет версионные миграции: создаёт недостающие таблицы и колонки и
#' записывает применённые версии в служебную таблицу `appauth_migrations`.
#' Существующие данные не изменяются, повторный запуск ничего не меняет.
#' Распознаются и старые схемы (например, таблица `users` без колонки `id` или
#' без `blocked`, база без таблиц сессий и попыток входа): недостающее
#' достраивается, пользователи, пароли и токены остаются как были.
#'
#' Миграции выполняются одной транзакцией: при ошибке изменения откатываются.
#' Функцию безопасно вызывать при каждом запуске приложения, в том числе на
#' работающих базах. Для запуска, который не должен останавливать приложение
#' при ошибке, используйте [aa_prepare_db()].
#'
#' @param conn Подключение к базе SQLite (`DBI::dbConnect(RSQLite::SQLite(), ...)`).
#'
#' @returns Список (невидимо): `applied` (версии миграций, применённые в этом
#'   вызове), `version` (текущая версия схемы) и `legacy` (`TRUE`, если таблица
#'   `users` уже существовала до подключения пакета).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_schema_version(conn)
#'   DBI::dbDisconnect(conn)
#' }
aa_init_db <- function(conn) {
  aa_check_sqlite(conn)

  legacy <- DBI::dbExistsTable(conn, "users") &&
    !DBI::dbExistsTable(conn, "appauth_migrations")

  applied <- integer()

  DBI::dbWithTransaction(conn, {
    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS appauth_migrations (
        version    INTEGER PRIMARY KEY,
        name       TEXT NOT NULL,
        applied_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ")

    done <- DBI::dbGetQuery(conn, "SELECT version FROM appauth_migrations")$version

    for (migration in aa_migrations()) {
      if (migration$version %in% done) next

      migration$up(conn)

      DBI::dbExecute(
        conn,
        "INSERT OR IGNORE INTO appauth_migrations (version, name) VALUES (?, ?)",
        params = list(migration$version, migration$name)
      )

      applied <- c(applied, migration$version)
    }
  })

  invisible(list(
    applied = applied,
    version = aa_schema_version(conn),
    legacy  = legacy
  ))
}

#' Текущая версия схемы таблиц авторизации
#'
#' @inheritParams aa_init_db
#'
#' @returns Целое число: номер последней применённой миграции или `0`, если
#'   схема ещё не создана пакетом.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_schema_version(conn)
#'   aa_init_db(conn)
#'   aa_schema_version(conn)
#'   DBI::dbDisconnect(conn)
#' }
aa_schema_version <- function(conn) {
  aa_check_sqlite(conn)

  if (!DBI::dbExistsTable(conn, "appauth_migrations")) {
    return(0L)
  }

  version <- DBI::dbGetQuery(conn, "SELECT MAX(version) AS v FROM appauth_migrations")$v

  if (is.na(version)) 0L else as.integer(version)
}

#' Удалить устаревшие данные авторизации
#'
#' Удаляет записи о попытках входа старше `attempts_retention_hours` часов, а
#' также просроченные и отозванные токены автовхода старше `token_retention_days`
#' дней. Активные токены и свежие попытки не затрагиваются. Вызывать нужно после
#' [aa_init_db()].
#'
#' @inheritParams aa_init_db
#' @param settings Настройки, результат [aa_settings()].
#'
#' @returns Список (невидимо): `login_attempts` (число удалённых попыток входа)
#'   и `auth_sessions` (число удалённых токенов).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_cleanup(conn)
#'   DBI::dbDisconnect(conn)
#' }
aa_cleanup <- function(conn, settings = aa_settings()) {
  aa_check_sqlite(conn)

  attempts_age <- sprintf("-%d hours", as.integer(settings$attempts_retention_hours))
  token_age    <- sprintf("-%d days", as.integer(settings$token_retention_days))

  attempts <- DBI::dbExecute(
    conn,
    "DELETE FROM login_attempts WHERE attempted_at < datetime('now', ?)",
    params = list(attempts_age)
  )

  sessions <- DBI::dbExecute(
    conn,
    "DELETE FROM auth_sessions
     WHERE expires_at < datetime('now', ?)
        OR (revoked = 1 AND created_at < datetime('now', ?))",
    params = list(token_age, token_age)
  )

  invisible(list(login_attempts = attempts, auth_sessions = sessions))
}

#' Подготовка базы при запуске приложения
#'
#' Вызывает [aa_init_db()] и [aa_cleanup()] и **никогда не останавливает
#' приложение**: при ошибке пишет сообщение в лог приложения и возвращает
#' `FALSE`. Рассчитана на вызов один раз при старте приложения. Без подготовленных
#' таблиц защита от перебора и блокировки работать не будут, а вход по паролю
#' продолжит работать.
#'
#' @inheritParams aa_cleanup
#'
#' @returns `TRUE`, если схема подготовлена, иначе `FALSE` (невидимо).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_prepare_db(conn, aa_settings())
#'   DBI::dbDisconnect(conn)
#' }
aa_prepare_db <- function(conn, settings = aa_settings()) {
  tryCatch({
    init <- aa_init_db(conn)
    cleaned <- aa_cleanup(conn, settings)

    if (length(init$applied) > 0) {
      message("appauth: применены миграции схемы: ", paste(init$applied, collapse = ", "))
    }

    if (cleaned$login_attempts + cleaned$auth_sessions > 0) {
      message(
        "appauth: удалено устаревших записей: попыток входа ", cleaned$login_attempts,
        ", токенов ", cleaned$auth_sessions
      )
    }

    invisible(TRUE)
  }, error = function(e) {
    message("ВНИМАНИЕ: appauth не подготовил базу данных: ", conditionMessage(e))
    invisible(FALSE)
  })
}
