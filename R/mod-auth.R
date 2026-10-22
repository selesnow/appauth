#' Модуль входа: интерфейс
#'
#' Форма входа (или создания первого администратора, если пользователей ещё
#' нет). Когда пользователь вошёл, модуль ничего не показывает. Стили подключаются
#' через [aa_app_head()].
#'
#' @param id Идентификатор модуля.
#'
#' @returns Элемент интерфейса Shiny.
#' @seealso [aa_auth_server()]
#' @export
#'
#' @examples
#' ui <- shiny::fluidPage(aa_app_head(), aa_auth_ui("auth"))
aa_auth_ui <- function(id) {
  shiny::uiOutput(shiny::NS(id, "form"))
}

#' Модуль входа: сервер
#'
#' Вход по логину и паролю с защитой от подбора ([aa_login_gate()]), создание
#' первого администратора на пустой базе, автовход по cookie (если включён в
#' настройках) и выход. Обо всех событиях модуль сообщает хуку `on_event`
#' (каталог в [aa_events()]), сам в логи ничего не пишет.
#'
#' Если пароль пользователю задал администратор (`must_change`), после ввода
#' верного пароля показывается форма смены пароля, и в приложение пользователь
#' попадает только после смены.
#'
#' Роль и логин берутся из базы, а не из введённой строки. Подключение `conn`
#' принадлежит приложению: закрывайте его при завершении сессии.
#'
#' @param id Идентификатор модуля, такой же, как в [aa_auth_ui()].
#' @param conn Подключение к базе SQLite со схемой [aa_init_db()].
#' @param settings Настройки, результат [aa_settings()].
#' @param on_event Хук событий `function(event, user, session_id, value)` или `NULL`.
#' @param title Заголовок формы входа. По умолчанию текст `login_title`.
#' @param logo Адрес картинки над заголовком (например `"logo.png"` из папки
#'   `www`) или `NULL`.
#' @param cookie_name Имя cookie автовхода. Cookie не изолируются по порту,
#'   поэтому приложениям на одном хосте нужны разные имена.
#'
#' @returns Список: `user` (реактивное значение, список `login` и `role` либо
#'   `NULL`), `logged_in` (реактивное логическое), `role` (реактивная роль либо
#'   `NULL`), функция `token()` (токен автовхода этой сессии или `NULL`, нужен
#'   [aa_session_guard()]) и функция `logout(reason = NULL, reload = FALSE)`. Без `reason`
#'   это обычный выход (событие `logout`), с `reason` (`"blocked"`, `"deleted"`,
#'   `"role_changed"`, `"token_revoked"`) принудительный (`session_forced_logout`). При
#'   `reload = TRUE` страница перезагружается, чтобы модули прежнего пользователя
#'   исчезли.
#' @seealso [aa_auth_ui()]
#' @export
#'
#' @examples
#' \dontrun{
#' server <- function(input, output, session) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), "app.db")
#'   aa_init_db(conn)
#'   session$onSessionEnded(function() DBI::dbDisconnect(conn))
#'
#'   auth <- aa_auth_server("auth", conn, on_event = log_event)
#'   output$app <- shiny::renderUI(if (auth$logged_in()) main_ui())
#' }
#' }
aa_auth_server <- function(id, conn, settings = aa_settings(), on_event = NULL,
                           title = NULL, logo = NULL, cookie_name = "appauth_token") {
  aa_check_sqlite(conn)

  shiny::moduleServer(id, function(input, output, session) {
    user <- shiny::reactiveVal(NULL)
    message_text <- shiny::reactiveVal("")
    current_token <- NULL
    # вошёл с паролем, который задал администратор: пока не сменит, в приложение не пускаем
    pending <- shiny::reactiveVal(NULL)

    users_exist <- shiny::reactiveVal(
      tryCatch(aa_users_exist(conn), error = function(e) TRUE)
    )

    emit <- function(event, login = NULL, value = NULL) {
      aa_emit(on_event, event, login, session$token, value)
    }

    finish_login <- function(login, role, issue_token = TRUE) {
      message_text("")
      user(list(login = login, role = role))

      if (issue_token) {
        token <- tryCatch(
          aa_issue_token(conn, login, settings),
          error = function(e) {
            message("appauth: не удалось выдать токен автовхода: ", conditionMessage(e))
            NULL
          }
        )

        if (!is.null(token)) {
          current_token <<- token
          session$sendCustomMessage(
            "appauth_set_cookie",
            list(name = cookie_name, token = token, days = settings$session_days)
          )
        }
      }
    }

    # автовход по cookie
    if (isTRUE(settings$autologin)) {
      session$onFlushed(function() {
        session$sendCustomMessage(
          "appauth_read_cookie",
          list(name = cookie_name, input = session$ns("cookie"))
        )
      }, once = TRUE)

      shiny::observeEvent(input$cookie, {
        if (!is.null(shiny::isolate(user())) || !aa_is_string(input$cookie)) {
          return()
        }

        found <- tryCatch(aa_find_session_user(conn, input$cookie), error = function(e) NULL)

        if (is.null(found)) {
          # токен устарел, отозван или принадлежит заблокированному: убираем cookie
          session$sendCustomMessage("appauth_clear_cookie", list(name = cookie_name))
          return()
        }

        current_token <<- input$cookie
        finish_login(found$login, found$role, issue_token = FALSE)
        emit("login_success", found$login, "cookie")
      })
    }

    logout <- function(reason = NULL, reload = FALSE) {
      login <- shiny::isolate(user())$login

      if (!is.null(current_token)) {
        try(aa_revoke_token(conn, current_token), silent = TRUE)
      }
      current_token <<- NULL
      session$sendCustomMessage("appauth_clear_cookie", list(name = cookie_name))

      if (is.null(reason)) {
        emit("logout", login)
      } else {
        emit("session_forced_logout", login, reason)
      }

      message_text("")
      user(NULL)
      users_exist(tryCatch(aa_users_exist(conn), error = function(e) TRUE))

      if (isTRUE(reload)) {
        session$reload()
      }

      invisible(TRUE)
    }

    output$form <- shiny::renderUI({
      if (!is.null(user())) {
        return(NULL)
      }

      ns <- session$ns
      hint <- NULL

      fields <- if (!is.null(pending())) {
        heading <- aa_text(settings, "must_change_title")
        hint <- shiny::tags$p(class = "aa-login-hint", aa_text(settings, "must_change_hint"))
        shiny::tagList(
          shiny::passwordInput(ns("change_password"), aa_text(settings, "password_new_label")),
          shiny::passwordInput(ns("change_confirm"), aa_text(settings, "password_confirm_label")),
          shiny::actionButton(ns("change_btn"), aa_text(settings, "password_change_button"), class = "aa-login-button"),
          shiny::div(class = "aa-login-message", shiny::textOutput(ns("message")))
        )
      } else if (users_exist()) {
        heading <- title %||% aa_text(settings, "login_title")
        shiny::tagList(
          shiny::textInput(ns("login"), aa_text(settings, "login_label")),
          shiny::passwordInput(ns("password"), aa_text(settings, "password_label")),
          shiny::actionButton(ns("login_btn"), aa_text(settings, "login_button"), class = "aa-login-button"),
          shiny::div(class = "aa-login-message", shiny::textOutput(ns("message")))
        )
      } else {
        heading <- aa_text(settings, "setup_title")
        hint <- shiny::tags$p(class = "aa-login-hint", aa_text(settings, "setup_hint", settings$admin_role))
        shiny::tagList(
          shiny::textInput(ns("setup_login"), aa_text(settings, "login_label")),
          shiny::passwordInput(ns("setup_password"), aa_text(settings, "password_label")),
          shiny::passwordInput(ns("setup_confirm"), aa_text(settings, "password_confirm_label")),
          shiny::actionButton(ns("setup_btn"), aa_text(settings, "setup_button"), class = "aa-login-button"),
          shiny::div(class = "aa-login-message", shiny::textOutput(ns("message")))
        )
      }

      shiny::div(
        class = "aa-login",
        shiny::div(
          class = "aa-login-card",
          if (!is.null(logo)) shiny::tags$img(src = logo, class = "aa-login-logo"),
          shiny::tags$h2(class = "aa-login-title", heading),
          hint,
          fields
        )
      )
    })

    output$message <- shiny::renderText(message_text())
    shiny::outputOptions(output, "message", suspendWhenHidden = FALSE)

    shiny::observeEvent(input$login_btn, {
      login <- input$login
      password <- input$password

      if (!aa_is_string(login) || !aa_is_string(password)) {
        message_text(aa_text(settings, "bad_credentials"))
        return()
      }

      # заблокированный логин и общий лимит: пароль не проверяем и попытку не
      # записываем, чтобы блокировка не продлевалась
      gate <- aa_login_gate(conn, login, settings)
      if (!gate$allowed) {
        message_text(gate$message)
        emit(if (gate$reason == "throttled") "login_throttled" else "login_locked", login, gate$seconds)
        return()
      }

      res <- aa_authenticate(conn, login, password)

      if (!is.null(res) && isTRUE(res$blocked[1] == 1)) {
        # пароль верный, но учётная запись заблокирована: об этом сообщаем только
        # тому, кто знает пароль, чтобы не раскрывать список логинов
        message_text(aa_text(settings, "blocked_user"))
        emit("login_blocked_user", login)
        return()
      }

      if (!is.null(res)) {
        try(aa_record_attempt(conn, login, success = TRUE, settings = settings), silent = TRUE)

        if (isTRUE(res$must_change[1] == 1)) {
          # пароль верный, но его задал администратор: сначала смена пароля
          message_text("")
          pending(list(login = res$login[1], role = res$role[1], old = password))
          return()
        }

        finish_login(res$login[1], res$role[1])
        emit("login_success", res$login[1])
        return()
      }

      try(aa_record_attempt(conn, login, success = FALSE, settings = settings), silent = TRUE)

      # эта попытка могла привести к блокировке
      gate <- aa_login_gate(conn, login, settings)
      if (!gate$allowed && gate$reason == "locked") {
        message_text(gate$message)
        emit("login_locked", login, gate$seconds)
      } else {
        message_text(aa_text(settings, "bad_credentials"))
        emit("login_failed", login)
      }
    })

    shiny::observeEvent(input$change_btn, {
      waiting <- pending()
      shiny::req(waiting)

      if (!identical(input$change_password, input$change_confirm)) {
        message_text(aa_text(settings, "passwords_mismatch"))
        return()
      }

      changed <- tryCatch(
        {
          aa_change_own_password(conn, waiting$login, waiting$old, input$change_password, settings)
          TRUE
        },
        appauth_error_user = function(e) {
          message_text(conditionMessage(e))
          FALSE
        }
      )

      if (changed) {
        pending(NULL)
        emit("password_changed", waiting$login)
        finish_login(waiting$login, waiting$role)
        emit("login_success", waiting$login)
      }
    })

    shiny::observeEvent(input$setup_btn, {
      # пользователя могли создать в другой вкладке или сессии
      if (tryCatch(aa_users_exist(conn), error = function(e) FALSE)) {
        users_exist(TRUE)
        return()
      }

      login <- input$setup_login
      password <- input$setup_password

      if (!identical(password, input$setup_confirm)) {
        message_text(aa_text(settings, "passwords_mismatch"))
        return()
      }

      created <- tryCatch(
        aa_create_first_admin(conn, login, password, settings),
        appauth_error_user = function(e) {
          message_text(conditionMessage(e))
          NULL
        }
      )

      if (is.null(created)) {
        return()
      }

      users_exist(TRUE)

      if (isTRUE(created)) {
        emit("first_admin_created", login)
        finish_login(login, settings$admin_role)
      }
    })

    list(
      user = shiny::reactive(user()),
      logged_in = shiny::reactive(!is.null(user())),
      role = shiny::reactive(user()$role),
      logout = logout,
      token = function() current_token
    )
  })
}
