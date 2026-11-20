# appauth glue for Reports portal.
# This file is sourced into the GLOBAL environment by app.R, so `auth_settings` must be created
# globally in app.R (auth_settings <<- ...): runApp() loads app.R into its own environment.

APP_PERMISSIONS <- c("reports", "export")

build_auth_settings <- function() {
  aa_settings(
    roles = c("owner", "editor", "viewer"),
    admin_role = "owner",
    must_change_default = FALSE, # password set by the owner is permanent
    texts = aa_texts("en", login_title = "Reports portal")
  )
}

app_db_path <- function() {
  Sys.getenv("REPORTS_PORTAL_DB", unset = "app.db")
}

# per-user permissions table lives next to the appauth tables
ensure_permissions_table <- function(con) {
  DBI::dbExecute(
    con,
    "
    CREATE TABLE IF NOT EXISTS user_permissions (
      login      TEXT NOT NULL,
      permission TEXT NOT NULL,
      PRIMARY KEY (login, permission)
    )"
  )
  invisible(TRUE)
}

prepare_app_db <- function(path, settings) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con))
  aa_prepare_db(con, settings)
  ensure_permissions_table(con)
}

user_permissions_of <- function(conn, login) {
  DBI::dbGetQuery(
    conn,
    "SELECT permission FROM user_permissions WHERE login = ?",
    params = list(login)
  )$permission
}

# permission source for appauth: function(user) -> character(); owner gets everything
make_permission_provider <- function(conn, settings) {
  function(user) {
    if (identical(user$role, settings$admin_role)) {
      return(c(APP_PERMISSIONS, "users"))
    }
    if (is.null(user$login) || !nzchar(user$login)) {
      return(character(0))
    }
    intersect(user_permissions_of(conn, user$login), APP_PERMISSIONS)
  }
}

# replace the permission set of a user (the caller must already have checked that it is the owner)
save_user_permissions <- function(conn, login, permissions) {
  stopifnot(is.character(login), length(login) == 1, nzchar(login))
  if (is.null(aa_get_user(conn, login))) {
    stop("unknown user", call. = FALSE)
  }
  permissions <- intersect(as.character(permissions), APP_PERMISSIONS)
  DBI::dbWithTransaction(conn, {
    DBI::dbExecute(
      conn,
      "DELETE FROM user_permissions WHERE login = ?",
      params = list(login)
    )
    for (p in permissions) {
      DBI::dbExecute(
        conn,
        "INSERT INTO user_permissions (login, permission) VALUES (?, ?)",
        params = list(login, p)
      )
    }
  })
  invisible(permissions)
}

# --- slot of the user card: block "Permissions" (the owner grants rights with checkboxes) ---------------
make_card_ui <- function(conn) {
  function(login, ns) {
    div(
      class = "aa-card-section",
      h5("Permissions"),
      checkboxGroupInput(
        ns("permissions"),
        NULL,
        choices = APP_PERMISSIONS,
        selected = user_permissions_of(conn, login)
      ),
      actionButton(
        ns("save_permissions"),
        "Save permissions",
        class = "btn btn-primary btn-sm"
      )
    )
  }
}

# The slot is application code, so the role check lives in its own handler (the package does not do it for us).
make_card_server <- function(conn, auth) {
  function(input, output, session, login) {
    observeEvent(input$save_permissions, {
      user <- isolate(auth$user())
      req(identical(user$role, auth_settings$admin_role), login()) # only the owner, role from server state
      target <- login()
      ok <- tryCatch(
        {
          save_user_permissions(conn, target, input$permissions)
          TRUE
        },
        error = function(e) FALSE
      )
      if (ok) {
        log_auth_event("permissions_changed", user$login, session$token, target)
        showNotification(
          paste("Permissions saved for", target),
          type = "message"
        )
      } else {
        showNotification("Could not save permissions", type = "error")
      }
    })
  }
}

# single place for events: console audit log (no secrets are ever passed by the package)
log_auth_event <- function(event, user, session_id, value) {
  message(sprintf("[audit] %s user=%s value=%s", event, user, value))
  invisible(NULL)
}
