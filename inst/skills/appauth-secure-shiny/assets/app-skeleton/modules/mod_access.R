# The "Access" tab (administrator only): users (appauth module), role permission editor
# and log toggles. The permission editor and toggles are part of the app, not of the package.

mod_access_ui <- function(id) {
  ns <- NS(id)
  tagList(
    h3("Access management"),
    aa_users_ui(ns("users")), # table, card, adding, roles, passwords, lockouts, deletion
    hr(),
    h4("Role access to app functions"),
    uiOutput(ns("role_editor")),
    div(
      style = "text-align: right; margin-top: 10px;",
      actionButton(ns("save_roles"), "Save roles", class = "btn-success")
    ),
    hr(),
    h4("Logging"),
    uiOutput(ns("logging_editor")),
    actionButton(ns("save_logging"), "Save logging", class = "btn-success")
  )
}

mod_access_server <- function(id, conn, auth, session_id, conf_rv) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # all actions of the tab are for the admin only: the tab permission AND the administrator role, regardless of the matrix,
    # so that granting the permission to another role cannot be used to raise one's own rights
    require_access_admin <- function() {
      require_permission(auth, conf_rv, "Access", session_id)
      if (!identical(auth$user()$role, auth_settings$admin_role)) {
        showNotification("Insufficient rights for this action", type = "error")
        req(FALSE)
      }
    }

    users <- aa_users_server(
      "users",
      conn,
      auth,
      auth_settings,
      on_event = log_auth_event
    )
    observe({
      invalidateLater(60000, session)
      users$refresh()
    }) # lockout statuses change over time

    # --- role permission editor
    output$role_editor <- renderUI({
      tab_nodes <- conf_rv()$access_matrix
      rows <- split(names(tab_nodes), ceiling(seq_along(tab_nodes) / 4))
      tagList(lapply(rows, function(row_nodes) {
        fluidRow(lapply(row_nodes, function(node) {
          column(
            3,
            selectInput(
              ns(paste0("roles_", node)),
              label = node,
              choices = auth_settings$roles,
              selected = tab_nodes[[node]],
              multiple = TRUE
            )
          )
        }))
      }))
    })

    observeEvent(input$save_roles, {
      require_access_admin()
      new_conf <- conf_rv()
      for (node in names(new_conf$access_matrix)) {
        # only known permissions, new keys from the browser are not accepted
        id <- paste0("roles_", node)
        if (!is.null(input[[id]])) {
          new_conf$access_matrix[[node]] <- intersect(
            input[[id]],
            auth_settings$roles
          )
        }
      }
      conf_rv(new_conf)
      yaml::write_yaml(new_conf, "config.yaml")
      write_action_log(
        user = auth$user()$login,
        func = "Access config change",
        session_id
      )
      showNotification("Role permissions updated", type = "message")
    })

    # --- log toggles
    output$logging_editor <- renderUI(tagList(lapply(
      names(conf_rv()$logging),
      function(type) {
        checkboxInput(
          ns(paste0("log_", type)),
          type,
          value = isTRUE(conf_rv()$logging[[type]])
        )
      }
    )))

    observeEvent(input$save_logging, {
      require_access_admin()
      new_conf <- conf_rv()
      for (type in names(new_conf$logging)) {
        id <- paste0("log_", type)
        if (!is.null(input[[id]])) {
          new_conf$logging[[type]] <- isTRUE(input[[id]])
        }
      }
      conf_rv(new_conf)
      yaml::write_yaml(new_conf, "config.yaml")
      write_action_log(
        user = auth$user()$login,
        func = "Logging config change",
        session_id
      )
      showNotification("Logging settings updated", type = "message")
    })
  })
}
