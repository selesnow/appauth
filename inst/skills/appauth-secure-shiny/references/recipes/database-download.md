# Recipe: downloading the database from the UI is dangerous

Sometimes a "Download database" button is added to an app (a `downloadHandler` serving the `app.db` file). This is a direct leak: the file holds the authentication tables.

## What is inside the file

* `users`: logins, roles, password hashes. A scrypt hash is strong, but it can be brute-forced offline indefinitely with no lockout, and passwords that have not yet been migrated are stored in plain text.
* `auth_sessions`: token hashes, expiry times and revocation flags.
* `login_attempts`: who tried to guess passwords, and when.
* App logs (`action_log`, `session_log`) with user actions.

Whoever downloads the file gets all of this data and can guess passwords without limits. The package's lockout only protects against online guessing through the login form.

## Rule

The application's database file is NOT served for download as a whole. If you need data for analysis, serve specific tables that contain no authentication data, as CSV or as a separate database built on the fly:

```r
output$download_data <- downloadHandler(
  filename = function() paste0("report_", Sys.Date(), ".csv"),
  content = function(file) {
    aa_require(auth, "Export", provider, on_event = log_event)   # the permission is checked inside the handler itself
    data <- DBI::dbGetQuery(conn, "SELECT task, status, started FROM task_log")   # only the needed tables and columns
    write.csv(data, file, row.names = FALSE, fileEncoding = "UTF-8")
  }
)
```

If you really need a copy of the whole database (a backup), make it on the server with administrator tools rather than through the UI; if needed, copy the database without the authentication tables:

```r
# a copy without the authentication tables (for debugging / handing over data)
src <- DBI::dbConnect(RSQLite::SQLite(), "app.db")
dst <- DBI::dbConnect(RSQLite::SQLite(), tmp_path)
for (t in setdiff(DBI::dbListTables(src), c("users", "auth_sessions", "login_attempts", "appauth_migrations")))
  DBI::dbWriteTable(dst, t, DBI::dbReadTable(src, t))
```

## Downloads in general

* A `downloadHandler` is always guarded by a permission (`aa_require` inside `content`), like any action.
* Do not pass paths from `input` into `filename` and `content` (recipes/handler-guards.md, the section on paths).
* Do not serve logs with logins and events to all roles: that is also data about users.

## Verification

The audit finds a `downloadHandler` that serves a `.db`/`.sqlite` file: a `DB_DOWNLOAD` finding of "critical" level (`Rscript <skill>/scripts/audit_shiny_app.R <folder>`).
