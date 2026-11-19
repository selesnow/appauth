#' Database connection closed together with the session
#'
#' Opens a database connection and immediately registers its closing when the
#' Shiny session ends. Without this the connection stays open until the R
#' process stops and holds the database file (SQLite, DuckDB): on Windows such a
#' file cannot be renamed or deleted, and server databases (MySQL, PostgreSQL)
#' are left with extra connections.
#'
#' By default a SQLite file is opened. For another database pass `connect`: a
#' function without arguments that returns a DBI connection.
#'
#' @param db_path Path to the SQLite database file. Not needed if `connect` is
#'   set.
#' @param session Shiny session. The current one by default, so the function
#'   must be called inside `server`.
#' @param prepare Prepare the database schema ([aa_prepare_db()]) right after
#'   connecting.
#' @param settings Settings, a result of [aa_settings()], needed for `prepare`.
#' @param connect A function without arguments that returns a database
#'   connection (SQLite, DuckDB, MySQL / MariaDB or PostgreSQL), or `NULL` for
#'   a SQLite file.
#'
#' @returns A database connection.
#' @export
#'
#' @examples
#' \dontrun{
#' server <- function(input, output, session) {
#'   # SQLite (default)
#'   conn <- aa_session_connection("app.db", prepare = TRUE)
#'
#'   # MySQL / MariaDB
#'   conn <- aa_session_connection(
#'     prepare = TRUE,
#'     connect = function() DBI::dbConnect(
#'       RMariaDB::MariaDB(), host = "db.example.com", dbname = "app",
#'       user = "app", password = Sys.getenv("APP_DB_PASSWORD")
#'     )
#'   )
#'
#'   auth <- aa_auth_server("auth", conn)
#' }
#' }
aa_session_connection <- function(db_path = NULL, session = shiny::getDefaultReactiveDomain(),
                                  prepare = FALSE, settings = aa_settings(), connect = NULL) {
  if (is.null(connect) && !aa_is_string(db_path)) {
    rlang::abort(
      "`db_path` must be a path to the database file (or pass `connect`).",
      class = "appauth_error_connection"
    )
  }

  if (!is.null(connect) && !is.function(connect)) {
    rlang::abort(
      "`connect` must be a function without arguments that returns a connection.",
      class = "appauth_error_connection"
    )
  }

  if (is.null(session) || !is.function(session$onSessionEnded)) {
    rlang::abort(
      "A Shiny session is required: call the function inside `server` or pass `session`.",
      class = "appauth_error_connection"
    )
  }

  if (is.null(connect)) {
    if (!requireNamespace("RSQLite", quietly = TRUE)) {
      rlang::abort("The RSQLite package is required to work with the database.", class = "appauth_error_connection")
    }

    conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  } else {
    conn <- connect()
  }

  aa_check_conn(conn)

  session$onSessionEnded(function() {
    try(DBI::dbDisconnect(conn), silent = TRUE)
  })

  if (isTRUE(prepare)) {
    aa_prepare_db(conn, settings)
  }

  conn
}

#' Forcibly end invalid sessions
#'
#' Every `session_check_seconds` (from [aa_settings()]) checks the open session
#' ([aa_user_session_valid()]). If the user has been blocked, deleted or had
#' their role changed, the session is ended through `auth$logout()`: the
#' `on_event` hook receives `session_forced_logout` with the reason, and tokens
#' are revoked. Thanks to this, blocking and role downgrades take effect within
#' the check interval rather than at the next sign-in.
#'
#' If the database cannot be read, the session is not ended.
#'
#' The session token (`auth$token()`) is checked too: a password reset of a
#' user or "end all sessions" also end open sessions. Every `cleanup_minutes`
#' the guard also deletes outdated sign-in attempts and tokens
#' ([aa_cleanup()]).
#'
#' @param auth A result of [aa_auth_server()].
#' @param cleanup_minutes How often to clean up outdated records, in minutes.
#' @param conn Database connection.
#' @param settings Settings, a result of [aa_settings()].
#' @param reload Reload the page after sign-out so that the modules of the
#'   previous user disappear. `TRUE` is recommended.
#'
#' @returns Invisibly a Shiny observer (it can be stopped with `$destroy()`).
#' @export
#'
#' @examples
#' \dontrun{
#' auth <- aa_auth_server("auth", conn)
#' aa_session_guard(auth, conn)
#' }
aa_session_guard <- function(auth, conn, settings = aa_settings(), reload = TRUE,
                             cleanup_minutes = 60) {
  aa_check_conn(conn)

  interval <- max(1, settings$session_check_seconds) * 1000
  last_cleanup <- Sys.time()

  invisible(shiny::observe({
    shiny::req(auth$logged_in())
    shiny::invalidateLater(interval)

    usr <- shiny::isolate(auth$user())
    token <- if (is.function(auth$token)) auth$token() else NULL
    check <- aa_user_session_valid(conn, usr$login, usr$role, token)

    if (!check$valid) {
      message("appauth: session closed: ", usr$login, " (", check$reason, ")")
      auth$logout(reason = check$reason, reload = reload)
    }

    # the service runs for months: clean outdated attempts and tokens as we go
    if (as.numeric(difftime(Sys.time(), last_cleanup, units = "mins")) >= cleanup_minutes) {
      last_cleanup <<- Sys.time()
      try(aa_cleanup(conn, settings), silent = TRUE)
    }
  }))
}

#' Attach a module server only if the permission is granted
#'
#' Calls `server()` once per session, when the signed-in user gets the
#' `permission` permission. For other users the module server is not registered
#' at all, and permissions still have to be checked inside handlers
#' ([aa_require()]): registration protects against unnecessary work, not
#' against forged requests.
#'
#' Registered modules cannot be removed from a session, so on sign-out use
#' `auth$logout(reload = TRUE)`: the page reloads and the modules of the
#' previous user disappear.
#'
#' @param auth A result of [aa_auth_server()].
#' @param permission Permission name.
#' @param provider Permission source, see [aa_can()].
#' @param server A function without arguments that registers the module, for
#'   example `function() mod_tasks_server("tasks")`.
#'
#' @returns Invisibly a Shiny observer.
#' @export
#'
#' @examples
#' \dontrun{
#' provider <- aa_permissions_from_matrix(conf$access_management)
#' aa_register_module(auth, "Tasks", provider, function() mod_tasks_server("tasks"))
#' }
aa_register_module <- function(auth, permission, provider, server) {
  if (!is.function(server)) {
    rlang::abort("`server` must be a function without arguments.", class = "appauth_error_permissions")
  }

  started <- FALSE

  invisible(shiny::observe({
    user <- auth$user()

    if (!started && !is.null(user) && aa_can(user, permission, provider)) {
      started <<- TRUE
      shiny::isolate(server())
    }
  }))
}
