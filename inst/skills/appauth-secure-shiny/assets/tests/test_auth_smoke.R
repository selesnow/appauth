# End-to-end test of an app with appauth authentication (template from the appauth-secure-shiny skill).
#
# app.R runs in a TEMPORARY copy of the project, the working app.db and config.yaml are not touched.
# The app is loaded into ITS OWN environment, as runApp() does: when loaded into the global
# environment, errors of the kind "a function from R/ does not see a variable from app.R" disappear (this is how the
# "Access" tab once turned out empty although the tests were green).
#
# Run from the project root: Rscript tests/test_auth_smoke.R
# Adapting to the app: the list of files and folders for the copy (below), module names and permissions.

proj <- normalizePath(getwd(), winslash = "/")
libs <- .libPaths() # project libraries (renv) are needed in the temporary copy too
source(file.path(proj, "tests/helper.R"))

tmp <- file.path(Sys.getenv("TEMP", tempdir()), "auth_smoke_proj")
unlink(tmp, recursive = TRUE)
dir.create(tmp)
for (f in c("app.R", "create_config.R", "create_db.R")) {
  if (file.exists(file.path(proj, f))) file.copy(file.path(proj, f), tmp)
}
for (d in c("R", "modules", "www")) {
  if (dir.exists(file.path(proj, d))) {
    invisible(file.copy(file.path(proj, d), tmp, recursive = TRUE))
  }
}
setwd(tmp)
.libPaths(libs)
suppressMessages({
  library(shiny)
  library(DBI)
  library(appauth)
})

chk(
  "temporary copy: neither app.db nor config.yaml exists yet",
  !file.exists("app.db") && !file.exists("config.yaml")
)

# app.R without the sink block (if there is one) and without running; replace heavy background processes with stubs here
txt <- readLines("app.R", encoding = "UTF-8")
app_env <- new.env(parent = globalenv())
app_obj <- suppressWarnings(suppressMessages(eval(
  parse(text = txt),
  envir = app_env
))) # do not print: print() launches the app
server <- app_env$server
chk("app.R loaded, the server function found", is.function(server))
chk("first run: config.yaml created by the app", file.exists("config.yaml"))
cfg <- yaml::read_yaml("config.yaml")
chk(
  "config.yaml contains the security section and the permission matrix",
  !is.null(cfg$security) && !is.null(cfg$access_matrix)
)

con <- dbConnect(RSQLite::SQLite(), cfg$database_settings$app_data_base)
chk(
  "the new database has the auth tables and the blocked, must_change columns",
  all(
    c("users", "auth_sessions", "login_attempts", "appauth_migrations") %in%
      dbListTables(con)
  ) &&
    all(
      c("blocked", "must_change") %in%
        dbGetQuery(con, "SELECT name FROM pragma_table_info('users')")$name
    )
)
chk(
  "the new database has no users (the administrator is created at first start)",
  dbGetQuery(con, "SELECT COUNT(*) n FROM users")$n == 0
)

# 1. first administrator and the administrator tab
testServer(server, {
  chk(
    "empty database: administrator creation on screen",
    grepl("setup_btn", as.character(output$`auth-form`$html), fixed = TRUE)
  )
  session$setInputs(
    `auth-setup_login` = "boss",
    `auth-setup_password` = "bosspass1",
    `auth-setup_confirm` = "bosspass1",
    `auth-setup_btn` = 1
  )
  chk(
    "first administrator created and signed in",
    auth$logged_in() && auth$role() == "admin"
  )
  session$flushReact()
  access_html <- tryCatch(
    as.character(output$`access-users-main`$html),
    error = function(e) ""
  )
  chk(
    "\"Access\" tab: the server part is registered for the administrator (users table, add button)",
    grepl("access-users-table", access_html, fixed = TRUE) &&
      grepl("access-users-add", access_html, fixed = TRUE)
  )
  chk(
    "\"Access\" tab: the permission editor and log toggles are rendered",
    all(vapply(
      c("access-role_editor", "access-logging_editor"),
      function(id) {
        !inherits(tryCatch(output[[id]], error = function(e) e), "error")
      },
      logical(1)
    ))
  )
  chk(
    "session log: the start of the session is recorded at sign-in (the session_log toggle works)",
    dbGetQuery(
      con,
      "SELECT COUNT(*) n FROM session_log WHERE action = 'start' AND user = 'boss'"
    )$n >=
      1
  )
  app_con_ref <<- conn
  # settings MUST be passed: with custom roles (owner, editor...) the role is "invalid" without them
  quiet(aa_create_user(con, "worker", "workpass1", "user", auth_settings))
  quiet(aa_create_user(con, "viewer1", "viewpass1", "viewer", auth_settings))
})

# 2. role permissions: a handler without the permission is rejected on the server even if the button was invoked from the browser
messages <- character()
# expr is passed to testServer as an expression (rlang::inject), otherwise it will not find session
run_app <- function(expr) {
  rlang::inject(withCallingHandlers(
    testServer(server, expr = !!rlang::enquo(expr)),
    message = function(m) {
      messages <<- c(messages, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  ))
}
login_as <- function(session, login, password) {
  session$setInputs(
    `auth-login` = login,
    `auth-password` = password,
    `auth-login_btn` = 1
  )
}
n_before <- dbGetQuery(
  con,
  "SELECT COUNT(*) n FROM action_log WHERE func_name = 'Access denied'"
)$n
run_app({
  login_as(session, "viewer1", "viewpass1")
  session$setInputs(`tasks-run` = 1)
}) # viewer does not hold the Run permission
chk(
  "handler without the permission: rejected, Access denied written to the log",
  dbGetQuery(
    con,
    "SELECT COUNT(*) n FROM action_log WHERE func_name = 'Access denied'"
  )$n ==
    n_before + 1
)
n_before <- dbGetQuery(
  con,
  "SELECT COUNT(*) n FROM action_log WHERE func_name = 'Access denied'"
)$n
run_app({
  login_as(session, "worker", "workpass1")
  session$setInputs(`tasks-run` = 1)
}) # user holds the Run permission
chk(
  "handler with the permission runs, no denial",
  dbGetQuery(
    con,
    "SELECT COUNT(*) n FROM action_log WHERE func_name = 'Access denied'"
  )$n ==
    n_before
)

# 3. user management: administrator only
run_app({
  login_as(session, "worker", "workpass1")
  session$setInputs(`access-users-open` = "viewer1")
  session$setInputs(`access-users-block` = 1)
})
chk(
  "the user role cannot block users",
  dbGetQuery(
    con,
    "SELECT blocked FROM users WHERE login = 'viewer1'"
  )$blocked ==
    0
)

# 4. lockout after failed attempts and an open session
testServer(server, {
  for (i in 1:5) {
    session$setInputs(
      `auth-login` = "worker",
      `auth-password` = paste0("bad", i),
      `auth-login_btn` = i
    )
  }
  chk(
    "5 wrong passwords: the lockout message is shown",
    grepl("Too many failed sign-in attempts", output$`auth-message`)
  )
  session$setInputs(
    `auth-login` = "worker",
    `auth-password` = "workpass1",
    `auth-login_btn` = 6
  )
  chk(
    "the correct password of a locked login does not let in",
    !auth$logged_in()
  )
})
quiet(dbExecute(con, "DELETE FROM login_attempts"))

testServer(server, {
  session$setInputs(
    `auth-login` = "worker",
    `auth-password` = "workpass1",
    `auth-login_btn` = 1
  )
  chk("worker signs in", auth$logged_in())
  quiet(aa_set_blocked(con, "worker", TRUE))
  session$elapse(31000)
  chk(
    "after blocking, the open session is closed at the next check",
    !auth$logged_in()
  )
})
quiet(aa_set_blocked(con, "worker", FALSE))

# 5. package events and the log: no event is left without a decision
chk(
  "every package event is mapped to the log or deliberately skipped",
  all(aa_events()$event %in% c(names(AUTH_EVENT_ACTIONS), AUTH_EVENTS_IGNORED))
)
chk(
  "permissions are read from the config.yaml matrix: viewer without Run, user with it",
  !user_can("viewer", "Run", cfg) &&
    user_can("user", "Run", cfg) &&
    user_can("admin", "Access", cfg)
)

dbDisconnect(con)

# 6. the connection is closed together with the session, the database file is not locked
chk(
  "after sessions close, the app's database connection is closed",
  exists("app_con_ref") && !DBI::dbIsValid(app_con_ref)
)
db_file <- cfg$database_settings$app_data_base
chk(
  "the database file can be renamed and restored (it is not locked)",
  isTRUE(file.rename(db_file, "moved.db")) && file.rename("moved.db", db_file)
)

setwd(Sys.getenv("TEMP", tempdir()))
unlink(tmp, recursive = TRUE)
finish_tests()
