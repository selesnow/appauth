# Shiny app skeleton with appauth authentication.
#
# What is already here: login and creation of the first administrator, auto-login, brute-force protection,
# permissions from the config.yaml matrix, tabs by permission, server parts of tabs only when the permission is held,
# handler protection, the "Access" tab (users, permission editor, log toggles),
# changing your own password, sign-out and sign-out on all devices (with confirmation), closing connections.
#
# What to replace for your app: permission and tab names (config.yaml: access_matrix),
# the contents of the "Tasks" tab (mod_tasks) and the action handler input$run.
#
# Run: shiny::runApp(".")

library(shiny)
library(appauth)

source("create_config.R")
ensure_config("config.yaml")
conf <<- yaml::read_yaml("config.yaml")

# R/ is sourced into the GLOBAL environment, so auth_settings is also created globally (<<-):
# under runApp() app.R itself is loaded into its own environment
for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)
for (f in list.files("modules", pattern = "[.]R$", full.names = TRUE)) source(f)
auth_settings <<- build_auth_settings(conf$security)

# database schema (auth tables, columns) and logs: at every start, safe on production databases
local({
  con <- DBI::dbConnect(RSQLite::SQLite(), conf$database_settings$app_data_base)
  on.exit(DBI::dbDisconnect(con))
  aa_prepare_db(con, auth_settings)
  ensure_log_tables(con)
})

ui <- fluidPage(
  aa_app_head(),                      # styles and the auto-login cookie script
  titlePanel("My app"),
  aa_auth_ui("auth"),                 # login form or first-administrator creation
  uiOutput("app_ui")
)

server <- function(input, output, session) {
  # the connection is closed together with the session (otherwise it holds the database file)
  conn <- aa_session_connection(conf$database_settings$app_data_base)
  conf_rv <- reactiveVal(conf)

  auth <- aa_auth_server("auth", conn, auth_settings, on_event = log_auth_event,
                         title = "Sign in", cookie_name = "myapp_token")   # every app on the host has its own cookie name

  # blocking, deletion, role change and password reset take effect within session_check_seconds
  aa_session_guard(auth, conn, auth_settings)

  # server parts of tabs are attached only for those who hold the permission
  aa_register_module(auth, "Tasks", conf_permissions(conf_rv), function() {
    mod_tasks_server("tasks", auth, conf_rv, session$token)
  })
  aa_register_module(auth, "Access", admin_only_provider, function() {
    mod_access_server("access", conn, auth, session$token, conf_rv)
  })
  # session log: start at sign-in, end when the browser tab is closed (sign-out by button is written by the event hook)
  observeEvent(auth$user(), {
    user <- auth$user()
    if (!is.null(user)) session_log(session$token, user$login, "start")
  }, ignoreNULL = FALSE, ignoreInit = TRUE)
  session$onSessionEnded(function() {
    user <- isolate(auth$user())
    if (!is.null(user)) session_log(session$token, user$login, "end")
  })

  pw <- aa_password_server("password", conn, auth, auth_settings, on_event = log_auth_event)

  output$app_ui <- renderUI({
    req(auth$logged_in())
    user <- auth$user()
    can <- function(permission) user_can(user$role, permission, conf_rv())

    tagList(
      div(                            # user badge and personal-cabinet buttons
        style = "margin-bottom: 12px;",
        span(icon("user"), strong(user$login), paste0(" (", user$role, ") ")),
        actionButton("change_password", "Change password", class = "btn-sm"),
        actionButton("logout_all", "Sign out on all devices", class = "btn-sm"),
        actionButton("logout", "Sign out", class = "btn-danger btn-sm")
      ),
      do.call(tabsetPanel, Filter(Negate(is.null), list(
        if (can("Tasks")) mod_tasks_ui("tasks", can_run = can("Run")),
        if (identical(user$role, auth_settings$admin_role)) tabPanel("Access", mod_access_ui("access"))
      )))
    )
  })

  # changing your own password: the module form in a dialog, closed after a successful change
  observeEvent(input$change_password, {
    showModal(modalDialog(aa_password_ui("password"), title = "Change password", easyClose = TRUE, footer = modalButton("Close")))
  })
  observeEvent(pw$changed(), removeModal(), ignoreInit = TRUE)

  # sign-out on all devices only after confirmation
  observeEvent(input$logout_all, {
    showModal(modalDialog(
      "All your sessions on all devices will be ended, you will have to sign in to the app again.",
      title = "Sign out on all devices?", easyClose = TRUE,
      footer = tagList(modalButton("Cancel"), actionButton("logout_all_confirm", "Sign out everywhere", class = "btn-danger"))
    ))
  })
  observeEvent(input$logout_all_confirm, { removeModal(); auth$logout_all(reload = TRUE) })
  observeEvent(input$logout, auth$logout(reload = TRUE))
}

shinyApp(ui, server)
