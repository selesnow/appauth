#' Модуль пользователей: интерфейс
#'
#' Таблица пользователей со статусами и кнопка добавления. Двойной клик по строке
#' открывает карточку пользователя. Модуль виден только администратору, остальным
#' ничего не показывает. Стили подключаются через [aa_app_head()].
#'
#' Остальное содержимое вкладки «Доступ» (редактор прав, переключатели логов)
#' собирает приложение, например
#' `tabPanel("Доступ", aa_users_ui("users"), мой_редактор_прав())`.
#'
#' @param id Идентификатор модуля.
#'
#' @returns Элемент интерфейса Shiny.
#' @seealso [aa_users_server()]
#' @export
#'
#' @examples
#' ui <- shiny::fluidPage(aa_app_head(), aa_users_ui("users"))
aa_users_ui <- function(id) {
  shiny::uiOutput(shiny::NS(id, "main"))
}

#' Модуль пользователей: сервер
#'
#' Управление пользователями для администратора: добавление, смена роли, сброс
#' пароля, блокировка и разблокировка, снятие блокировки входа, удаление. Правила
#' (нельзя заблокировать или удалить себя, нельзя остаться без активного
#' администратора) проверяются на сервере функциями пакета, интерфейс лишь не
#' показывает недопустимые кнопки.
#'
#' Модуль не зависит от матрицы прав приложения: управлять пользователями может
#' только пользователь с ролью `settings$admin_role`, которая дополнительно
#' сверяется с базой при каждом действии. Цель действия берётся из серверного
#' состояния открытой карточки, а не из значения, присланного браузером.
#'
#' @section Слоты расширения:
#' Приложение может добавить свой блок в карточку пользователя.
#'
#' * `extra_card_ui(login, ns)` возвращает интерфейс блока. Идентификаторы
#'   элементов нужно оборачивать в `ns()`.
#' * `extra_card_server(input, output, session, login)` вызывается один раз при
#'   старте модуля внутри его пространства имён, `login` это реактивное значение
#'   с логином открытой карточки. Здесь регистрируются обработчики блока.
#'
#' @param id Идентификатор модуля, такой же, как в [aa_users_ui()].
#' @param conn Подключение к базе SQLite.
#' @param auth Объект авторизации, результат [aa_auth_server()].
#' @param settings Настройки, результат [aa_settings()].
#' @param on_event Хук событий `function(event, user, session_id, value)` или `NULL`.
#' @param extra_card_ui,extra_card_server Слоты расширения карточки, см. раздел
#'   «Слоты расширения».
#'
#' @returns Список с функцией `refresh()`, которая перерисовывает таблицу
#'   (например после изменений, сделанных не через модуль).
#' @seealso [aa_users_ui()], [aa_auth_server()]
#' @export
#'
#' @examples
#' \dontrun{
#' auth <- aa_auth_server("auth", conn)
#' shiny::observe({
#'   if (auth$logged_in()) aa_users_server("users", conn, auth, on_event = log_event)
#' })
#' }
aa_users_server <- function(id, conn, auth, settings = aa_settings(), on_event = NULL,
                            extra_card_ui = NULL, extra_card_server = NULL) {
  aa_check_sqlite(conn)

  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    version <- shiny::reactiveVal(0)
    card_login <- shiny::reactiveVal(NULL)

    acting_user <- function() shiny::isolate(auth$user())

    emit <- function(event, value = NULL) {
      aa_emit(on_event, event, acting_user()$login, session$token, value)
    }

    notify <- function(text, type = "message") {
      shiny::showNotification(text, type = type)
    }

    # в режиме password_policy = "warn" слабый пароль принимается, но об этом сообщаем
    warn_weak <- function(password, login) {
      weak <- aa_password_warning(password, settings, login)

      if (!is.null(weak)) {
        emit("weak_password_set", paste0(login, ": ", weak$reason))
        notify(weak$text, "warning")
      }
    }

    # администратор по серверному состоянию сессии и по текущим данным базы
    is_admin <- function() {
      acting <- acting_user()

      if (!is.list(acting) || !identical(acting$role, settings$admin_role)) {
        return(FALSE)
      }

      current <- tryCatch(aa_get_user(conn, acting$login), error = function(e) NULL)

      !is.null(current) && identical(current$role, settings$admin_role) &&
        !isTRUE(as.logical(current$blocked))
    }

    require_admin <- function() {
      if (!is_admin()) {
        emit("access_denied", "users")
        notify(aa_text(settings, "access_denied"), "error")
        shiny::req(FALSE)
      }
    }

    # выполняет действие над пользователем, ошибки правил показывает уведомлением
    run_action <- function(action) {
      tryCatch(
        {
          action()
          TRUE
        },
        appauth_error_user = function(e) {
          notify(conditionMessage(e), "error")
          FALSE
        }
      )
    }

    overview <- shiny::reactive({
      version()
      aa_users_overview(conn, settings)
    })

    output$main <- shiny::renderUI({
      auth$user() # зависимость: после входа или выхода интерфейс перерисовывается
      if (!is_admin()) {
        return(NULL)
      }

      shiny::div(
        class = "aa-users",
        shiny::div(
          class = "aa-users-toolbar",
          shiny::h4(aa_text(settings, "users_title"), style = "margin-right: auto;"),
          shiny::actionButton(ns("add"), aa_text(settings, "users_add"), class = "btn btn-success")
        ),
        DT::DTOutput(ns("table")),
        shiny::p(class = "aa-users-hint", aa_text(settings, "users_hint"))
      )
    })

    output$table <- DT::renderDT({
      # после выхода таблица перерисовывается без пользователя: это не отказ в доступе
      shiny::req(auth$user())
      require_admin()
      data <- overview()

      shown <- data.frame(
        data$login, data$role, data$status, data$created, data$last_login, data$state,
        stringsAsFactors = FALSE
      )
      names(shown) <- c(
        aa_text(settings, "col_login"), aa_text(settings, "col_role"),
        aa_text(settings, "col_status"), aa_text(settings, "col_created"),
        aa_text(settings, "col_last_login"), "state"
      )

      DT::datatable(
        shown,
        rownames = FALSE,
        selection = "none",
        class = "compact hover",
        options = list(
          dom = "t",
          paging = FALSE,
          columnDefs = list(list(visible = FALSE, targets = 5)),
          rowCallback = DT::JS(
            "function(row, data) {",
            "  if (data[5] === 'blocked') { $(row).addClass('aa-row-blocked'); }",
            "  else if (data[5] === 'locked') { $(row).addClass('aa-row-locked'); }",
            "}"
          )
        ),
        callback = DT::JS(sprintf(
          "table.on('dblclick', 'tbody tr', function() {
             var d = table.row(this).data();
             if (d) { Shiny.setInputValue('%s', d[0], {priority: 'event'}); }
           });",
          ns("open")
        ))
      )
    })

    # --- карточка пользователя -------------------------------------------------

    show_card <- function(login) {
      user <- aa_get_user(conn, login)
      if (is.null(user)) {
        card_login(NULL)
        shiny::removeModal()
        return(invisible(NULL))
      }

      acting <- acting_user()$login
      email <- aa_get_email(conn, login)
      lock_seconds <- tryCatch(aa_login_lock_remaining(conn, login, settings), error = function(e) 0L)
      is_blocked <- isTRUE(as.logical(user$blocked))
      block_reason <- aa_check_can_block(conn, login, acting, settings)
      delete_reason <- aa_check_can_delete(conn, login, acting, settings)

      card_login(login)

      shiny::showModal(shiny::modalDialog(
        title = aa_text(settings, "card_title", login),
        size = "m",
        easyClose = TRUE,
        footer = shiny::modalButton(aa_text(settings, "button_close")),
        shiny::div(
          class = "aa-card",
          shiny::div(
            shiny::strong(paste0(aa_text(settings, "card_account"), ": ")),
            if (is_blocked) {
              shiny::tagList(
                shiny::span(aa_text(settings, "card_blocked"), class = "aa-status-blocked"), " ",
                shiny::actionButton(ns("unblock"), aa_text(settings, "button_unblock"), class = "btn btn-success btn-sm")
              )
            } else {
              shiny::tagList(
                shiny::span(aa_text(settings, "card_active")), " ",
                if (is.null(block_reason)) {
                  shiny::actionButton(ns("block"), aa_text(settings, "button_block"), class = "btn btn-danger btn-sm")
                }
              )
            }
          ),
          shiny::div(
            shiny::strong(paste0(aa_text(settings, "card_signin"), ": ")),
            if (lock_seconds > 0) {
              shiny::tagList(
                shiny::span(
                  aa_text(settings, "card_signin_locked", max(1L, as.integer(ceiling(lock_seconds / 60)))),
                  class = "aa-status-locked"
                ), " ",
                shiny::actionButton(ns("unlock"), aa_text(settings, "button_unlock"), class = "btn btn-warning btn-sm")
              )
            } else {
              shiny::span(aa_text(settings, "card_signin_ok"))
            }
          ),
          shiny::tags$hr(),
          shiny::div(
            class = "aa-card-section",
            shiny::h5(aa_text(settings, "role_section")),
            shiny::fluidRow(
              shiny::column(8, shiny::selectInput(
                ns("role"), aa_text(settings, "role_label"),
                choices = settings$roles, selected = user$role
              )),
              shiny::column(4, shiny::actionButton(
                ns("change_role"), aa_text(settings, "role_button"),
                class = "btn btn-warning w-100", style = "margin-top: 25px;"
              ))
            )
          ),
          shiny::div(
            class = "aa-card-section",
            shiny::h5(aa_text(settings, "email_section")),
            shiny::fluidRow(
              shiny::column(8, shiny::textInput(
                ns("email"), aa_text(settings, "email_label"),
                value = if (is.na(email)) "" else email,
                placeholder = aa_text(settings, "email_not_set")
              )),
              shiny::column(4, shiny::actionButton(
                ns("save_email"), aa_text(settings, "email_button"),
                class = "btn btn-warning w-100", style = "margin-top: 25px;"
              ))
            )
          ),
          shiny::div(
            class = "aa-card-section",
            shiny::h5(aa_text(settings, "reset_section")),
            shiny::fluidRow(
              shiny::column(4, shiny::passwordInput(ns("new_password"), aa_text(settings, "reset_new_label"))),
              shiny::column(4, shiny::passwordInput(ns("new_password_confirm"), aa_text(settings, "password_confirm_label"))),
              shiny::column(4, shiny::actionButton(
                ns("reset_password"), aa_text(settings, "reset_button"),
                class = "btn btn-warning w-100", style = "margin-top: 25px;"
              ))
            ),
            shiny::checkboxInput(ns("reset_must_change"), aa_text(settings, "must_change_label"), value = settings$must_change_default)
          ),
          shiny::div(
            class = "aa-card-section",
            shiny::actionButton(ns("revoke"), aa_text(settings, "button_revoke"), class = "btn btn-warning btn-sm")
          ),
          if (is.function(extra_card_ui)) extra_card_ui(login, ns),
          if (is.null(delete_reason)) {
            shiny::div(
              class = "aa-card-section aa-card-danger",
              shiny::h5(aa_text(settings, "delete_section"), class = "aa-status-blocked"),
              shiny::p(aa_text(settings, "delete_warning"), class = "aa-login-hint", style = "text-align: left;"),
              shiny::actionButton(ns("delete"), aa_text(settings, "delete_button"), class = "btn btn-danger")
            )
          } else {
            shiny::div(
              class = "aa-card-section",
              shiny::p(aa_text(settings, "delete_unavailable", delete_reason), class = "aa-login-hint", style = "text-align: left; margin: 0;")
            )
          }
        )
      ))

      invisible(NULL)
    }

    shiny::observeEvent(input$open, {
      require_admin()
      shiny::req(aa_is_string(input$open))
      show_card(input$open)
    })

    # цель действия берётся из состояния открытой карточки
    target <- function() {
      login <- card_login()
      shiny::req(aa_is_string(login))
      login
    }

    shiny::observeEvent(input$block, {
      require_admin()
      login <- target()
      if (run_action(function() aa_set_blocked(conn, login, TRUE, acting_user()$login, settings))) {
        emit("user_blocked", login)
        notify(aa_text(settings, "done_blocked", login))
        version(version() + 1)
        show_card(login)
      }
    })

    shiny::observeEvent(input$unblock, {
      require_admin()
      login <- target()
      if (run_action(function() aa_set_blocked(conn, login, FALSE, acting_user()$login, settings))) {
        emit("user_unblocked", login)
        notify(aa_text(settings, "done_unblocked", login))
        version(version() + 1)
        show_card(login)
      }
    })

    shiny::observeEvent(input$unlock, {
      require_admin()
      login <- target()
      aa_clear_attempts(conn, login, settings)
      emit("login_unlocked", login)
      notify(aa_text(settings, "done_unlocked", login))
      version(version() + 1)
      show_card(login)
    })

    shiny::observeEvent(input$change_role, {
      require_admin()
      login <- target()
      role <- input$role
      shiny::req(aa_is_string(role))

      if (run_action(function() aa_set_role(conn, login, role, settings))) {
        emit("user_role_changed", paste0(login, ": ", role))
        notify(aa_text(settings, "done_role_changed", login))
        version(version() + 1)
        show_card(login)
      }
    })

    shiny::observeEvent(input$save_email, {
      require_admin()
      login <- target()
      email <- input$email
      cleared <- !nzchar(aa_normalize_email(email))

      if (run_action(function() aa_set_email(conn, login, email, settings))) {
        emit("email_changed", login)
        notify(aa_text(settings, if (cleared) "done_email_cleared" else "done_email_saved", login))
        show_card(login)
      }
    })

    shiny::observeEvent(input$reset_password, {
      require_admin()
      login <- target()

      if (!identical(input$new_password, input$new_password_confirm)) {
        notify(aa_text(settings, "passwords_mismatch"), "error")
        return()
      }

      must_change <- isTRUE(input$reset_must_change)

      if (run_action(function() aa_set_password(conn, login, input$new_password, settings, must_change = must_change))) {
        emit("password_reset", login)
        notify(aa_text(settings, "done_password_reset", login))
        warn_weak(input$new_password, login)
        shiny::removeModal()
        card_login(NULL)
      }
    })

    shiny::observeEvent(input$revoke, {
      require_admin()
      login <- target()
      aa_revoke_sessions(conn, login)
      emit("sessions_revoked", login)
      notify(aa_text(settings, "done_sessions_revoked", login))
    })

    # удаление необратимо: кнопка в карточке открывает окно подтверждения
    delete_pending <- shiny::reactiveVal(NULL)

    shiny::observeEvent(input$delete, {
      require_admin()
      login <- target()
      delete_pending(login)

      shiny::showModal(shiny::modalDialog(
        title = aa_text(settings, "delete_confirm_title"),
        size = "s",
        easyClose = FALSE,
        footer = shiny::tagList(
          shiny::actionButton(ns("delete_cancel"), aa_text(settings, "button_cancel"), class = "btn btn-default"),
          shiny::actionButton(ns("delete_confirm"), aa_text(settings, "delete_confirm_button"), class = "btn btn-danger")
        ),
        shiny::p(aa_text(settings, "delete_confirm_text", login))
      ))
    })

    shiny::observeEvent(input$delete_cancel, {
      require_admin()
      login <- delete_pending()
      delete_pending(NULL)
      shiny::req(aa_is_string(login))
      show_card(login)
    })

    shiny::observeEvent(input$delete_confirm, {
      require_admin()
      login <- delete_pending()
      # подтверждение действует только для пользователя, которого показали в окне
      shiny::req(aa_is_string(login), identical(login, card_login()))
      delete_pending(NULL)

      if (run_action(function() aa_delete_user(conn, login, acting_user()$login, settings))) {
        emit("user_removed", login)
        notify(aa_text(settings, "done_deleted", login))
        shiny::removeModal()
        card_login(NULL)
        version(version() + 1)
      }
    })

    # --- добавление пользователя -----------------------------------------------

    add_message <- shiny::reactiveVal("")

    shiny::observeEvent(input$add, {
      require_admin()
      add_message("")

      shiny::showModal(shiny::modalDialog(
        title = aa_text(settings, "add_title"),
        size = "s",
        easyClose = TRUE,
        footer = shiny::tagList(
          shiny::modalButton(aa_text(settings, "button_close")),
          shiny::actionButton(ns("add_confirm"), aa_text(settings, "add_button"), class = "btn btn-success")
        ),
        shiny::textInput(ns("new_login"), aa_text(settings, "login_label")),
        shiny::passwordInput(ns("new_user_password"), aa_text(settings, "password_label")),
        shiny::passwordInput(ns("new_user_confirm"), aa_text(settings, "password_confirm_label")),
        shiny::selectInput(
          ns("new_user_role"), aa_text(settings, "role_label"),
          choices = settings$roles,
          # по умолчанию роль без прав администратора, повышать нужно осознанно
          selected = (setdiff(settings$roles, settings$admin_role))[1] %||% settings$roles[1]
        ),
        shiny::textInput(ns("new_user_email"), aa_text(settings, "email_label"), placeholder = aa_text(settings, "email_not_set")),
        shiny::checkboxInput(ns("new_user_must_change"), aa_text(settings, "must_change_label"), value = settings$must_change_default),
        shiny::textOutput(ns("add_message"))
      ))
    })

    output$add_message <- shiny::renderText(add_message())
    shiny::outputOptions(output, "add_message", suspendWhenHidden = FALSE)

    shiny::observeEvent(input$add_confirm, {
      require_admin()

      if (!identical(input$new_user_password, input$new_user_confirm)) {
        add_message(aa_text(settings, "passwords_mismatch"))
        return()
      }

      login <- input$new_login
      role <- input$new_user_role

      created <- tryCatch(
        {
          aa_create_user(conn, login, input$new_user_password, role, settings,
                         must_change = isTRUE(input$new_user_must_change),
                         email = input$new_user_email)
          TRUE
        },
        appauth_error_user = function(e) {
          add_message(conditionMessage(e))
          FALSE
        }
      )

      if (created) {
        emit("user_added", paste0(login, " (", role, ")"))
        notify(aa_text(settings, "done_user_added", login))
        warn_weak(input$new_user_password, login)
        shiny::removeModal()
        version(version() + 1)
      }
    })

    if (is.function(extra_card_server)) {
      extra_card_server(input, output, session, login = card_login)
    }

    list(refresh = function() version(shiny::isolate(version()) + 1))
  })
}
