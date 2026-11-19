# appauth reference: Database

Reference built from appauth 0.8.0. Generated automatically from the package help pages; do not edit by hand.

Functions in this section:
`aa_init_db()`, `aa_prepare_db()`, `aa_schema_version()`, `aa_cleanup()`, `aa_session_connection()`

## aa_init_db

```text
Create or upgrade the authentication table schema

Description:

     Applies versioned migrations: creates missing tables and columns and records
     the applied versions in the 'appauth_migrations' service table. Existing data is
     not changed, and running it again changes nothing. Legacy schemas are also
     recognised (for example, a 'users' table without an 'id' column or without
     'blocked', or a database without session and login-attempt tables): whatever is
     missing is added, while users, passwords and tokens stay as they were.

Usage:

     aa_init_db(conn)
     
Arguments:

    conn: Database connection: SQLite, DuckDB, MySQL / MariaDB or PostgreSQL
          ('DBI::dbConnect()' with the RSQLite, duckdb, RMariaDB or RPostgres driver).

Details:

     Migrations run in a single transaction: on error the changes are rolled back. The
     function is safe to call on every app start, including on live databases.
     For a start-up call that must not stop the app on error, use
     'aa_prepare_db()'.

Value:

     A list (invisibly): 'applied' (migration versions applied in this call), 'version'
     (current schema version) and 'legacy' ('TRUE' if the 'users' table already existed
     before the package was connected).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_schema_version(conn)
       DBI::dbDisconnect(conn)
     }
```

## aa_prepare_db

```text
Prepare the database at app start

Description:

     Calls 'aa_init_db()' and 'aa_cleanup()' and *never stops the app*: on error it
     writes a message to the app log and returns 'FALSE'. Intended to be called once
     at app start. Without the prepared tables, brute-force protection and lockouts
     will not work, while password login will keep working.

Usage:

     aa_prepare_db(conn, settings = aa_settings())
     
Arguments:

    conn: Database connection: SQLite, DuckDB, MySQL / MariaDB or PostgreSQL
          ('DBI::dbConnect()' with the RSQLite, duckdb, RMariaDB or RPostgres driver).

settings: Settings, the result of 'aa_settings()'.

Value:

     'TRUE' if the schema is prepared, otherwise 'FALSE' (invisibly).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_prepare_db(conn, aa_settings())
       DBI::dbDisconnect(conn)
     }
```

## aa_schema_version

```text
Current version of the authentication table schema

Description:

     Current version of the authentication table schema

Usage:

     aa_schema_version(conn)
     
Arguments:

    conn: Database connection: SQLite, DuckDB, MySQL / MariaDB or PostgreSQL
          ('DBI::dbConnect()' with the RSQLite, duckdb, RMariaDB or RPostgres driver).

Value:

     An integer: the number of the last applied migration, or '0' if the schema has not
     been created by the package yet.

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_schema_version(conn)
       aa_init_db(conn)
       aa_schema_version(conn)
       DBI::dbDisconnect(conn)
     }
```

## aa_cleanup

```text
Delete stale authentication data

Description:

     Deletes login-attempt records older than 'attempts_retention_hours' hours, expired
     and revoked auto-login tokens older than 'token_retention_days' days, used and
     expired password-reset tokens, and Google sign-in parameters older than one day.
     Active tokens and recent attempts are not touched. Must be called after
     'aa_init_db()'.

Usage:

     aa_cleanup(conn, settings = aa_settings())
     
Arguments:

    conn: Database connection: SQLite, DuckDB, MySQL / MariaDB or PostgreSQL
          ('DBI::dbConnect()' with the RSQLite, duckdb, RMariaDB or RPostgres driver).

settings: Settings, the result of 'aa_settings()'.

Value:

     A list (invisibly): 'login_attempts' (number of deleted login attempts),
     'auth_sessions' (number of deleted tokens), 'password_resets' (number of deleted
     password-reset tokens) and 'oauth_states' (number of deleted Google sign-in
     parameters).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_cleanup(conn)
       DBI::dbDisconnect(conn)
     }
```

## aa_session_connection

```text
Database connection that is closed together with the session

Description:

     Opens a database connection and immediately registers its closing when the Shiny
     session ends. Without this, the connection stays open until the R process stops
     and holds the database file (SQLite, DuckDB): on Windows such a file cannot be
     renamed or deleted, and with server databases (MySQL, PostgreSQL) extra
     connections are left behind.

Usage:

     aa_session_connection(
       db_path = NULL,
       session = shiny::getDefaultReactiveDomain(),
       prepare = FALSE,
       settings = aa_settings(),
       connect = NULL
     )
     
Arguments:

 db_path: Path to the SQLite database file. Not needed if 'connect' is given.

 session: Shiny session. The current one by default, so the function must be called
          inside 'server'.

 prepare: Prepare the database schema ('aa_prepare_db()') right after connecting.

settings: Settings, the result of 'aa_settings()', needed for 'prepare'.

 connect: A function with no arguments that returns a database connection (SQLite,
          DuckDB, MySQL / MariaDB or PostgreSQL), or 'NULL' for a SQLite file.

Details:

     A SQLite file is opened by default. For another database, pass 'connect': a
     function with no arguments that returns a DBI connection.

Value:

     A database connection.

Examples:

     ## Not run:
     
     server <- function(input, output, session) {
       # SQLite (default)
       conn <- aa_session_connection("app.db", prepare = TRUE)
     
       # MySQL / MariaDB
       conn <- aa_session_connection(
         prepare = TRUE,
         connect = function() DBI::dbConnect(
           RMariaDB::MariaDB(), host = "db.example.com", dbname = "app",
           user = "app", password = Sys.getenv("APP_DB_PASSWORD")
         )
       )
     
       auth <- aa_auth_server("auth", conn)
     }
     ## End(Not run)
```

