# Database connection closed together with the session

Opens a database connection and immediately registers its closing when
the Shiny session ends. Without this the connection stays open until the
R process stops and holds the database file (SQLite, DuckDB): on Windows
such a file cannot be renamed or deleted, and server databases (MySQL,
PostgreSQL) are left with extra connections.

## Usage

``` r
aa_session_connection(
  db_path = NULL,
  session = shiny::getDefaultReactiveDomain(),
  prepare = FALSE,
  settings = aa_settings(),
  connect = NULL
)
```

## Arguments

- db_path:

  Path to the SQLite database file. Not needed if `connect` is set.

- session:

  Shiny session. The current one by default, so the function must be
  called inside `server`.

- prepare:

  Prepare the database schema
  ([`aa_prepare_db()`](https://alexey-seleznev.pro/appauth/reference/aa_prepare_db.md))
  right after connecting.

- settings:

  Settings, a result of
  [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md),
  needed for `prepare`.

- connect:

  A function without arguments that returns a database connection
  (SQLite, DuckDB, MySQL / MariaDB or PostgreSQL), or `NULL` for a
  SQLite file.

## Value

A database connection.

## Details

By default a SQLite file is opened. For another database pass `connect`:
a function without arguments that returns a DBI connection.

## Examples

``` r
if (FALSE) { # \dontrun{
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
} # }
```
