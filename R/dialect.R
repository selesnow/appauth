# Dialect layer: everything that differs between databases.
#
# The package works with SQLite (the default), DuckDB, MySQL / MariaDB and PostgreSQL.
# So that the rest of the code does not depend on the database, the differences are collected here:
#   * R computes the time and passes it as a parameter (a UTC string "YYYY-MM-DD HH:MM:SS"),
#     so queries have no datetime('now'), NOW() and the like;
#   * the aa_query() and aa_execute() wrappers substitute placeholders of the right kind;
#   * column types, auto-increment and indexes are described by the functions below.
# Dates are stored everywhere as UTC text: this way date comparison is the same in all databases,
# and existing SQLite databases stay compatible without moving data.

# Supported databases
#
# @returns Dialect names.
# @noRd
aa_dialects <- function() c("sqlite", "duckdb", "mysql", "postgres")

# Database dialect by connection
#
# @param conn A DBI connection.
#
# @returns `"sqlite"`, `"duckdb"`, `"mysql"` (MySQL and MariaDB), `"postgres"`
#   or `NA` if the database is not supported.
# @noRd
aa_dialect <- function(conn) {
  if (inherits(conn, "SQLiteConnection")) {
    "sqlite"
  } else if (inherits(conn, "duckdb_connection")) {
    "duckdb"
  } else if (
    inherits(conn, "MariaDBConnection") || inherits(conn, "MySQLConnection")
  ) {
    "mysql"
  } else if (inherits(conn, "PqConnection")) {
    "postgres"
  } else {
    NA_character_
  }
}

# Database connection check
#
# The connection must be open and belong to one of the supported databases:
# SQLite (`RSQLite`), DuckDB (`duckdb`), MySQL / MariaDB (`RMariaDB`) or
# PostgreSQL (`RPostgres`).
#
# @param conn Database connection.
# @param call Environment for the error message.
#
# @returns The connection (invisibly), or an error of class
# `appauth_error_connection`.
# @noRd
aa_check_conn <- function(conn, call = rlang::caller_env()) {
  if (is.na(aa_dialect(conn))) {
    rlang::abort(
      paste0(
        "The appauth package works with SQLite, DuckDB, MySQL / MariaDB and PostgreSQL databases: ",
        "pass a connection created with `DBI::dbConnect()` and the driver ",
        "RSQLite::SQLite(), duckdb::duckdb(), RMariaDB::MariaDB() or RPostgres::Postgres()."
      ),
      class = "appauth_error_connection",
      call = call
    )
  }

  if (!DBI::dbIsValid(conn)) {
    rlang::abort(
      "The database connection is closed, open it again.",
      class = "appauth_error_connection",
      call = call
    )
  }

  invisible(conn)
}

# Current UTC time for writing to the database
#
# @param offset_seconds Offset in seconds from the current moment (may be
# negative).
# @param now The moment to count from (for tests).
#
# @returns A `"YYYY-MM-DD HH:MM:SS"` string in UTC.
# @noRd
aa_utc <- function(offset_seconds = 0, now = Sys.time()) {
  format(now + offset_seconds, "%Y-%m-%d %H:%M:%S", tz = "UTC")
}

# Replace `?` placeholders with the form the database understands
#
# PostgreSQL (RPostgres) accepts only `$1, $2, ...`, other databases accept
# `?`.
# In the package queries the `?` sign does not occur inside string literals.
#
# @param conn Database connection.
# @param sql Query text with `?` placeholders.
#
# @returns Query text.
# @noRd
aa_prepare_sql <- function(conn, sql) {
  if (
    !identical(aa_dialect(conn), "postgres") || !grepl("?", sql, fixed = TRUE)
  ) {
    return(sql)
  }

  pieces <- strsplit(paste0(sql, "\001"), "?", fixed = TRUE)[[1]]
  n <- length(pieces) - 1L

  out <- paste0(
    paste0(pieces[seq_len(n)], "$", seq_len(n), collapse = ""),
    pieces[n + 1L]
  )
  sub("\001", "", out, fixed = TRUE)
}

# Convert 64-bit integers to ordinary numbers
#
# `COUNT(*)` in PostgreSQL and MySQL is returned as `integer64`, which
# is inconvenient to compare and format.
#
# @param x Query result table.
#
# @returns A table where `integer64` is replaced with numbers.
# @noRd
aa_fix_integers <- function(x) {
  for (i in seq_along(x)) {
    if (inherits(x[[i]], "integer64")) {
      x[[i]] <- as.numeric(x[[i]])
    }
  }

  x
}

# Run a query with a result
#
# A wrapper around `DBI::dbGetQuery()`: `?` placeholders, numbers without
# `integer64`.
#
# @param conn Database connection.
# @param sql Query text.
# @param params A list of parameters or `NULL`.
#
# @returns A table.
# @noRd
aa_query <- function(conn, sql, params = NULL) {
  sql <- aa_prepare_sql(conn, sql)

  res <- if (is.null(params)) {
    DBI::dbGetQuery(conn, sql)
  } else {
    DBI::dbGetQuery(conn, sql, params = params)
  }

  aa_fix_integers(res)
}

# Run a query without a result
#
# A wrapper around `DBI::dbExecute()`: `?` placeholders.
#
# @inheritParams aa_query
#
# @returns The number of affected rows.
# @noRd
aa_execute <- function(conn, sql, params = NULL) {
  sql <- aa_prepare_sql(conn, sql)

  n <- if (is.null(params)) {
    DBI::dbExecute(conn, sql)
  } else {
    DBI::dbExecute(conn, sql, params = params)
  }

  as.integer(n)
}

aa_write_state <- new.env(parent = emptyenv())

aa_conn_key <- function(conn) {
  slots <- methods::slotNames(conn)
  ptr <- slots[vapply(
    slots,
    function(s) typeof(methods::slot(conn, s)) == "externalptr",
    logical(1)
  )]
  if (length(ptr) > 0) format(methods::slot(conn, ptr[1])) else format(conn)
}

aa_write_section <- function(conn, fun) {
  key <- aa_conn_key(conn)
  depth <- if (exists(key, envir = aa_write_state, inherits = FALSE)) {
    get(key, envir = aa_write_state, inherits = FALSE)
  } else {
    0L
  }

  if (depth > 0L) {
    if (identical(aa_dialect(conn), "duckdb")) {
      assign(key, depth + 1L, envir = aa_write_state)
      on.exit(assign(key, depth, envir = aa_write_state), add = TRUE)
      result <- withVisible(fun())
      return(if (result$visible) result$value else invisible(result$value))
    }

    savepoint <- paste0("aa_write_", depth)
    DBI::dbExecute(conn, paste0("SAVEPOINT ", savepoint))
    assign(key, depth + 1L, envir = aa_write_state)
    ok <- FALSE

    on.exit(
      {
        assign(key, depth, envir = aa_write_state)
        if (ok) {
          DBI::dbExecute(conn, paste0("RELEASE SAVEPOINT ", savepoint))
        } else {
          try(
            DBI::dbExecute(conn, paste0("ROLLBACK TO SAVEPOINT ", savepoint)),
            silent = TRUE
          )
          try(
            DBI::dbExecute(conn, paste0("RELEASE SAVEPOINT ", savepoint)),
            silent = TRUE
          )
        }
      },
      add = TRUE
    )

    result <- withVisible(fun())
    ok <- TRUE
    return(if (result$visible) result$value else invisible(result$value))
  }

  dialect <- aa_dialect(conn)
  lock_name <- "appauth:write"
  ok <- FALSE
  started <- FALSE
  locked <- FALSE

  assign(key, 1L, envir = aa_write_state)
  on.exit(
    {
      if (depth == 0L) {
        rm(list = key, envir = aa_write_state)
      } else {
        assign(key, depth, envir = aa_write_state)
      }
      if (locked) {
        try(
          DBI::dbExecute(
            conn,
            "SELECT RELEASE_LOCK(?)",
            params = list(lock_name)
          ),
          silent = TRUE
        )
      }
      if (started) {
        if (ok) {
          if (identical(dialect, "sqlite")) {
            DBI::dbExecute(conn, "COMMIT")
          } else {
            DBI::dbCommit(conn)
          }
        } else {
          if (identical(dialect, "sqlite")) {
            DBI::dbExecute(conn, "ROLLBACK")
          } else {
            DBI::dbRollback(conn)
          }
        }
      }
    },
    add = TRUE
  )

  if (identical(dialect, "sqlite")) {
    DBI::dbExecute(conn, "BEGIN IMMEDIATE")
  } else {
    DBI::dbBegin(conn)
  }
  started <- TRUE

  if (identical(dialect, "mysql")) {
    acquired <- aa_query(
      conn,
      "SELECT GET_LOCK(?, 30) AS ok",
      params = list(lock_name)
    )$ok
    if (!isTRUE(acquired == 1)) {
      rlang::abort(
        "Could not acquire the appauth write lock.",
        class = "appauth_error_connection"
      )
    }
    locked <- TRUE
  } else if (identical(dialect, "postgres")) {
    aa_query(
      conn,
      "SELECT pg_advisory_xact_lock(hashtext(?))",
      params = list(lock_name)
    )
  }

  result <- withVisible(fun())
  ok <- TRUE

  if (result$visible) result$value else invisible(result$value)
}

# How many rows matched the update condition
#
# SQLite, DuckDB and PostgreSQL return the number of found rows, while MySQL
# returns only
# the number of changed ones: updating with the same value gives 0. For MySQL
# with a zero
# result the existence of the user is checked separately.
#
# @param conn Database connection.
# @param n The number of affected rows from `aa_execute()`.
# @param login The login the `users` update was for.
#
# @returns The number of matched rows (0 or 1).
# @noRd
aa_rows_matched <- function(conn, n, login) {
  if (n > 0 || !identical(aa_dialect(conn), "mysql")) {
    return(n)
  }

  as.integer(
    aa_query(
      conn,
      "SELECT COUNT(*) AS n FROM users WHERE login = ?",
      params = list(login)
    )$n
  )
}

# Table columns (in lower case)
#
# @param conn Database connection.
# @param table Table name.
#
# @returns A vector of column names.
# @noRd
aa_table_columns <- function(conn, table) {
  tolower(DBI::dbListFields(conn, table))
}

# Whether a uniqueness constraint is violated
#
# @param e An error caught on write.
#
# @returns `TRUE` or `FALSE`.
# @noRd
aa_is_unique_violation <- function(e) {
  grepl(
    "UNIQUE|Duplicate entry|duplicate key|Duplicate key",
    conditionMessage(e),
    ignore.case = FALSE
  )
}

# Order of users table rows "by insertion"
#
# @param conn Database connection.
#
# @returns An expression for `ORDER BY`.
# @noRd
aa_users_order <- function(conn) {
  if ("id" %in% aa_table_columns(conn, "users")) {
    "id"
  } else if (identical(aa_dialect(conn), "sqlite")) {
    "rowid"
  } else {
    "login"
  }
}

# Binary collation that does not ignore trailing spaces
#
# The usual `utf8mb4_bin` treats `"alsey"` and `"alsey "` as equal (PAD SPACE),
# while logins
# must be compared exactly. In MySQL 8 there is `utf8mb4_0900_bin` for this, in
# MariaDB
# `utf8mb4_nopad_bin`.
#
# @param conn Connection to MySQL / MariaDB.
#
# @returns The collation name.
# @noRd
aa_mysql_collation <- function(conn) {
  version <- DBI::dbGetQuery(conn, "SELECT VERSION() AS v")$v

  if (grepl("mariadb", version, ignore.case = TRUE)) {
    "utf8mb4_nopad_bin"
  } else {
    "utf8mb4_0900_bin"
  }
}

# Schema column types for a database
#
# Logins, roles and hashes are compared exactly (case-sensitively), so in
# MySQL,
# where comparison is case-insensitive by default, such columns are created
# with
# a binary collation. Time is stored as UTC text.
#
# @param conn Database connection.
#
# @returns A list: `key` (short text for logins, roles, hashes), `text`
#   (arbitrary text), `ts` (a time column) and `ts_now` (a time column
#   with the default value "now").
# @noRd
aa_col_types <- function(conn) {
  dialect <- aa_dialect(conn)

  key <- switch(
    dialect,
    sqlite = "TEXT",
    mysql = paste0(
      "VARCHAR(255) CHARACTER SET utf8mb4 COLLATE ",
      aa_mysql_collation(conn)
    ),
    "VARCHAR(255)"
  )

  ts <- if (dialect == "sqlite") "TEXT" else "VARCHAR(19)"

  now_default <- switch(
    dialect,
    sqlite = "DEFAULT (datetime('now'))",
    mysql = "DEFAULT (DATE_FORMAT(UTC_TIMESTAMP(), '%Y-%m-%d %H:%i:%s'))",
    postgres = "DEFAULT to_char(timezone('UTC', now()), 'YYYY-MM-DD HH24:MI:SS')",
    duckdb = "DEFAULT (substr(CAST(timezone('UTC', now()) AS VARCHAR), 1, 19))"
  )

  list(
    key = key,
    text = "TEXT",
    ts = ts,
    ts_now = paste(ts, now_default)
  )
}

# Definition of the `id` column with auto-increment
#
# For DuckDB it also creates the table sequence.
#
# @param conn Database connection.
# @param table Table name.
#
# @returns A string with the column definition for `CREATE TABLE`.
# @noRd
aa_pk_column <- function(conn, table) {
  switch(
    aa_dialect(conn),
    sqlite = "id INTEGER PRIMARY KEY AUTOINCREMENT",
    mysql = "id INT AUTO_INCREMENT PRIMARY KEY",
    postgres = "id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY",
    duckdb = {
      seq <- paste0("aa_seq_", table)
      DBI::dbExecute(conn, paste0("CREATE SEQUENCE IF NOT EXISTS ", seq))
      paste0("id INTEGER PRIMARY KEY DEFAULT nextval('", seq, "')")
    }
  )
}

# Create an index if it does not exist yet
#
# MySQL does not support `CREATE INDEX IF NOT EXISTS`, so the existence of the
# index
# is checked separately.
#
# @param conn Database connection.
# @param name Index name.
# @param table Table name.
# @param columns Index columns (a string, comma-separated).
# @param unique Make the index unique.
#
# @returns Invisibly `NULL`.
# @noRd
aa_create_index <- function(conn, name, table, columns, unique = FALSE) {
  kind <- if (unique) "UNIQUE INDEX" else "INDEX"

  if (identical(aa_dialect(conn), "mysql")) {
    exists <- aa_query(
      conn,
      "SELECT COUNT(*) AS n FROM information_schema.statistics
       WHERE table_schema = DATABASE() AND table_name = ? AND index_name = ?",
      params = list(table, name)
    )$n

    if (exists == 0) {
      DBI::dbExecute(
        conn,
        sprintf("CREATE %s %s ON %s (%s)", kind, name, table, columns)
      )
    }
  } else {
    DBI::dbExecute(
      conn,
      sprintf(
        "CREATE %s IF NOT EXISTS %s ON %s (%s)",
        kind,
        name,
        table,
        columns
      )
    )
  }

  invisible(NULL)
}

# Query "insert if such a row does not exist yet"
#
# @param conn Database connection.
# @param table Table name.
# @param columns Column names.
#
# @returns `INSERT` text with `?` placeholders.
# @noRd
aa_insert_ignore_sql <- function(conn, table, columns) {
  base <- sprintf(
    "INTO %s (%s) VALUES (%s)",
    table,
    paste(columns, collapse = ", "),
    paste(rep("?", length(columns)), collapse = ", ")
  )

  if (identical(aa_dialect(conn), "mysql")) {
    paste("INSERT IGNORE", base)
  } else {
    paste("INSERT", base, "ON CONFLICT DO NOTHING")
  }
}

# Explicit cast of a parameter to text
#
# PostgreSQL cannot determine the type of a parameter in a `SELECT` list
# without `INSERT`
# columns, so in queries like `INSERT ... SELECT ?` the parameter is cast
# explicitly. For other databases just `?` is returned.
#
# @param conn Database connection.
#
# @returns A query fragment.
# @noRd
aa_text_param <- function(conn) {
  if (identical(aa_dialect(conn), "postgres")) "CAST(? AS TEXT)" else "?"
}

# Lock for the duration of migrations
#
# If several app instances start simultaneously, only one should
# complete the schema. MySQL: a named lock per connection;
# PostgreSQL: an advisory lock inside the migration transaction (released
# with it). SQLite and DuckDB lock the file themselves.
#
# @param conn Database connection.
#
# @returns A function without arguments that releases the lock (does nothing
# for SQLite, DuckDB and
#   PostgreSQL).
# @noRd
aa_migration_lock <- function(conn) {
  dialect <- aa_dialect(conn)

  if (dialect == "mysql") {
    got <- aa_query(conn, "SELECT GET_LOCK('appauth_migrations', 60) AS ok")$ok

    if (!isTRUE(as.numeric(got) == 1)) {
      rlang::abort(
        "Could not obtain the lock for schema migrations.",
        class = "appauth_error_migration"
      )
    }

    return(function() {
      try(
        DBI::dbGetQuery(conn, "SELECT RELEASE_LOCK('appauth_migrations')"),
        silent = TRUE
      )
    })
  }

  if (dialect == "postgres") {
    DBI::dbGetQuery(conn, "SELECT pg_advisory_xact_lock(7272741)")
  }

  function() invisible(NULL)
}
