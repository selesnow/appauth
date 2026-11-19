# Schema of the authentication tables and its versioned migrations.
#
# The package owns seven tables:
#   users             - users (login, password hash, role, blocked flag, email);
#   auth_sessions     - auto-login tokens (the sha256 of the token is stored);
#   login_attempts    - login attempts for protection against password guessing;
#   password_resets   - one-time password recovery tokens (the sha256 of the token is stored);
#   totp_recovery     - two-factor authentication recovery codes (the sha256 of the code is stored);
#   oauth_states      - one-time Google sign-in parameters (the sha256 of state is stored);
#   appauth_migrations - a service table of migration versions.
#
# Table names and columns are compatible with schemas created by earlier versions
# of the package, so existing databases are connected without moving data. Each migration is
# idempotent: it checks what already exists and creates only what
# is missing, without changing existing data. So old schemas (a users table
# without an id column or without blocked, a database without the other tables, plain-text
# passwords) are recognized and completed without losses.

#' List of schema migrations
#'
#' Tables and columns are the same in all databases, only the types and
#' auto-increment differ (see dialect.R). In SQLite the schema matches the earlier one.
#'
#' @returns A list of migrations, each with `version`, `name` and an `up(conn)` function.
#' @noRd
aa_migrations <- function() {
  list(
    list(
      version = 1L,
      name    = "users",
      up      = function(conn) {
        t <- aa_col_types(conn)

        # DuckDB does not allow altering a table that already has an index (and users gets one
        # in migration 7), so all the late columns are created at once there;
        # migrations 2, 5, 6, 7 and 8 check that the columns exist and add nothing
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

        # SQLite does not allow DEFAULT CURRENT_TIMESTAMP in ALTER TABLE, so the columns
        # allow NULL: the dates are unknown for existing users
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

        # email is stored in lower case and allows NULL: existing
        # users have no address; uniqueness applies only to set addresses
        # (in all supported databases several NULLs in a unique index are allowed)
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

        # the secret is stored encrypted (see aa_totp_seal), two-factor authentication
        # is off for existing users
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

        # sign-in with Google: state is stored only as sha256, the record lives minutes and
        # is used once; nonce and the PKCE verifier are needed on return from Google
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

#' Create or update the authentication table schema
#'
#' Applies versioned migrations: creates missing tables and columns and
#' records the applied versions in the service table `appauth_migrations`.
#' Existing data is not changed, a repeated run changes nothing.
#' Old schemas are recognized too (for example, a `users` table without an `id` column or
#' without `blocked`, a database without session and login attempt tables): what is missing
#' is completed, users, passwords and tokens stay as they were.
#'
#' Migrations run in a single transaction: on error the changes are rolled back.
#' It is safe to call the function on every app start, including on
#' live databases. For a start that must not stop the app
#' on error, use [aa_prepare_db()].
#'
#' @param conn Database connection: SQLite, DuckDB, MySQL / MariaDB or PostgreSQL
#'   (`DBI::dbConnect()` with the RSQLite, duckdb, RMariaDB or RPostgres driver).
#'
#' @returns A list (invisibly): `applied` (migration versions applied in this
#'   call), `version` (the current schema version) and `legacy` (`TRUE` if the
#'   `users` table already existed before the package was connected).
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

#' Current version of the authentication table schema
#'
#' @inheritParams aa_init_db
#'
#' @returns An integer: the number of the last applied migration or `0` if the
#'   schema has not been created by the package yet.
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

#' Delete stale authentication data
#'
#' Deletes login attempt records older than `attempts_retention_hours` hours, as
#' well as expired and revoked auto-login tokens older than `token_retention_days`
#' days, as well as used and expired password recovery tokens
#' and Google sign-in parameters older than a day. Active tokens and fresh attempts are not touched. Call it
#' after [aa_init_db()].
#'
#' @inheritParams aa_init_db
#' @param settings Settings, the result of [aa_settings()].
#'
#' @returns A list (invisibly): `login_attempts` (the number of deleted login attempts),
#'   `auth_sessions` (the number of deleted tokens), `password_resets` (the number of deleted
#'   password recovery tokens) and `oauth_states` (the number of deleted sign-in parameters
#'   for Google).
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

  # the password recovery table may be missing if the schema is not upgraded
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

#' Prepare the database on app start
#'
#' Calls [aa_init_db()] and [aa_cleanup()] and **never stops
#' the app**: on error it writes a message to the app log and returns
#' `FALSE`. Meant to be called once at app start. Without the prepared
#' tables, protection against guessing and locks will not work, while password sign-in
#' will keep working.
#'
#' @inheritParams aa_cleanup
#'
#' @returns `TRUE` if the schema is prepared, otherwise `FALSE` (invisibly).
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
      message("appauth: schema migrations applied: ", paste(init$applied, collapse = ", "))
    }

    if (cleaned$login_attempts + cleaned$auth_sessions + cleaned$password_resets > 0) {
      message(
        "appauth: stale records deleted: login attempts ", cleaned$login_attempts,
        ", tokens ", cleaned$auth_sessions,
        ", password recovery tokens ", cleaned$password_resets
      )
    }

    invisible(TRUE)
  }, error = function(e) {
    message("WARNING: appauth could not prepare the database: ", conditionMessage(e))
    invisible(FALSE)
  })
}
