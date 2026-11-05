# Схема таблиц авторизации и её версионные миграции.
#
# Пакет владеет семью таблицами:
#   users             - пользователи (логин, хеш пароля, роль, признак блокировки, email);
#   auth_sessions     - токены автовхода (хранится sha256 токена);
#   login_attempts    - попытки входа для защиты от подбора пароля;
#   password_resets   - одноразовые токены восстановления пароля (хранится sha256 токена);
#   totp_recovery     - резервные коды двухфакторной аутентификации (хранится sha256 кода);
#   oauth_states      - одноразовые параметры входа через Google (хранится sha256 state);
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
#' Таблицы и колонки одинаковы во всех базах, различаются только типы и
#' автоинкремент (см. dialect.R). В SQLite схема совпадает с прежней.
#'
#' @returns Список миграций, у каждой `version`, `name` и функция `up(conn)`.
#' @noRd
aa_migrations <- function() {
  list(
    list(
      version = 1L,
      name    = "users",
      up      = function(conn) {
        t <- aa_col_types(conn)

        # DuckDB не позволяет менять таблицу, на которую уже есть индекс (а на users он
        # появится в миграции 7), поэтому там все поздние колонки создаются сразу;
        # миграции 2, 5, 6, 7 и 8 проверяют наличие колонок и ничего не добавят
        later <- if (identical(aa_dialect(conn), "duckdb")) {
          paste0(",
            blocked        INTEGER NOT NULL DEFAULT 0,
            must_change    INTEGER NOT NULL DEFAULT 0,
            created_at     ", t$ts, ",
            last_login_at  ", t$ts, ",
            email          ", t$key, ",
            totp_secret    ", t$text, ",
            totp_enabled   INTEGER NOT NULL DEFAULT 0,
            totp_last_step INTEGER NOT NULL DEFAULT 0")
        } else {
          ""
        }

        aa_execute(conn, paste0("
          CREATE TABLE IF NOT EXISTS users (
            ", aa_pk_column(conn, "users"), ",
            login    ", t$key, " UNIQUE NOT NULL,
            password ", t$text, " NOT NULL,
            role     ", t$key, " NOT NULL", later, "
          )
        "))
      }
    ),
    list(
      version = 2L,
      name    = "users_blocked_column",
      up      = function(conn) {
        cols <- aa_table_columns(conn, "users")

        if (!"blocked" %in% cols) {
          aa_execute(conn, "ALTER TABLE users ADD COLUMN blocked INTEGER NOT NULL DEFAULT 0")
        }
      }
    ),
    list(
      version = 3L,
      name    = "auth_sessions",
      up      = function(conn) {
        t <- aa_col_types(conn)

        aa_execute(conn, paste0("
          CREATE TABLE IF NOT EXISTS auth_sessions (
            ", aa_pk_column(conn, "auth_sessions"), ",
            user_login ", t$key, " NOT NULL,
            token_hash ", t$key, " NOT NULL,
            created_at ", t$ts_now, ",
            expires_at ", t$ts, " NOT NULL,
            revoked    INTEGER DEFAULT 0
          )
        "))
        aa_create_index(conn, "idx_auth_sessions_token", "auth_sessions", "token_hash")
        aa_create_index(conn, "idx_auth_sessions_user", "auth_sessions", "user_login")
      }
    ),
    list(
      version = 4L,
      name    = "login_attempts",
      up      = function(conn) {
        t <- aa_col_types(conn)

        aa_execute(conn, paste0("
          CREATE TABLE IF NOT EXISTS login_attempts (
            ", aa_pk_column(conn, "login_attempts"), ",
            login        ", t$key, " NOT NULL,
            success      INTEGER NOT NULL,
            attempted_at ", t$ts_now, " NOT NULL
          )
        "))
        aa_create_index(conn, "idx_login_attempts_login", "login_attempts", "login, attempted_at")
      }
    ),
    list(
      version = 5L,
      name    = "users_must_change_column",
      up      = function(conn) {
        cols <- aa_table_columns(conn, "users")

        if (!"must_change" %in% cols) {
          aa_execute(conn, "ALTER TABLE users ADD COLUMN must_change INTEGER NOT NULL DEFAULT 0")
        }
      }
    ),
    list(
      version = 6L,
      name    = "users_created_and_last_login_columns",
      up      = function(conn) {
        cols <- aa_table_columns(conn, "users")
        t <- aa_col_types(conn)

        # SQLite не разрешает DEFAULT CURRENT_TIMESTAMP в ALTER TABLE, поэтому колонки
        # допускают NULL: у уже существующих пользователей даты неизвестны
        if (!"created_at" %in% cols) {
          aa_execute(conn, paste("ALTER TABLE users ADD COLUMN created_at", t$ts))
        }

        if (!"last_login_at" %in% cols) {
          aa_execute(conn, paste("ALTER TABLE users ADD COLUMN last_login_at", t$ts))
        }
      }
    ),
    list(
      version = 7L,
      name    = "password_resets_and_email",
      up      = function(conn) {
        cols <- aa_table_columns(conn, "users")
        t <- aa_col_types(conn)

        # email хранится в нижнем регистре и допускает NULL: у существующих
        # пользователей адреса нет; уникальность действует только для заданных адресов
        # (во всех поддерживаемых базах несколько NULL в уникальном индексе допустимы)
        if (!"email" %in% cols) {
          aa_execute(conn, paste("ALTER TABLE users ADD COLUMN email", t$key))
        }

        aa_create_index(conn, "idx_users_email", "users", "email", unique = TRUE)

        aa_execute(conn, paste0("
          CREATE TABLE IF NOT EXISTS password_resets (
            ", aa_pk_column(conn, "password_resets"), ",
            user_login ", t$key, " NOT NULL,
            token_hash ", t$key, " NOT NULL,
            created_at ", t$ts_now, " NOT NULL,
            expires_at ", t$ts, " NOT NULL,
            used       INTEGER NOT NULL DEFAULT 0
          )
        "))
        aa_create_index(conn, "idx_password_resets_token", "password_resets", "token_hash")
        aa_create_index(conn, "idx_password_resets_user", "password_resets", "user_login, created_at")
      }
    ),
    list(
      version = 8L,
      name    = "totp_two_factor",
      up      = function(conn) {
        cols <- aa_table_columns(conn, "users")
        t <- aa_col_types(conn)

        # секрет хранится зашифрованным (см. aa_totp_seal), у существующих пользователей
        # двухфакторная аутентификация выключена
        if (!"totp_secret" %in% cols) {
          aa_execute(conn, paste("ALTER TABLE users ADD COLUMN totp_secret", t$text))
        }

        if (!"totp_enabled" %in% cols) {
          aa_execute(conn, "ALTER TABLE users ADD COLUMN totp_enabled INTEGER NOT NULL DEFAULT 0")
        }

        if (!"totp_last_step" %in% cols) {
          aa_execute(conn, "ALTER TABLE users ADD COLUMN totp_last_step INTEGER NOT NULL DEFAULT 0")
        }

        aa_execute(conn, paste0("
          CREATE TABLE IF NOT EXISTS totp_recovery (
            ", aa_pk_column(conn, "totp_recovery"), ",
            user_login ", t$key, " NOT NULL,
            code_hash  ", t$key, " NOT NULL,
            used       INTEGER NOT NULL DEFAULT 0,
            created_at ", t$ts_now, " NOT NULL
          )
        "))
        aa_create_index(conn, "idx_totp_recovery_user", "totp_recovery", "user_login, code_hash")
      }
    ),
    list(
      version = 9L,
      name    = "oauth_states",
      up      = function(conn) {
        t <- aa_col_types(conn)

        # вход через Google: state хранится только в виде sha256, запись живёт минуты и
        # используется один раз; nonce и PKCE-проверка нужны при возврате от Google
        aa_execute(conn, paste0("
          CREATE TABLE IF NOT EXISTS oauth_states (
            ", aa_pk_column(conn, "oauth_states"), ",
            state_hash    ", t$key, " NOT NULL,
            nonce         ", t$key, " NOT NULL,
            code_verifier ", t$key, " NOT NULL,
            created_at    ", t$ts_now, " NOT NULL,
            expires_at    ", t$ts, " NOT NULL,
            used          INTEGER NOT NULL DEFAULT 0
          )
        "))
        aa_create_index(conn, "idx_oauth_states_hash", "oauth_states", "state_hash", unique = TRUE)
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
#' @param conn Подключение к базе данных: SQLite, DuckDB, MySQL / MariaDB или PostgreSQL
#'   (`DBI::dbConnect()` с драйвером RSQLite, duckdb, RMariaDB или RPostgres).
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
  aa_check_conn(conn)

  legacy <- DBI::dbExistsTable(conn, "users") &&
    !DBI::dbExistsTable(conn, "appauth_migrations")

  applied <- integer()
  t <- aa_col_types(conn)

  DBI::dbWithTransaction(conn, {
    release <- aa_migration_lock(conn)
    on.exit(release(), add = TRUE)

    aa_execute(conn, paste0("
      CREATE TABLE IF NOT EXISTS appauth_migrations (
        version    INTEGER PRIMARY KEY,
        name       ", t$key, " NOT NULL,
        applied_at ", t$ts_now, " NOT NULL
      )
    "))

    done <- aa_query(conn, "SELECT version FROM appauth_migrations")$version

    for (migration in aa_migrations()) {
      if (migration$version %in% done) next

      migration$up(conn)

      aa_execute(
        conn,
        aa_insert_ignore_sql(conn, "appauth_migrations", c("version", "name", "applied_at")),
        params = list(migration$version, migration$name, aa_utc())
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
  aa_check_conn(conn)

  if (!DBI::dbExistsTable(conn, "appauth_migrations")) {
    return(0L)
  }

  version <- aa_query(conn, "SELECT MAX(version) AS v FROM appauth_migrations")$v

  if (is.na(version)) 0L else as.integer(version)
}

#' Удалить устаревшие данные авторизации
#'
#' Удаляет записи о попытках входа старше `attempts_retention_hours` часов, а
#' также просроченные и отозванные токены автовхода старше `token_retention_days`
#' дней, а также использованные и просроченные токены восстановления пароля
#' и параметры входа через Google старше суток. Активные токены и свежие попытки не затрагиваются. Вызывать нужно
#' после [aa_init_db()].
#'
#' @inheritParams aa_init_db
#' @param settings Настройки, результат [aa_settings()].
#'
#' @returns Список (невидимо): `login_attempts` (число удалённых попыток входа),
#'   `auth_sessions` (число удалённых токенов) и `password_resets` (число удалённых
#'   токенов восстановления пароля) и `oauth_states` (число удалённых параметров входа
#'   через Google).
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
  aa_check_conn(conn)

  attempts_cutoff <- aa_utc(-3600 * as.integer(settings$attempts_retention_hours))
  token_cutoff    <- aa_utc(-86400 * as.integer(settings$token_retention_days))
  day_cutoff      <- aa_utc(-86400)

  attempts <- aa_execute(
    conn,
    "DELETE FROM login_attempts WHERE attempted_at < ?",
    params = list(attempts_cutoff)
  )

  sessions <- aa_execute(
    conn,
    "DELETE FROM auth_sessions
     WHERE expires_at < ?
        OR (revoked = 1 AND created_at < ?)",
    params = list(token_cutoff, token_cutoff)
  )

  # таблицы восстановления пароля может не быть, если схема не достроена
  resets <- tryCatch(
    aa_execute(
      conn,
      "DELETE FROM password_resets WHERE expires_at < ?
         OR (used = 1 AND created_at < ?)",
      params = list(day_cutoff, day_cutoff)
    ),
    error = function(e) 0L
  )

  oauth <- tryCatch(
    aa_execute(conn, "DELETE FROM oauth_states WHERE expires_at < ?", params = list(day_cutoff)),
    error = function(e) 0L
  )

  invisible(list(
    login_attempts = attempts, auth_sessions = sessions, password_resets = resets,
    oauth_states = oauth
  ))
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

    if (cleaned$login_attempts + cleaned$auth_sessions + cleaned$password_resets > 0) {
      message(
        "appauth: удалено устаревших записей: попыток входа ", cleaned$login_attempts,
        ", токенов ", cleaned$auth_sessions,
        ", токенов восстановления пароля ", cleaned$password_resets
      )
    }

    invisible(TRUE)
  }, error = function(e) {
    message("ВНИМАНИЕ: appauth не подготовил базу данных: ", conditionMessage(e))
    invisible(FALSE)
  })
}
