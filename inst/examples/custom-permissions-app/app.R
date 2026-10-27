# Приложение с другой моделью авторизации: английский интерфейс, свои роли и
# права, которые хранятся в базе на каждого пользователя.
#
# Что показывает (ядро appauth не привязано к одной схеме прав):
#   * свои роли owner / editor / viewer, роль администратора owner;
#   * источник прав `function(user)` вместо матрицы: права читаются из таблицы
#     user_permissions, владелец (owner) получает все права и управление
#     пользователями (право "users");
#   * слот карточки пользователя: свой блок "Permissions" с галочками прав;
#   * английские тексты, свои названия кнопок, своё имя cookie;
#   * пароль от администратора по умолчанию постоянный (must_change_default = FALSE).
#
# Запуск: shiny::runApp("custom-permissions-app")
# База по умолчанию временная. Постоянную задаёт APPAUTH_EXAMPLE_DB.

library(shiny)
library(appauth)

all_permissions <- c("reports", "export")

# Вместо письма пример пишет ссылку восстановления пароля в консоль; в настоящем
# приложении здесь отправка почты, например через пакет emayili
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
  texts = aa_texts("en", login_title = "Reports portal", login_button = "Sign in")
)

db_path <- Sys.getenv("APPAUTH_EXAMPLE_DB", file.path(tempdir(), "custom-permissions-app.db"))

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

  # собственная таблица приложения рядом с таблицами appauth
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS user_permissions (
      login      TEXT NOT NULL,
      permission TEXT NOT NULL,
      PRIMARY KEY (login, permission)
    )")

  # источник прав: любая функция function(user) -> character()
  provider <- function(user) {
    # владелец получает все права и управление пользователями
    if (identical(user$role, settings$admin_role)) {
      return(c(all_permissions, "users"))
    }

    DBI::dbGetQuery(
      conn, "SELECT permission FROM user_permissions WHERE login = ?",
      params = list(user$login)
    )$permission
  }

  auth <- aa_auth_server(
    "auth", conn, settings, on_event = log_event,
    title = "Reports portal", cookie_name = "reports_portal_token"
  )
  aa_session_guard(auth, conn, settings)
  aa_password_server("password", conn, auth, settings, on_event = log_event)

  # слот карточки пользователя: блок прав приложения
  card_ui <- function(login, ns) {
    current <- DBI::dbGetQuery(
      conn, "SELECT permission FROM user_permissions WHERE login = ?",
      params = list(login)
    )$permission

    div(
      class = "aa-card-section",
      h5("Permissions"),
      checkboxGroupInput(ns("permissions"), NULL, choices = all_permissions, selected = current),
      actionButton(ns("save_permissions"), "Save permissions", class = "btn btn-primary btn-sm")
    )
  }

  card_server <- function(input, output, session, login) {
    observeEvent(input$save_permissions, {
      # только владелец, роль берём из серверного состояния сессии
      user <- isolate(auth$user())
      req(identical(user$role, settings$admin_role), login())

      DBI::dbWithTransaction(conn, {
        DBI::dbExecute(conn, "DELETE FROM user_permissions WHERE login = ?", params = list(login()))
        for (permission in intersect(input$permissions, all_permissions)) {
          DBI::dbExecute(
            conn, "INSERT INTO user_permissions (login, permission) VALUES (?, ?)",
            params = list(login(), permission)
          )
        }
      })

      log_event("permissions_changed", user$login, session$token, login())
      showNotification(paste("Permissions saved for", login()), type = "message")
    })
  }

  # вкладка пользователей и её серверная часть доступны только с правом "users"
  aa_register_module(auth, "users", provider, function() {
    aa_users_server(
      "users", conn, auth, settings, on_event = log_event,
      extra_card_ui = card_ui, extra_card_server = card_server
    )
  })

  output$main <- renderUI({
    req(auth$logged_in())
    user <- auth$user()

    tabs <- list(
      if (aa_can(user, "reports", provider)) tabPanel("Reports", p("Quarterly report for ", strong(user$login))),
      if (aa_can(user, "export", provider)) {
        tabPanel("Export", actionButton("export", "Export to CSV"))
      },
      if (aa_can(user, "users", provider)) tabPanel("Users", aa_users_ui("users")),
      tabPanel("Profile", aa_password_ui("password"), hr(), actionButton("logout", "Sign out"))
    )

    do.call(tabsetPanel, Filter(Negate(is.null), tabs))
  })

  observeEvent(input$export, {
    aa_require(auth, "export", provider, on_event = log_event, settings = settings)
    showNotification("Export started", type = "message")
  })

  observeEvent(input$logout, auth$logout(reload = TRUE))
}

shinyApp(ui, server)
