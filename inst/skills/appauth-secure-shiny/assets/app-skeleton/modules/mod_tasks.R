# Example app tab: replace it with your own. Shows the correct pattern:
#   * namespaced (ns) identifiers, the handler inside the module;
#   * the action button is shown by permission (convenience), while the PROTECTION is the first line of the handler
#     (a hidden button is not protection: the handler can be called from the browser).

mod_tasks_ui <- function(id, can_run = FALSE) {
  ns <- NS(id)
  tabPanel(
    "Tasks",
    p("App tab contents."),
    if (can_run) actionButton(ns("run"), "Run")
  )
}

# the server part is registered only when the tab permission is held (aa_register_module in app.R)
mod_tasks_server <- function(id, auth, conf_rv, session_id) {
  moduleServer(id, function(input, output, session) {
    observeEvent(input$run, {
      require_permission(auth, conf_rv, "Run", session_id)   # the Run permission is checked on the server
      showNotification("Done", type = "message")
    })
  })
}
