suppressMessages({
  pkgload::load_all(Sys.getenv("AA_PKG", "."), quiet = TRUE)
  library(shiny)
})

db_path <- Sys.getenv("AA_DB")
log_path <- Sys.getenv("AA_LOG")
settings <- aa_settings(max_failed_logins = 3, session_check_seconds = 2)
provider <- aa_permissions_from_matrix(list(
  Tasks = c("admin", "user", "viewer"),
  Access = "admin"
))

log_event <- function(event, user, session_id, value) {
  cat(sprintf("%s|%s|%s\n", event, user, value), file = log_path, append = TRUE)
}

ui <- fluidPage(
  aa_app_head(),
  aa_auth_ui("auth"),
  uiOutput("app")
)

server <- function(input, output, session) {
  conn <- aa_session_connection(db_path)

  auth <- aa_auth_server(
    "auth",
    conn,
    settings,
    on_event = log_event,
    title = "E2E App"
  )

  aa_session_guard(auth, conn, settings)
  aa_password_server("pw", conn, auth, settings, on_event = log_event)
  aa_register_module(auth, "Access", provider, function() {
    aa_users_server("users", conn, auth, settings, on_event = log_event)
  })

  output$app <- renderUI({
    req(auth$logged_in())
    tagList(
      div(
        style = "padding: 16px;",
        h3(id = "whoami", paste0(auth$user()$login, " / ", auth$user()$role)),
        actionButton("logout", "Sign out"),
        aa_password_ui("pw"),
        if (aa_can(auth$user(), "Access", provider)) aa_users_ui("users")
      )
    )
  })

  observeEvent(input$logout, auth$logout(reload = TRUE))
}

shinyApp(ui, server)
