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
#' @section Двухфакторная аутентификация:
#' При `totp_enabled = TRUE` в настройках ([aa_settings()]) пользователь, у которого
#' включена 2FA ([aa_totp_server()]), после верного пароля вводит код из
#' приложения-аутентификатора или резервный код. До этого токен автовхода не
#' выдаётся, а успешная попытка входа не записывается: неверные коды считаются
#' неудачными попытками входа, и логин блокируется по тем же правилам, что и при
#' переборе пароля. Вход по cookie автовхода второй фактор не спрашивает (cookie
#' выдан после его прохождения). Модуль сообщает события `totp_failed` и
#' `recovery_code_used`.
#'
#' @section Восстановление пароля по email:
#' При `reset_enabled = TRUE` в настройках ([aa_settings()]) на форме входа
#' появляется ссылка «Забыли пароль?». Пользователь вводит логин или email, ему
#' уходит письмо со ссылкой `<reset_base_url>/?reset=<токен>`, а ответ на экране
#' всегда один и тот же, независимо от того, найден ли пользователь. Модуль сам
#' читает параметр `reset` из адресной строки, убирает его из адреса и показывает
#' форму нового пароля, если ссылка рабочая. После смены пароля пользователь входит
#' как обычно: автоматически его не пускают. Модуль сообщает события
#' `password_reset_requested`, `password_reset_done` и `password_reset_failed`.
#' Логика без интерфейса: [aa_request_password_reset()] и
#' [aa_reset_password_with_token()].
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
#'   [aa_session_guard()]), функция `logout(reason = NULL, reload = FALSE)` и
#'   функция `logout_all(reload = TRUE)`. Без `reason`
#'   это обычный выход (событие `logout`), с `reason` (`"blocked"`, `"deleted"`,
#'   `"role_changed"`, `"token_revoked"`) принудительный (`session_forced_logout`). При
#'   `reload = TRUE` страница перезагружается, чтобы модули прежнего пользователя
#'   исчезли.
#'
#'   `logout_all()` это «выйти на всех устройствах»: отзывает все токены
#'   пользователя (событие `sessions_revoked`) и сразу выходит; открытые сессии на
#'   других устройствах закроет [aa_session_guard()] при ближайшей проверке. Перед
#'   вызовом покажите пользователю окно подтверждения: кнопка выбросит его везде.
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
    # пароль верен, ждём код второго фактора: list(login, role, must_change, old)
    second_factor <- shiny::reactiveVal(NULL)
    # какая форма показана до входа: "login" или "forgot" (запрос ссылки)
    mode <- shiny::reactiveVal("login")
    # токен из ссылки восстановления, по которому показана форма нового пароля
    reset_pending <- shiny::reactiveVal(NULL)

    users_exist <- shiny::reactiveVal(
      tryCatch(aa_users_exist(conn), error = function(e) TRUE)
    )

    emit <- function(event, login = NULL, value = NULL) {
      aa_emit(on_event, event, login, session$token, value)
    }

    # в режиме password_policy = "warn" слабый пароль принимается, но об этом сообщаем
    warn_weak <- function(password, login) {
      weak <- aa_password_warning(password, settings, login)

      if (!is.null(weak)) {
        emit("weak_password_set", login, paste0(login, ": ", weak$reason))
        shiny::showNotification(weak$text, type = "warning")
      }
    }

    finish_login <- function(login, role, issue_token = TRUE) {
      message_text("")
      user(list(login = login, role = role))

      if (issue_token) {
        # вход по паролю (в том числе после обязательной смены пароля и создания
        # первого администратора); вход по cookie дату не обновляет
        aa_touch_last_login(conn, login)

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

    # ссылка восстановления пароля из письма: ?reset=<токен>
    if (isTRUE(settings$reset_enabled)) {
      shiny::observeEvent(aa_url_search(session), {
        token <- shiny::parseQueryString(aa_url_search(session))[["reset"]]

        if (!aa_is_string(token) || !is.null(shiny::isolate(user()))) {
          return()
        }

        # токен не должен оставаться в адресе: он попадёт в историю и закладки
        shiny::updateQueryString("?", mode = "replace", session = session)

        login <- tryCatch(aa_reset_token_login(conn, token), error = function(e) NULL)

        if (is.null(login)) {
          message_text(aa_text(settings, "reset_link_invalid"))
          emit("password_reset_failed")
        } else {
          message_text("")
          reset_pending(token)
        }
      }, once = TRUE)
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

    # выход на всех устройствах: отзываются все токены пользователя (остальные
    # сессии закроет сторож aa_session_guard() при ближайшей проверке) и сразу
    # выходит текущая сессия
    logout_all <- function(reload = TRUE) {
      login <- shiny::isolate(user())$login

      if (!aa_is_string(login)) {
        return(invisible(FALSE))
      }

      try(aa_revoke_sessions(conn, login), silent = TRUE)
      emit("sessions_revoked", login, login)

      logout(reload = reload)
    }

    output$form <- shiny::renderUI({
      if (!is.null(user())) {
        return(NULL)
      }

      ns <- session$ns
      hint <- NULL

      fields <- if (!is.null(second_factor())) {
        heading <- aa_text(settings, "totp_title")
        hint <- shiny::tags$p(class = "aa-login-hint", aa_text(settings, "totp_hint"))
        shiny::tagList(
          shiny::textInput(ns("totp_code"), aa_text(settings, "totp_code_label")),
          shiny::actionButton(ns("totp_btn"), aa_text(settings, "totp_button"), class = "aa-login-button"),
          shiny::div(class = "aa-login-message", shiny::textOutput(ns("message"))),
          shiny::div(class = "aa-login-hint", shiny::actionLink(ns("back_link"), aa_text(settings, "back_to_login")))
        )
      } else if (!is.null(pending())) {
        heading <- aa_text(settings, "must_change_title")
        hint <- shiny::tags$p(class = "aa-login-hint", aa_text(settings, "must_change_hint"))
        shiny::tagList(
          shiny::passwordInput(ns("change_password"), aa_text(settings, "password_new_label")),
          shiny::passwordInput(ns("change_confirm"), aa_text(settings, "password_confirm_label")),
          shiny::actionButton(ns("change_btn"), aa_text(settings, "password_change_button"), class = "aa-login-button"),
          shiny::div(class = "aa-login-message", shiny::textOutput(ns("message")))
        )
      } else if (!is.null(reset_pending())) {
        heading <- aa_text(settings, "reset_title")
        hint <- shiny::tags$p(class = "aa-login-hint", aa_text(settings, "reset_hint"))
        shiny::tagList(
          shiny::passwordInput(ns("reset_password"), aa_text(settings, "password_new_label")),
          shiny::passwordInput(ns("reset_confirm"), aa_text(settings, "password_confirm_label")),
          shiny::actionButton(ns("reset_btn"), aa_text(settings, "reset_save_button"), class = "aa-login-button"),
          shiny::div(class = "aa-login-message", shiny::textOutput(ns("message"))),
          shiny::div(class = "aa-login-hint", shiny::actionLink(ns("back_link"), aa_text(settings, "back_to_login")))
        )
      } else if (users_exist() && identical(mode(), "forgot") && isTRUE(settings$reset_enabled)) {
        heading <- aa_text(settings, "forgot_title")
        hint <- shiny::tags$p(class = "aa-login-hint", aa_text(settings, "forgot_hint"))
        shiny::tagList(
          shiny::textInput(ns("forgot_identifier"), aa_text(settings, "forgot_identifier_label")),
          shiny::actionButton(ns("forgot_btn"), aa_text(settings, "forgot_button"), class = "aa-login-button"),
          shiny::div(class = "aa-login-message", shiny::textOutput(ns("message"))),
          shiny::div(class = "aa-login-hint", shiny::actionLink(ns("back_link"), aa_text(settings, "back_to_login")))
        )
      } else if (users_exist()) {
        heading <- title %||% aa_text(settings, "login_title")
        shiny::tagList(
          shiny::textInput(ns("login"), aa_text(settings, "login_label")),
          shiny::passwordInput(ns("password"), aa_text(settings, "password_label")),
          shiny::actionButton(ns("login_btn"), aa_text(settings, "login_button"), class = "aa-login-button"),
          shiny::div(class = "aa-login-message", shiny::textOutput(ns("message"))),
          if (isTRUE(settings$reset_enabled)) {
            shiny::div(class = "aa-login-hint", shiny::actionLink(ns("forgot_link"), aa_text(settings, "forgot_link")))
          }
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

      if (!is.null(res) && isTRUE(settings$totp_enabled) && aa_totp_enabled(conn, res$login[1])) {
        # пароль верен, но нужен код: успешную попытку не записываем (она обнулила бы
        # счётчик неудач, и код можно было бы подбирать бесконечно), токен не выдаём
        message_text("")
        second_factor(list(
          login = res$login[1], role = res$role[1],
          must_change = isTRUE(res$must_change[1] == 1), old = password
        ))
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
        warn_weak(input$change_password, waiting$login)
        finish_login(waiting$login, waiting$role)
        emit("login_success", waiting$login)
      }
    })

    shiny::observeEvent(input$forgot_link, {
      shiny::req(isTRUE(settings$reset_enabled))
      message_text("")
      mode("forgot")
    })

    shiny::observeEvent(input$back_link, {
      message_text("")
      second_factor(NULL)
      reset_pending(NULL)
      mode("login")
    })

    shiny::observeEvent(input$forgot_btn, {
      shiny::req(isTRUE(settings$reset_enabled))

      res <- tryCatch(
        aa_request_password_reset(conn, input$forgot_identifier, settings),
        error = function(e) {
          message("appauth: не удалось обработать запрос восстановления пароля: ", conditionMessage(e))
          list(reason = "error", login = NA_character_)
        }
      )

      # в журнал уходит причина, пользователю ответ всегда один и тот же
      emit("password_reset_requested", if (is.na(res$login)) NULL else res$login, res$reason)
      message_text(aa_text(settings, "forgot_done", as.integer(round(settings$reset_ttl_minutes))))
    })

    shiny::observeEvent(input$reset_btn, {
      token <- reset_pending()
      shiny::req(token)

      if (!identical(input$reset_password, input$reset_confirm)) {
        message_text(aa_text(settings, "passwords_mismatch"))
        return()
      }

      login <- tryCatch(
        aa_reset_password_with_token(conn, token, input$reset_password, settings),
        appauth_error_user = function(e) {
          message_text(conditionMessage(e))

          # ссылка больше не работает: слабый пароль токен не тратит, остальное да
          if (identical(e$reason, "reset_link_invalid")) {
            reset_pending(NULL)
            mode("login")
            emit("password_reset_failed")
            message_text(conditionMessage(e))
          }

          NULL
        }
      )

      if (!is.null(login)) {
        reset_pending(NULL)
        mode("login")
        emit("password_reset_done", login)
        warn_weak(input$reset_password, login)
        message_text(aa_text(settings, "reset_done"))
      }
    })

    shiny::observeEvent(input$totp_btn, {
      waiting <- second_factor()
      shiny::req(waiting)

      gate <- aa_login_gate(conn, waiting$login, settings)
      if (!gate$allowed) {
        message_text(gate$message)
        emit(if (gate$reason == "throttled") "login_throttled" else "login_locked", waiting$login, gate$seconds)
        return()
      }

      checked <- tryCatch(
        aa_verify_second_factor(conn, waiting$login, input$totp_code, settings),
        error = function(e) {
          message("appauth: не удалось проверить второй фактор: ", conditionMessage(e))
          list(ok = FALSE, method = NA_character_)
        }
      )

      if (!isTRUE(checked$ok)) {
        try(aa_record_attempt(conn, waiting$login, success = FALSE, settings = settings), silent = TRUE)
        emit("totp_failed", waiting$login)

        gate <- aa_login_gate(conn, waiting$login, settings)
        if (!gate$allowed && gate$reason == "locked") {
          # блокировка: начинать нужно с пароля (когда она закончится)
          second_factor(NULL)
          message_text(gate$message)
          emit("login_locked", waiting$login, gate$seconds)
        } else {
          message_text(aa_text(settings, "totp_wrong"))
        }
        return()
      }

      try(aa_record_attempt(conn, waiting$login, success = TRUE, settings = settings), silent = TRUE)
      if (identical(checked$method, "recovery")) {
        emit("recovery_code_used", waiting$login)
      }
      second_factor(NULL)

      if (isTRUE(waiting$must_change)) {
        message_text("")
        pending(list(login = waiting$login, role = waiting$role, old = waiting$old))
        return()
      }

      finish_login(waiting$login, waiting$role)
      emit("login_success", waiting$login)
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
        warn_weak(password, login)
        finish_login(login, settings$admin_role)
      }
    })

    list(
      user = shiny::reactive(user()),
      logged_in = shiny::reactive(!is.null(user())),
      role = shiny::reactive(user()$role),
      logout = logout,
      logout_all = logout_all,
      token = function() current_token
    )
  })
}

#' Строка параметров адреса страницы
#'
#' Вынесено в функцию, чтобы тесты могли подменить адрес: у mock-сессии Shiny
#' адресная строка не настраивается.
#'
#' @param session Сессия модуля.
#'
#' @returns Строка вида `"?reset=abc"` (может быть пустой).
#' @noRd
aa_url_search <- function(session) {
  session$clientData$url_search
}
