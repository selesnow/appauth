# A minimal application with appauth authentication.
#
# What it shows:
#   * login, creating the first administrator on an empty database, cookie auto-login;
#   * permissions from a "permission -> roles" matrix (config.yaml), tabs by permission;
#   * a permission check in a handler (aa_require);
#   * a users tab for the administrator;
#   * buttons next to the user badge: change your own password (a dialog with the
#     module form), sign out and sign out on all devices (with confirmation);
#   * forced logout on blocking, deletion, role change or password reset;
#   * an events hook (all events are written to the console).
#
# Run: shiny::runApp("minimal-app")
# The default database is temporary, so every run offers to create an
# administrator. A permanent database is set with APPAUTH_EXAMPLE_DB.

library(shiny)
library(appauth)

conf <- yaml::read_yaml("config.yaml")
settings <- aa_settings_from_list(conf$security)
provider <- aa_permissions_from_matrix(function() conf$access_matrix)
db_path <- Sys.getenv("APPAUTH_EXAMPLE_DB", file.path(tempdir(), "minimal-app.db"))

# the only place where the app decides what to do with authentication events
log_event <- function(event, user, session_id, value) {
  message(sprintf("[appauth] %s user=%s value=%s", event, user, value))
}

ui <- fluidPage(
  aa_app_head(),
  titlePanel("Minimal application"),
  aa_auth_ui("auth"),
  uiOutput("main")
)

server <- function(input, output, session) {
  # the connection is closed with the session, the schema is prepared on connect
  conn <- aa_session_connection(db_path, prepare = TRUE, settings = settings)

  auth <- aa_auth_server("auth", conn, settings, on_event = log_event, title = "Sign in")

  # blocking, deletion, role change and password reset take effect within 30 seconds
  aa_session_guard(auth, conn, settings)

  # the server parts of tabs are attached only for users who have the permission
  aa_register_module(auth, "Access", provider, function() {
    aa_users_server("users", conn, auth, settings, on_event = log_event)
  })
  pw <- aa_password_server("password", conn, auth, settings, on_event = log_event)

  output$main <- renderUI({
    req(auth$logged_in())
    user <- auth$user()

    tabs <- list(
      if (aa_can(user, "Tasks", provider)) {
        tabPanel(
          "Tasks",
          p("Signed in as ", strong(user$login), " (role ", user$role, ")."),
          if (aa_can(user, "Run", provider)) actionButton("run", "Run task")
        )
      },
      if (aa_can(user, "Access", provider)) tabPanel("Access", aa_users_ui("users"))
    )

    tagList(
      # user badge with the account buttons
      div(
        style = "margin-bottom: 12px;",
        span(icon("user"), strong(user$login), paste0(" (", user$role, ") ")),
        actionButton("change_password", "Change password", class = "btn-sm"),
        actionButton("logout_all", "Sign out everywhere", class = "btn-sm"),
        actionButton("logout", "Sign out", class = "btn-danger btn-sm")
      ),
      do.call(tabsetPanel, Filter(Negate(is.null), tabs))
    )
  })

  # changing your own password: the module form in a dialog, closed after a successful change
  observeEvent(input$change_password, {
    showModal(modalDialog(
      aa_password_ui("password"),
      title = "Change password", easyClose = TRUE, footer = modalButton("Close")
    ))
  })
  observeEvent(pw$changed(), removeModal(), ignoreInit = TRUE)

  # sign out everywhere only after confirmation: the button also ends sessions on other devices
  observeEvent(input$logout_all, {
    showModal(modalDialog(
      "All your sessions on all devices will be ended; you will have to sign in again.",
      title = "Sign out on all devices?", easyClose = TRUE,
      footer = tagList(
        modalButton("Cancel"),
        actionButton("logout_all_confirm", "Sign out everywhere", class = "btn-danger")
      )
    ))
  })
  observeEvent(input$logout_all_confirm, {
    removeModal()
    auth$logout_all(reload = TRUE)
  })

  observeEvent(input$run, {
    # a server-side check: a hidden button is not protection, the handler can be called from the browser
    aa_require(auth, "Run", provider, on_event = log_event, settings = settings)
    showNotification("Task started", type = "message")
  })

  observeEvent(input$logout, auth$logout(reload = TRUE))
}

shinyApp(ui, server)
