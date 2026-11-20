# config.yaml is specific to every copy of the app (dev, prod) and is not kept in git (add it to .gitignore).
# If the file does not exist it is created from the defaults; if it exists, only MISSING settings
# are APPENDED to it (new permissions, new sections from a newer app version),
# existing values are not changed.

default_config <- function() {
  list(
    database_settings = list(app_data_base = Sys.getenv("APP_DB", "app.db")),
    logging = list(session_log = TRUE, action_log = TRUE),
    # authentication settings (appauth package, see ?aa_settings), unset ones are taken from the package
    security = list(
      max_failed_logins = 5, # failures before a login is locked
      lockout_minutes = 15, # counting window and lockout duration, minutes
      max_failed_logins_per_minute = 30, # global limit of failures across all logins
      must_change_default = TRUE # a password set by the administrator is temporary by default
    ),
    # permission matrix: permission -> roles (permission names are arbitrary but must match the code)
    access_matrix = list(
      "Tasks" = c("admin", "user", "viewer"),
      "Run" = c("admin", "user"),
      "Access" = "admin"
    )
  )
}

merge_missing_config <- function(current, defaults) {
  for (key in names(defaults)) {
    if (is.null(current[[key]])) {
      current[[key]] <- defaults[[key]]
    } else if (
      is.list(current[[key]]) &&
        !is.null(names(current[[key]])) &&
        is.list(defaults[[key]]) &&
        !is.null(names(defaults[[key]]))
    ) {
      current[[key]] <- merge_missing_config(current[[key]], defaults[[key]])
    }
  }
  current
}

ensure_config <- function(path = "config.yaml") {
  defaults <- default_config()

  if (!file.exists(path)) {
    yaml::write_yaml(defaults, path, fileEncoding = "UTF-8")
    message("Created ", path, " from the defaults")
    return(defaults)
  }

  current <- yaml::read_yaml(path)
  merged <- merge_missing_config(current, defaults)
  if (!identical(current, merged)) {
    yaml::write_yaml(merged, path, fileEncoding = "UTF-8")
    message("Missing settings were appended to ", path)
  }
  merged
}
