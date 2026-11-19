# Recipe: database connection and closing it

## The problem

If an app opens a database connection per session and never closes it, the connection stays open until the R process stops. On Windows the SQLite file is then locked: it cannot be renamed, deleted or copied while the process is alive. In production, open connections pile up with every browser session.

## Solution: `aa_session_connection()`

```r
server <- function(input, output, session) {
  conn <- aa_session_connection(conf$database_settings$app_data_base, prepare = TRUE, settings = auth_settings)
  auth <- aa_auth_server("auth", conn, auth_settings, on_event = log_auth_event)
  ...
}
```

The function opens a connection and registers its closing when the session ends. With `prepare = TRUE` it also completes the database schema (`aa_prepare_db()`: migrations and cleanup of stale records) without stopping the app on error.

It is convenient to also prepare the database once at process start (before the first session), so migrations finish before the first user arrives:

```r
local({
  con <- DBI::dbConnect(RSQLite::SQLite(), conf$database_settings$app_data_base)
  on.exit(DBI::dbDisconnect(con))
  aa_prepare_db(con, auth_settings)
})
```

## If you open the connection yourself

Close it when the session ends:

```r
conn <- DBI::dbConnect(RSQLite::SQLite(), path)
session$onSessionEnded(function() try(DBI::dbDisconnect(conn), silent = TRUE))
```

In functions that open a short-lived connection (writing to a log), use `on.exit(DBI::dbDisconnect(con))` right after `dbConnect`.

## Connections in observers

Do not call `dbConnect` inside `observe`/`renderUI` blocks that fire often: a connection would be opened on every run. Use the shared session connection (`conn`) or open and close within a single function.

## Server databases (MySQL, PostgreSQL) and DuckDB

For a non-SQLite database pass a `connect` function to `aa_session_connection()` (see `recipes/other-databases.md`): the connection will likewise be closed together with the session. With server databases an unclosed connection is an extra connection on the server that accumulates with every session and hits the connection limit.

## Other databases of the app

Close connections to other databases (for example, a bot database on a statistics tab) the same way: `onSessionEnded` or `on.exit`.

## Verification

Test: after all sessions are closed, the connection is invalid (`DBI::dbIsValid(conn)` is `FALSE`), and the database file can be renamed and renamed back:

```r
chk("connection closed after the session", !DBI::dbIsValid(app_con_ref))
moved <- file.rename("app.db", "app_moved.db")
chk("database file is not locked", isTRUE(moved)); file.rename("app_moved.db", "app.db")
```

The audit finds suspicious places: `Rscript <skill>/scripts/audit_shiny_app.R <folder>` (finding `DB_NOT_CLOSED`).

## Windows and cloud drives

Do not keep the database file in a folder synchronised by a cloud drive: synchronisation also locks the file. Put the database in the app's local folder and include it in backups separately.
