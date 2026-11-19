# Recipe: another database instead of SQLite

Since `appauth` 0.8.0 the package works with SQLite (the default), DuckDB, MySQL / MariaDB and PostgreSQL. It is needed if the app already has a database server or a SQLite file is inconvenient (several app instances, backups with database tools).

## Which database to choose

| Database | When it fits | Driver |
| --- | --- | --- |
| SQLite | one app, one server, the default | `RSQLite` |
| PostgreSQL | several app instances, a managed cloud database | `RPostgres` |
| MySQL / MariaDB | the project already has MySQL | `RMariaDB` |
| DuckDB | the app is in a single R process, a file like SQLite | `duckdb` |

**BigQuery and other analytical warehouses do not fit**: they have no unique constraints and atomic updates, which one-time tokens (password reset, sign-in with Google, 2FA backup codes) and the protection of the last administrator rely on. For the cloud, use managed PostgreSQL or MySQL.

## Connecting

Create a separate (empty) schema for the authentication tables: the package creates seven tables itself. The database user needs the privileges `CREATE`, `ALTER`, `INDEX`, `SELECT`, `INSERT`, `UPDATE`, `DELETE`. The database password comes only from environment variables (`.Renviron`, service secrets), not from code and not from `config.yaml` in git.

```r
server <- function(input, output, session) {
  conn <- aa_session_connection(
    prepare = TRUE, settings = auth_settings,
    connect = function() DBI::dbConnect(
      RPostgres::Postgres(),                  # or RMariaDB::MariaDB(), duckdb::duckdb(dbdir = "app.duckdb")
      host = Sys.getenv("APP_DB_HOST"), port = 5432, dbname = "app_auth",
      user = Sys.getenv("APP_DB_USER"), password = Sys.getenv("APP_DB_PASSWORD")
    )
  )
  auth <- aa_auth_server("auth", conn, auth_settings, on_event = log_auth_event)
  aa_session_guard(auth, conn, auth_settings)
}
```

`aa_session_connection()` closes the connection together with the session (otherwise connections pile up on a server database), and `prepare = TRUE` creates and completes the schema. The rest of the app code, modules and permissions do not change.

It is convenient to prepare the schema once at process start: in MySQL and PostgreSQL migrations run under a lock, so starting several instances simultaneously is safe.

## What differs from SQLite

* **Time** is stored as UTC text (`YYYY-MM-DD HH:MM:SS`) and computed in R. In your own queries and tests do not use `datetime('now')` and other SQLite functions: pass the time as a parameter.
* **Placeholders:** `RPostgres` accepts only `$1, $2`, the other drivers `?`. For the package's tables you need no SQL of your own, the package has functions; for your own tables, take this into account.
* **MySQL:** logins, roles and hashes are in columns with a binary collation that does not ignore trailing spaces (`utf8mb4_0900_bin`, in MariaDB `utf8mb4_nopad_bin`), so that `Alice`, `alice` and `alice ` are different logins. A `users` table created manually with an ordinary collation compares case-insensitively: recreate it through `aa_init_db()` on an empty schema and migrate the users with package functions. DDL in MySQL is not rolled back: if a migration is interrupted, running it again completes the schema.
* **DuckDB:** the file is opened by one process; several R processes (or parallel workers) will get a locking error.
* **Old schemas and plain-text passwords:** completing legacy schemas and `aa_migrate_plaintext_passwords()` (which works on a file) are for SQLite only. To move an app to another database, create the package tables on an empty schema and migrate users with `aa_create_user()` (for password hashes, moving data with an SQL query is acceptable only if the hashes are already `$7$...`).
* An unsupported database raises an error of class `appauth_error_connection`.

## Tests

It is better to run the app's tests on the same database as in production: an empty test schema whose tables can be dropped. An example of running the package's own test suite on the desired database: `Rscript dev/run-tests-db.R mysql|postgres|duckdb|sqlite` in the `appauth` sources (the script is described in its header).

```r
# set time in tests in R, not with SQLite functions
five_min_ago <- format(Sys.time() - 300, "%Y-%m-%d %H:%M:%S", tz = "UTC")
```

## Audit and checklist

* The database password is not in the repository and not in `config.yaml` under git.
* The database user has only the needed privileges, the schema is separate.
* The connection is opened through `aa_session_connection()` (or closed in `onSessionEnded`).
* The schema is created before the first user (`prepare = TRUE` or `aa_prepare_db()` at start).
* Backups and permissions on the `users` and `auth_sessions` tables: they hold password and token hashes.
