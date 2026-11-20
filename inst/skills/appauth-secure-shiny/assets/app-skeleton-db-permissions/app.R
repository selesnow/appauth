# Reports portal: appauth authentication, per-user permissions stored in the DB.
# Run: shiny::runApp(".")

library(shiny)
library(appauth)

# R/ goes to the global environment, so settings are global (<<-), see R/auth_setup.R
for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) {
  source(f)
}
auth_settings <<- build_auth_settings()
prepare_app_db(app_db_path(), auth_settings)

ui <- fluidPage(
  aa_app_head(),
  titlePanel("Reports portal"),
  aa_auth_ui("auth"),
  uiOutput("main")
)

server <- function(input, output, session) {
  conn <- aa_session_connection(app_db_path()) # closed with the session
  provider <- make_permission_provider(conn, auth_settings)

  auth <- aa_auth_server(
    "auth",
    conn,
    auth_settings,
    on_event = log_auth_event,
    title = "Reports portal",
    cookie_name = "reports_portal_token"
  )
  aa_session_guard(auth, conn, auth_settings)
  pw <- aa_password_server(
    "password",
    conn,
    auth,
    auth_settings,
    on_event = log_auth_event
  )

  # "Permissions" block in the user card (slot): the factories live in R/auth_setup.R, so tests can use them
  card_ui <- make_card_ui(conn)
  card_server <- make_card_server(conn, auth)

  # server part of the Users tab is registered only for users with the "users" right (owner)
  aa_register_module(auth, "users", provider, function() {
    aa_users_server(
      "users",
      conn,
      auth,
      auth_settings,
      on_event = log_auth_event,
      extra_card_ui = card_ui,
      extra_card_server = card_server
    )
  })

  output$main <- renderUI({
    req(auth$logged_in())
    user <- auth$user()
    tabs <- list(
      if (aa_can(user, "reports", provider)) {
        tabPanel(
          "Reports",
          p("Quarterly report for ", strong(user$login)),
          actionButton("export", "Export")
        )
      },
      if (aa_can(user, "users", provider)) {
        tabPanel("Users", aa_users_ui("users"))
      },
      tabPanel(
        "Profile",
        aa_password_ui("password"),
        hr(),
        actionButton("logout_all", "Sign out on all devices"),
        actionButton("logout", "Sign out", class = "btn-danger")
      )
    )
    tagList(
      p(icon("user"), strong(user$login), paste0(" (", user$role, ")")),
      do.call(
        tabsetPanel,
        c(list(id = "main_tabs"), Filter(Negate(is.null), tabs))
      )
    )
  })

  # the permission is checked in the handler itself: a hidden button is not protection
  observeEvent(input$export, {
    aa_require(
      auth,
      "export",
      provider,
      on_event = log_auth_event,
      settings = auth_settings
    )
    log_auth_event("export_done", auth$user()$login, session$token, "reports")
    showNotification("Export started", type = "message")
  })

  observeEvent(input$logout_all, {
    showModal(modalDialog(
      "All your sessions on all devices will be closed.",
      title = "Sign out on all devices?",
      easyClose = TRUE,
      footer = tagList(
        modalButton("Cancel"),
        actionButton(
          "logout_all_confirm",
          "Sign out everywhere",
          class = "btn-danger"
        )
      )
    ))
  })
  observeEvent(input$logout_all_confirm, {
    removeModal()
    auth$logout_all(reload = TRUE)
  })
  observeEvent(input$logout, auth$logout(reload = TRUE))
}

shinyApp(ui, server)
