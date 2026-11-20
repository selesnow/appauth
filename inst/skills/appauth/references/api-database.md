# appauth reference: Database

Package version: 0.10.1. This file is generated automatically from the package help (`dev/skills/build_reference.R`) and must not be edited by hand.

Functions in this section: 
`aa_init_db()`, `aa_prepare_db()`, `aa_schema_version()`, `aa_cleanup()`, `aa_session_connection()`

## aa_init_db

```text
Create or update the authentication table schema

Description:

     Applies versioned migrations: creates missing tables and columns and records the
     applied versions in the service table 'appauth_migrations'. Existing data is not
     changed, a repeated run changes nothing. Old schemas are recognized too (for
     example, a 'users' table without an 'id' column or without 'blocked', a database
     without session and login attempt tables): what is missing is completed, users,
     passwords and tokens stay as they were.

Usage:

     aa_init_db(conn)
     
Arguments:

    conn: Database connection: SQLite, DuckDB, MySQL / MariaDB or PostgreSQL
          ('DBI::dbConnect()' with the RSQLite, duckdb, RMariaDB or RPostgres driver).

Details:

     Migrations run in a single transaction: on error the changes are rolled back. It is
     safe to call the function on every app start, including on live databases. For a
     start that must not stop the app on error, use 'aa_prepare_db()'.

Value:

     A list (invisibly): 'applied' (migration versions applied in this call), 'version'
     (the current schema version) and 'legacy' ('TRUE' if the 'users' table already
     existed before the package was connected).

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
Prepare the database on app start

Description:

     Calls 'aa_init_db()' and 'aa_cleanup()' and *never stops the app*: on error it
     writes a message to the app log and returns 'FALSE'. Meant to be called once at app
     start. Without the prepared tables, protection against guessing and locks will not
     work, while password sign-in will keep working.

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

     An integer: the number of the last applied migration or '0' if the schema has not
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

     Deletes login attempt records older than 'attempts_retention_hours' hours, as well
     as expired and revoked auto-login tokens older than 'token_retention_days' days, as
     well as used and expired password recovery tokens and Google sign-in parameters
     older than a day. Active tokens and fresh attempts are not touched. Call it after
     'aa_init_db()'.

Usage:

     aa_cleanup(conn, settings = aa_settings())
     
Arguments:

    conn: Database connection: SQLite, DuckDB, MySQL / MariaDB or PostgreSQL
          ('DBI::dbConnect()' with the RSQLite, duckdb, RMariaDB or RPostgres driver).

settings: Settings, the result of 'aa_settings()'.

Value:

     A list (invisibly): 'login_attempts' (the number of deleted login attempts),
     'auth_sessions' (the number of deleted tokens), 'password_resets' (the number of
     deleted password recovery tokens) and 'oauth_states' (the number of deleted sign-in
     parameters for Google).

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
Database connection closed together with the session

Description:

     Opens a database connection and immediately registers its closing when the Shiny
     session ends. Without this the connection stays open until the R process stops and
     holds the database file (SQLite, DuckDB): on Windows such a file cannot be renamed
     or deleted, and server databases (MySQL, PostgreSQL) are left with extra
     connections.

Usage:

     aa_session_connection(
       db_path = NULL,
       session = shiny::getDefaultReactiveDomain(),
       prepare = FALSE,
       settings = aa_settings(),
       connect = NULL
     )
     
Arguments:

 db_path: Path to the SQLite database file. Not needed if 'connect' is set.

 session: Shiny session. The current one by default, so the function must be called
          inside 'server'.

 prepare: Prepare the database schema ('aa_prepare_db()') right after connecting.

settings: Settings, a result of 'aa_settings()', needed for 'prepare'.

 connect: A function without arguments that returns a database connection (SQLite,
          DuckDB, MySQL / MariaDB or PostgreSQL), or 'NULL' for a SQLite file.

Details:

     By default a SQLite file is opened. For another database pass 'connect': a function
     without arguments that returns a DBI connection.

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

