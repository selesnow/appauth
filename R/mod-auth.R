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
#' @section Вход через Google:
#' При `google_enabled = TRUE` в настройках ([aa_settings()]) на форме входа появляется
#' кнопка «Войти через Google». Пользователь подтверждает вход у Google и возвращается
#' на `google_redirect_uri`; пакет проверяет подпись и содержимое токена Google, домен
#' организации (`google_domains`) и находит пользователя **по email среди уже созданных**:
#' новых пользователей вход не создаёт, роль берётся из базы, заблокированный
#' пользователь не входит. Двухфакторный код приложения при этом не спрашивается
#' (подтверждение делает Google). `state` из адреса сверяется с коротким cookie
#' браузера, начавшего вход, поэтому чужую ссылку возврата подсунуть нельзя. При
#' `password_login = FALSE` форма пароля скрыта, а попытки входа по паролю отклоняются
#' на сервере. Модуль сообщает `login_success` со значением `google` и
#' `google_login_failed` (причина и email в `value`); пользователю при отказе
#' показывается общий текст. Если страница открыта не на адресе
#' `google_redirect_uri` (например, приложение открыто по IP, а возврат настроен на
#' домен), кнопка переводит пользователя на адрес возврата, и вход начинается там сам
#' (параметр `?google=1`): `state` лежит в cookie адреса сайта, а cookie по IP и по домену
#' разные. Вход по паролю и автовход по cookie на каждом адресе работают независимо.
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
    # параметры возврата от Google (code, state), пока ждём cookie браузера для сверки
    google_callback <- shiny::reactiveVal(NULL)
    google_on <- isTRUE(settings$google_enabled)
    # настройки собраны aa_settings(), но на всякий случай отсутствие поля не отключает пароль
    password_on <- !identical(settings$password_login, FALSE)
    oauth_cookie <- paste0(cookie_name, "_oauth")

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
    if (isTRUE(settings$reset_enabled) && password_on) {
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

    # вход через Google ------------------------------------------------------------
    google_fail <- function(reason, email = NULL) {
      message_text(aa_text(settings, aa_google_text_key(reason)))
      emit("google_login_failed", NULL, paste(c(reason, if (aa_is_string(email)) email), collapse = " "))
    }

    if (google_on) {
      # запоминаем state в cookie этого браузера и отправляем его к Google
      start_google <- function() {
        if (!is.null(shiny::isolate(user()))) {
          return()
        }

        started <- tryCatch(
          aa_google_start(conn, settings),
          error = function(e) {
            message("appauth: не удалось начать вход через Google: ", conditionMessage(e))
            NULL
          }
        )

        if (is.null(started)) {
          google_fail("start_failed")
          return()
        }

        message_text("")
        session$sendCustomMessage(
          "appauth_set_cookie",
          list(name = oauth_cookie, token = started$state, days = 600 / 86400)
        )
        aa_redirect(session, started$url, "https://accounts.google.com")
      }

      # кнопка. state лежит в cookie адреса, с которого открыта страница, а Google вернёт
      # пользователя на google_redirect_uri: со страницы на другом адресе (например, по IP) вход
      # нужно начинать на адресе возврата, туда кнопка и переводит (вход стартует там сам)
      shiny::observeEvent(input$google_btn, {
        if (!is.null(shiny::isolate(user()))) {
          return()
        }

        if (!aa_page_matches(session, settings$google_redirect_uri)) {
          message_text("")
          aa_redirect(
            session, aa_google_hop_url(settings),
            aa_origin_string(aa_url_origin(settings$google_redirect_uri))
          )
          return()
        }

        start_google()
      })

      # возврат от Google: ?code=...&state=... (или ?error=... при отказе пользователя)
      shiny::observeEvent(aa_url_search(session), {
        query <- shiny::parseQueryString(aa_url_search(session))
        code <- query[["code"]]
        state <- query[["state"]]

        # переход с кнопки на другом адресе (по IP): начинаем вход сразу, без второго клика.
        # Здесь адрес не сверяется, иначе при неверном определении адреса был бы бесконечный переход
        if (identical(query[["google"]], "1") && !aa_is_string(code) && !aa_is_string(state) &&
            is.null(shiny::isolate(user()))) {
          shiny::updateQueryString("?", mode = "replace", session = session)
          start_google()
          return()
        }

        if (!is.null(shiny::isolate(user())) || !aa_is_string(state) ||
            !(aa_is_string(code) || aa_is_string(query[["error"]]))) {
          return()
        }

        # код и state не должны оставаться в адресной строке
        shiny::updateQueryString("?", mode = "replace", session = session)

        if (!aa_is_string(code)) {
          google_fail("cancelled")
          return()
        }

        google_callback(list(code = code, state = state))
        session$sendCustomMessage("appauth_read_cookie", list(name = oauth_cookie, input = session$ns("oauth_cookie")))
      }, once = TRUE)

      # cookie браузера должен совпасть со state из адреса: так вход заканчивается
      # только в том браузере, который его начал
      shiny::observeEvent(input$oauth_cookie, {
        callback <- shiny::isolate(google_callback())
        shiny::req(callback)
        google_callback(NULL)
        session$sendCustomMessage("appauth_clear_cookie", list(name = oauth_cookie))

        if (!is.null(shiny::isolate(user()))) {
          return()
        }

        if (!aa_is_string(input$oauth_cookie) || !identical(input$oauth_cookie, callback$state)) {
          google_fail("bad_browser")
          return()
        }

        res <- aa_google_complete(conn, settings, callback$code, callback$state)

        if (!isTRUE(res$ok)) {
          google_fail(res$reason, res$email)
          return()
        }

        finish_login(res$login, res$role)
        emit("login_success", res$login, "google")
      }, ignoreNULL = FALSE, ignoreInit = TRUE)
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
          if (password_on) {
            shiny::tagList(
              shiny::textInput(ns("login"), aa_text(settings, "login_label")),
              shiny::passwordInput(ns("password"), aa_text(settings, "password_label")),
              shiny::actionButton(ns("login_btn"), aa_text(settings, "login_button"), class = "aa-login-button")
            )
          },
          if (google_on) {
            shiny::tagList(
              if (password_on) shiny::div(class = "aa-login-or", aa_text(settings, "google_or")),
              shiny::actionButton(
                ns("google_btn"),
                shiny::tagList(aa_google_icon(), aa_text(settings, "google_button")),
                class = "aa-login-button aa-google-button"
              )
            )
          },
          shiny::div(class = "aa-login-message", shiny::textOutput(ns("message"))),
          if (isTRUE(settings$reset_enabled) && password_on) {
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

      # защита на сервере: скрытая форма не заменяет проверку
      if (!password_on) {
        message_text(aa_text(settings, "password_login_disabled"))
        emit("login_failed", NULL, "password_disabled")
        return()
      }

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
      shiny::req(isTRUE(settings$reset_enabled), password_on)
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
      shiny::req(isTRUE(settings$reset_enabled), password_on)

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

#' Значок Google для кнопки входа
#'
#' @returns Элемент интерфейса Shiny (встроенный SVG).
#' @noRd
aa_google_icon <- function() {
  shiny::HTML(paste0(
    '<svg viewBox="0 0 48 48" aria-hidden="true">',
    '<path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>',
    '<path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>',
    '<path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>',
    '<path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>',
    '</svg>'
  ))
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
