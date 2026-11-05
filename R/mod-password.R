#' Модуль смены собственного пароля: интерфейс
#'
#' Форма «текущий пароль, новый пароль, подтверждение». Показывается только
#' вошедшему пользователю. Разместите её там, где у приложения личный кабинет или
#' настройки (на вкладке или в модальном окне). Стили подключаются через
#' [aa_app_head()].
#'
#' @param id Идентификатор модуля.
#'
#' @returns Элемент интерфейса Shiny.
#' @seealso [aa_password_server()]
#' @export
#'
#' @examples
#' ui <- shiny::fluidPage(aa_app_head(), aa_password_ui("password"))
aa_password_ui <- function(id) {
  shiny::uiOutput(shiny::NS(id, "form"))
}

#' Модуль смены собственного пароля: сервер
#'
#' Пользователь подтверждает текущий пароль и задаёт новый ([aa_change_own_password()]).
#' Токены автовхода остальных сессий отзываются, текущая сессия продолжает
#' работать. О смене модуль сообщает хуку `on_event` событием `password_changed`.
#'
#' @param id Идентификатор модуля, такой же, как в [aa_password_ui()].
#' @param conn Подключение к базе данных.
#' @param auth Объект авторизации, результат [aa_auth_server()].
#' @param settings Настройки, результат [aa_settings()].
#' @param on_event Хук событий `function(event, user, session_id, value)` или `NULL`.
#'
#' @returns Список с реактивным значением `changed`: число успешных смен пароля в
#'   этой сессии (можно использовать, чтобы закрыть окно или показать сообщение).
#' @seealso [aa_password_ui()]
#' @export
#'
#' @examples
#' \dontrun{
#' auth <- aa_auth_server("auth", conn)
#' aa_password_server("password", conn, auth, on_event = log_event)
#' }
aa_password_server <- function(id, conn, auth, settings = aa_settings(), on_event = NULL) {
  aa_check_conn(conn)

  shiny::moduleServer(id, function(input, output, session) {
    changed <- shiny::reactiveVal(0)
    message_text <- shiny::reactiveVal("")
    # счётчик перерисовки формы: после успешной смены поля очищаются
    form_version <- shiny::reactiveVal(0)

    output$form <- shiny::renderUI({
      form_version()
      shiny::req(auth$user())
      ns <- session$ns

      shiny::div(
        class = "aa-password",
        shiny::h4(aa_text(settings, "password_change_title")),
        shiny::passwordInput(ns("old"), aa_text(settings, "password_old_label")),
        shiny::passwordInput(ns("new"), aa_text(settings, "password_new_label")),
        shiny::passwordInput(ns("confirm"), aa_text(settings, "password_confirm_label")),
        shiny::actionButton(ns("change"), aa_text(settings, "password_change_button"), class = "btn btn-primary"),
        shiny::div(class = "aa-login-message", shiny::textOutput(ns("message")))
      )
    })

    output$message <- shiny::renderText(message_text())
    shiny::outputOptions(output, "message", suspendWhenHidden = FALSE)

    shiny::observeEvent(input$change, {
      user <- shiny::isolate(auth$user())
      shiny::req(user)

      if (!identical(input$new, input$confirm)) {
        message_text(aa_text(settings, "passwords_mismatch"))
        return()
      }

      token <- if (is.function(auth$token)) auth$token() else NULL
      new_password <- input$new

      ok <- tryCatch(
        {
          aa_change_own_password(conn, user$login, input$old, input$new, settings, keep_token = token)
          TRUE
        },
        appauth_error_user = function(e) {
          message_text(conditionMessage(e))
          FALSE
        }
      )

      if (ok) {
        aa_emit(on_event, "password_changed", user$login, session$token)
        message_text("")
        form_version(form_version() + 1)
        changed(changed() + 1)
        shiny::showNotification(aa_text(settings, "done_password_changed"), type = "message")

        # в режиме password_policy = "warn" слабый пароль принимается, но об этом сообщаем
        weak <- aa_password_warning(new_password, settings, user$login)
        if (!is.null(weak)) {
          aa_emit(on_event, "weak_password_set", user$login, session$token, paste0(user$login, ": ", weak$reason))
          shiny::showNotification(weak$text, type = "warning")
        }
      }
    })

    list(changed = shiny::reactive(changed()))
  })
}
