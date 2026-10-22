# Минимальное приложение с авторизацией appauth.
#
# Что показывает:
#   * вход, создание первого администратора на пустой базе, автовход по cookie;
#   * права из матрицы "право -> роли" (config.yaml), вкладки по правам;
#   * проверку права в обработчике (aa_require);
#   * вкладку пользователей для администратора;
#   * кнопки рядом с плашкой пользователя: смена своего пароля (окно с формой модуля),
#     выход и выход на всех устройствах (с подтверждением);
#   * принудительный выход при блокировке, удалении, смене роли или сброса пароля;
#   * хук событий (все события пишутся в консоль).
#
# Запуск: shiny::runApp("minimal-app")
# База по умолчанию временная, поэтому при каждом запуске приложение предложит
# создать администратора. Постоянную базу задаёт переменная APPAUTH_EXAMPLE_DB.

library(shiny)
library(appauth)

conf <- yaml::read_yaml("config.yaml")
settings <- aa_settings_from_list(conf$security, texts = aa_texts("ru"))
provider <- aa_permissions_from_matrix(function() conf$access_matrix)
db_path <- Sys.getenv("APPAUTH_EXAMPLE_DB", file.path(tempdir(), "minimal-app.db"))

# единственное место, где приложение решает, что делать с событиями авторизации
log_event <- function(event, user, session_id, value) {
  message(sprintf("[appauth] %s user=%s value=%s", event, user, value))
}

ui <- fluidPage(
  aa_app_head(),
  titlePanel("Минимальное приложение"),
  aa_auth_ui("auth"),
  uiOutput("main")
)

server <- function(input, output, session) {
  # подключение закрывается вместе с сессией, схема готовится при подключении
  conn <- aa_session_connection(db_path, prepare = TRUE, settings = settings)

  auth <- aa_auth_server("auth", conn, settings, on_event = log_event, title = "Вход")

  # блокировка, удаление, смена роли и сброс пароля вступают в силу за 30 секунд
  aa_session_guard(auth, conn, settings)

  # серверные части вкладок подключаются только тем, у кого есть право
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
          "Задачи",
          p("Вы вошли как ", strong(user$login), " (роль ", user$role, ")."),
          if (aa_can(user, "Run", provider)) actionButton("run", "Запустить задачу")
        )
      },
      if (aa_can(user, "Access", provider)) tabPanel("Доступ", aa_users_ui("users"))
    )

    tagList(
      # плашка пользователя с кнопками личного кабинета
      div(
        style = "margin-bottom: 12px;",
        span(icon("user"), strong(user$login), paste0(" (", user$role, ") ")),
        actionButton("change_password", "Сменить пароль", class = "btn-sm"),
        actionButton("logout_all", "Выйти на всех устройствах", class = "btn-sm"),
        actionButton("logout", "Выйти", class = "btn-danger btn-sm")
      ),
      do.call(tabsetPanel, Filter(Negate(is.null), tabs))
    )
  })

  # смена своего пароля: форма модуля в окне, после успешной смены окно закрывается
  observeEvent(input$change_password, {
    showModal(modalDialog(
      aa_password_ui("password"),
      title = "Смена пароля", easyClose = TRUE, footer = modalButton("Закрыть")
    ))
  })
  observeEvent(pw$changed(), removeModal(), ignoreInit = TRUE)

  # выход на всех устройствах только после подтверждения: кнопка выбросит и с других устройств
  observeEvent(input$logout_all, {
    showModal(modalDialog(
      "Все ваши сессии на всех устройствах будут завершены, в приложение придётся войти заново.",
      title = "Выйти на всех устройствах?", easyClose = TRUE,
      footer = tagList(
        modalButton("Отмена"),
        actionButton("logout_all_confirm", "Выйти везде", class = "btn-danger")
      )
    ))
  })
  observeEvent(input$logout_all_confirm, {
    removeModal()
    auth$logout_all(reload = TRUE)
  })

  observeEvent(input$run, {
    # проверка на сервере: скрытая кнопка не защита, обработчик можно вызвать из браузера
    aa_require(auth, "Run", provider, on_event = log_event, settings = settings)
    showNotification("Задача запущена", type = "message")
  })

  observeEvent(input$logout, auth$logout(reload = TRUE))
}

shinyApp(ui, server)
