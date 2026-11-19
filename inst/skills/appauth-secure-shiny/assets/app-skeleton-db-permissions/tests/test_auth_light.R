# Lightweight end-to-end test of an app with appauth WITHOUT config.yaml (template from the appauth-secure-shiny skill).
# Adapt to your app: the name of the environment variable with the database path, app files, permissions, input names (export...).
# Run from the app root: Rscript --no-init-file --no-site-file tests/test_auth_light.R
# The app is loaded INTO ITS OWN ENVIRONMENT, as runApp() does: otherwise environment errors disappear.
# End-to-end test of Reports portal.
# Works on a temporary copy and a temporary DB; the real app.db is not touched.
proj <- normalizePath(getwd(), winslash = "/")
libs <- .libPaths()
source(file.path(proj, "tests/helper.R"))

tmp <- file.path(Sys.getenv("TEMP", tempdir()), "reports_portal_test"); unlink(tmp, recursive = TRUE); dir.create(tmp)
invisible(file.copy(file.path(proj, "app.R"), tmp)); invisible(file.copy(file.path(proj, "R"), tmp, recursive = TRUE))
setwd(tmp); .libPaths(libs)
Sys.setenv(REPORTS_PORTAL_DB = file.path(tmp, "test.db"))
suppressMessages({library(shiny); library(DBI); library(appauth)})

# load app.R into its own environment, like runApp() does
app_env <- new.env(parent = globalenv())
invisible(suppressWarnings(suppressMessages(eval(parse(text = readLines("app.R", encoding = "UTF-8")), envir = app_env))))
server <- app_env$server
chk("app.R loaded, server found", is.function(server))

con <- dbConnect(RSQLite::SQLite(), Sys.getenv("REPORTS_PORTAL_DB"))
chk("tables: users, user_permissions", all(c("users", "user_permissions") %in% dbListTables(con)))
chk("roles are owner/editor/viewer, admin role owner",
    identical(auth_settings$roles, c("owner", "editor", "viewer")) && identical(auth_settings$admin_role, "owner"))
chk("must_change_default is FALSE", isFALSE(auth_settings$must_change_default))

prov <- make_permission_provider(con, auth_settings)
quiet(aa_create_user(con, "boss", "bosspass1", "owner", auth_settings))
quiet(aa_create_user(con, "ed", "edpass123", "editor", auth_settings))
quiet(aa_create_user(con, "vi", "vipass123", "viewer", auth_settings))
chk("owner has all rights and users", setequal(prov(list(login = "boss", role = "owner")), c("reports", "export", "users")))
chk("editor without rows has no rights", length(prov(list(login = "ed", role = "editor"))) == 0)
save_user_permissions(con, "ed", c("reports", "bogus"))
chk("saving ignores unknown permissions", identical(prov(list(login = "ed", role = "editor")), "reports"))
chk("saving for an unknown user fails", inherits(try(save_user_permissions(con, "nobody", "reports"), silent = TRUE), "try-error"))
chk("rights of the owner do not depend on table rows", "export" %in% prov(list(login = "boss", role = "owner")))
chk("permission SQL is not injectable via login", length(prov(list(login = "x' OR '1'='1", role = "viewer"))) == 0)
chk("password created by owner is permanent (must_change = 0)",
    dbGetQuery(con, "SELECT must_change FROM users WHERE login = 'ed'")$must_change == 0)

messages <- character()
run_app <- function(expr) {
  rlang::inject(withCallingHandlers(
    testServer(server, expr = !!rlang::enquo(expr)),
    message = function(m) { messages <<- c(messages, conditionMessage(m)); invokeRestart("muffleMessage") }
  ))
}
login_as <- function(session, l, p) session$setInputs(`auth-login` = l, `auth-password` = p, `auth-login_btn` = 1)

# Export is protected on the server
messages <- character()
run_app({ login_as(session, "ed", "edpass123"); session$setInputs(export = 1) })
chk("editor without export: denied, no export_done", any(grepl("access_denied", messages)) && !any(grepl("export_done", messages)))
save_user_permissions(con, "ed", c("reports", "export"))
messages <- character()
run_app({ login_as(session, "ed", "edpass123"); session$setInputs(export = 1) })
chk("editor with export: export done, no denial", any(grepl("export_done", messages)) && !any(grepl("access_denied", messages)))
messages <- character()
run_app({ login_as(session, "vi", "vipass123"); session$setInputs(export = 1) })
chk("viewer without rights: denied", any(grepl("access_denied", messages)) && !any(grepl("export_done", messages)))

# Users tab server part exists only for the owner
run_app({
  login_as(session, "boss", "bosspass1"); session$flushReact()
  html <- tryCatch(as.character(output$`users-main`$html), error = function(e) "")
  chk("owner: Users tab rendered (users table)", grepl("users-table", html, fixed = TRUE))
})
run_app({
  login_as(session, "ed", "edpass123"); session$flushReact()
  html <- tryCatch(as.character(output$`users-main`$html), error = function(e) "")
  chk("editor: Users tab server part is not registered", !nzchar(html))
})

# non-owner cannot save permissions through the card slot
save_user_permissions(con, "vi", character())
run_app({
  login_as(session, "ed", "edpass123")
  session$setInputs(`users-open` = "vi", `users-permissions` = c("reports", "export"), `users-save_permissions` = 1)
})
chk("editor cannot grant rights", length(prov(list(login = "vi", role = "viewer"))) == 0)

# the slot is protected by its own role check: test the module with a hand-made non-owner
save_user_permissions(con, "vi", character())
fake_editor <- list(user = function() list(login = "ed", role = "editor"))
suppressMessages(testServer(aa_users_server, args = list(conn = con, auth = fake_editor, settings = auth_settings,
                                                         extra_card_server = make_card_server(con, fake_editor)), {
  session$setInputs(open = "vi", permissions = c("reports", "export"), save_permissions = 1)
}))
chk("slot handler: editor cannot grant rights even if the module is mounted for him", length(prov(list(login = "vi", role = "viewer"))) == 0)
fake_owner <- list(user = function() list(login = "boss", role = "owner"))
suppressMessages(testServer(aa_users_server, args = list(conn = con, auth = fake_owner, settings = auth_settings,
                                                         extra_card_server = make_card_server(con, fake_owner)), {
  session$setInputs(open = "vi", permissions = c("reports"), save_permissions = 1)
}))
chk("slot handler: owner grants rights", identical(prov(list(login = "vi", role = "viewer")), "reports"))

chk("events: every package event is known", all(aa_events()$event != ""))
dbDisconnect(con)
setwd(Sys.getenv("TEMP", tempdir())); unlink(tmp, recursive = TRUE)
finish_tests()
