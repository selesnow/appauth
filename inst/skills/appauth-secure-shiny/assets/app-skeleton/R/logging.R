# App action and session log (the tables belong to the app, not to the appauth package).
# The toggles in config.yaml (logging section) switch writing on and off.

ensure_log_tables <- function(con) {
  DBI::dbExecute(con, "CREATE TABLE IF NOT EXISTS action_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT, datetime TEXT, func_name TEXT, user TEXT, session_id TEXT, value TEXT)")
  DBI::dbExecute(con, "CREATE TABLE IF NOT EXISTS session_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT, datetime TEXT, session_id TEXT, user TEXT, action TEXT)")
  invisible(TRUE)
}

write_action_log <- function(func, user, session_id = "x0", value = NULL) {
  if (!isTRUE(conf$logging$action_log)) return(invisible(NULL))
  con <- DBI::dbConnect(RSQLite::SQLite(), conf$database_settings$app_data_base)
  on.exit(DBI::dbDisconnect(con))
  DBI::dbExecute(
    con, "INSERT INTO action_log (datetime, func_name, user, session_id, value) VALUES (?, ?, ?, ?, ?)",
    params = list(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), func, user, session_id, value %||% NA_character_)
  )
  invisible(NULL)
}

session_log <- function(session_id, user, action = "start") {
  if (!isTRUE(conf$logging$session_log)) return(invisible(NULL))
  con <- DBI::dbConnect(RSQLite::SQLite(), conf$database_settings$app_data_base)
  on.exit(DBI::dbDisconnect(con))
  DBI::dbExecute(
    con, "INSERT INTO session_log (datetime, session_id, user, action) VALUES (?, ?, ?, ?)",
    params = list(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), session_id, user, action)
  )
  invisible(NULL)
}
