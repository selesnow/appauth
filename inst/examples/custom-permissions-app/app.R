# An application with a different authorization model: custom roles and
# permissions stored per user in the database.
#
# What it shows (the appauth core is not tied to one permission scheme):
#   * custom roles owner / editor / viewer, with owner as the administrator role;
#   * a `function(user)` permission source instead of a matrix: permissions are read
#     from the user_permissions table, the owner gets all permissions and user
#     management (the "users" permission);
#   * a user card slot: a custom "Permissions" block with permission checkboxes;
#   * custom texts, custom button labels, a custom cookie name;
#   * a password set by the administrator is permanent by default (must_change_default = FALSE).
#
# Run: shiny::runApp("custom-permissions-app")
# The default database is temporary. A permanent one is set with APPAUTH_EXAMPLE_DB.

library(shiny)
library(appauth)

all_permissions <- c("reports", "export")

# Instead of an email, the example writes the password reset link to the console;
# a real application sends an email here, for example with the emayili package
send_reset <- function(email, link, login) {
  message(sprintf("[reset] %s (%s): %s", login, email, link))
}

settings <- aa_settings(
  roles = c("owner", "editor", "viewer"),
  admin_role = "owner",
  must_change_default = FALSE,
  max_failed_logins = 3,
  reset_enabled = TRUE,
  send_reset = send_reset,
  reset_base_url = Sys.getenv("APPAUTH_EXAMPLE_URL", "http://127.0.0.1:3838"),
  # two-factor authentication: in a real application the secret encryption key is taken
  # from an environment variable and kept out of the repository; this value is for the example
  totp_enabled = TRUE,
  totp_key = Sys.getenv(
    "APPAUTH_EXAMPLE_TOTP_KEY",
    "example-only-key-change-me-0123456789"
  ),
  totp_issuer = "Reports portal",
  texts = aa_texts(
    "en",
    login_title = "Reports portal",
    login_button = "Sign in"
  )
)

db_path <- Sys.getenv(
  "APPAUTH_EXAMPLE_DB",
  file.path(tempdir(), "custom-permissions-app.db")
)

log_event <- function(event, user, session_id, value) {
  message(sprintf("[audit] %s user=%s value=%s", event, user, value))
}

ui <- fluidPage(
  aa_app_head(),
  titlePanel("Reports portal"),
  aa_auth_ui("auth"),
  uiOutput("main")
)

server <- function(input, output, session) {
  conn <- aa_session_connection(db_path, prepare = TRUE, settings = settings)

  # the application's own table next to the appauth tables
  DBI::dbExecute(
    conn,
    "
    CREATE TABLE IF NOT EXISTS user_permissions (
      login      TEXT NOT NULL,
      permission TEXT NOT NULL,
      PRIMARY KEY (login, permission)
    )"
  )

  # permission source: any function(user) -> character()
  provider <- function(user) {
    # the owner gets all permissions and user management
    if (identical(user$role, settings$admin_role)) {
      return(c(all_permissions, "users"))
    }

    DBI::dbGetQuery(
      conn,
      "SELECT permission FROM user_permissions WHERE login = ?",
      params = list(user$login)
    )$permission
  }

  auth <- aa_auth_server(
    "auth",
    conn,
    settings,
    on_event = log_event,
    title = "Reports portal",
    cookie_name = "reports_portal_token"
  )
  aa_session_guard(auth, conn, settings)
  aa_password_server("password", conn, auth, settings, on_event = log_event)
  aa_totp_server("totp", conn, auth, settings, on_event = log_event)

  # user card slot: the application's permissions block
  card_ui <- function(login, ns) {
    current <- DBI::dbGetQuery(
      conn,
      "SELECT permission FROM user_permissions WHERE login = ?",
      params = list(login)
    )$permission

    div(
      class = "aa-card-section",
      h5("Permissions"),
      checkboxGroupInput(
        ns("permissions"),
        NULL,
        choices = all_permissions,
        selected = current
      ),
      actionButton(
        ns("save_permissions"),
        "Save permissions",
        class = "btn btn-primary btn-sm"
      )
    )
  }

  card_server <- function(input, output, session, login) {
    observeEvent(input$save_permissions, {
      # owner only, the role is taken from the server-side session state
      user <- isolate(auth$user())
      req(identical(user$role, settings$admin_role), login())

      DBI::dbWithTransaction(conn, {
        DBI::dbExecute(
          conn,
          "DELETE FROM user_permissions WHERE login = ?",
          params = list(login())
        )
        for (permission in intersect(input$permissions, all_permissions)) {
          DBI::dbExecute(
            conn,
            "INSERT INTO user_permissions (login, permission) VALUES (?, ?)",
            params = list(login(), permission)
          )
        }
      })

      log_event("permissions_changed", user$login, session$token, login())
      showNotification(
        paste("Permissions saved for", login()),
        type = "message"
      )
    })
  }

  # the users tab and its server part are available only with the "users" permission
  aa_register_module(auth, "users", provider, function() {
    aa_users_server(
      "users",
      conn,
      auth,
      settings,
      on_event = log_event,
      extra_card_ui = card_ui,
      extra_card_server = card_server
    )
  })

  output$main <- renderUI({
    req(auth$logged_in())
    user <- auth$user()

    tabs <- list(
      if (aa_can(user, "reports", provider)) {
        tabPanel("Reports", p("Quarterly report for ", strong(user$login)))
      },
      if (aa_can(user, "export", provider)) {
        tabPanel("Export", actionButton("export", "Export to CSV"))
      },
      if (aa_can(user, "users", provider)) {
        tabPanel("Users", aa_users_ui("users"))
      },
      tabPanel(
        "Profile",
        aa_password_ui("password"),
        hr(),
        aa_totp_ui("totp"),
        hr(),
        actionButton("logout", "Sign out")
      )
    )

    do.call(tabsetPanel, Filter(Negate(is.null), tabs))
  })

  observeEvent(input$export, {
    aa_require(
      auth,
      "export",
      provider,
      on_event = log_event,
      settings = settings
    )
    showNotification("Export started", type = "message")
  })

  observeEvent(input$logout, auth$logout(reload = TRUE))
}

shinyApp(ui, server)
