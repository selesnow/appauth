#' Модуль двухфакторной аутентификации: интерфейс
#'
#' Блок для личного кабинета: статус двухфакторной аутентификации, подключение
#' (секрет, QR-код и подтверждение кодом) и выключение. Ничего не показывает,
#' пока в настройках не включено `totp_enabled`. Стили подключаются через
#' [aa_app_head()].
#'
#' @param id Идентификатор модуля.
#'
#' @returns Элемент интерфейса Shiny.
#' @seealso [aa_totp_server()]
#' @export
#'
#' @examples
#' ui <- shiny::fluidPage(aa_app_head(), aa_totp_ui("totp"))
aa_totp_ui <- function(id) {
  shiny::uiOutput(shiny::NS(id, "main"))
}

#' QR-код для ссылки otpauth
#'
#' Нужен необязательный пакет `qrcode`. Если его нет или построить код не
#' удалось, возвращается `NULL`, и пользователь вводит ключ вручную.
#'
#' @param uri Ссылка `otpauth://`.
#'
#' @returns HTML с SVG или `NULL`.
#' @noRd
aa_totp_qr_html <- function(uri) {
  if (!requireNamespace("qrcode", quietly = TRUE)) {
    return(NULL)
  }

  tryCatch(
    {
      path <- tempfile(fileext = ".svg")
      on.exit(unlink(path), add = TRUE)
      qrcode::generate_svg(qrcode::qr_code(uri), path)
      htmltools::HTML(paste(readLines(path, warn = FALSE), collapse = ""))
    },
    error = function(e) NULL
  )
}

#' Модуль двухфакторной аутентификации: сервер
#'
#' Пользователь сам включает и выключает двухфакторную аутентификацию (TOTP):
#'
#' * **включение**: кнопка создаёт секрет ([aa_totp_setup()]), показывает QR-код
#'   (если установлен пакет `qrcode`) и ключ для ручного ввода, а после ввода кода
#'   из приложения ([aa_totp_enable()]) включает защиту и **один раз** показывает
#'   10 резервных кодов. Остальные сессии пользователя при включении завершаются;
#' * **выключение**: нужны пароль и код (или резервный код), иначе тот, кто
#'   занял открытую сессию, мог бы снять защиту.
#'
#' Неверные коды считаются неудачными попытками входа ([aa_record_attempt()]),
#' поэтому перебор кода в личном кабинете блокирует логин так же, как перебор
#' пароля. События: `totp_enabled`, `totp_disabled`, `totp_failed`.
#'
#' @param id Идентификатор модуля, такой же, как в [aa_totp_ui()].
#' @param conn Подключение к базе SQLite.
#' @param auth Объект авторизации, результат [aa_auth_server()].
#' @param settings Настройки, результат [aa_settings()] с `totp_enabled = TRUE`.
#' @param on_event Хук событий `function(event, user, session_id, value)` или `NULL`.
#'
#' @returns Список с функцией `refresh()`, которая перерисовывает блок.
#' @seealso [aa_totp_ui()], [aa_auth_server()]
#' @export
#'
#' @examples
#' \dontrun{
#' auth <- aa_auth_server("auth", conn, settings)
#' shiny::observe({
#'   if (auth$logged_in()) aa_totp_server("totp", conn, auth, settings, on_event = log_event)
#' })
#' }
aa_totp_server <- function(id, conn, auth, settings = aa_settings(), on_event = NULL) {
  aa_check_sqlite(conn)

  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    version <- shiny::reactiveVal(0)
    enrolling <- shiny::reactiveVal(NULL)
    message_text <- shiny::reactiveVal("")

    acting_login <- function() shiny::isolate(auth$user())$login

    emit <- function(event, value = NULL) {
      aa_emit(on_event, event, acting_login(), session$token, value)
    }

    notify <- function(text, type = "message") {
      shiny::showNotification(text, type = type)
    }

    # перебор кода в личном кабинете блокирует логин так же, как перебор пароля
    gate_open <- function(login) {
      gate <- aa_login_gate(conn, login, settings)

      if (!gate$allowed) {
        message_text(gate$message)
      }

      gate$allowed
    }

    wrong <- function(login) {
      try(aa_record_attempt(conn, login, success = FALSE, settings = settings), silent = TRUE)
      emit("totp_failed")
    }

    output$main <- shiny::renderUI({
      auth$user() # зависимость: после входа или выхода интерфейс перерисовывается
      version()

      login <- acting_login()

      if (!isTRUE(settings$totp_enabled) || !aa_is_string(login)) {
        return(NULL)
      }

      enabled <- aa_totp_enabled(conn, login)

      body <- if (enabled) {
        shiny::tagList(
          shiny::p(
            shiny::span(aa_text(settings, "totp_status_on"), class = "aa-status-ok"), ". ",
            aa_text(settings, "totp_recovery_left", aa_recovery_codes_left(conn, login))
          ),
          shiny::h5(aa_text(settings, "totp_disable_title")),
          shiny::passwordInput(ns("disable_password"), aa_text(settings, "password_label")),
          shiny::textInput(ns("disable_code"), aa_text(settings, "totp_code_label")),
          shiny::actionButton(ns("disable_btn"), aa_text(settings, "totp_disable_button"), class = "btn btn-danger")
        )
      } else if (is.null(enrolling())) {
        shiny::tagList(
          shiny::p(aa_text(settings, "totp_status_off")),
          shiny::actionButton(ns("start"), aa_text(settings, "totp_enable_button"), class = "btn btn-success")
        )
      } else {
        setup <- enrolling()
        qr <- aa_totp_qr_html(setup$uri)

        shiny::tagList(
          shiny::p(class = "aa-login-hint", aa_text(settings, "totp_setup_hint")),
          if (!is.null(qr)) shiny::div(class = "aa-totp-qr", style = "max-width: 220px;", qr),
          shiny::p(
            aa_text(settings, "totp_secret_label"), ": ",
            shiny::tags$code(gsub("(.{4})", "\\1 ", setup$secret))
          ),
          shiny::textInput(ns("code"), aa_text(settings, "totp_code_label")),
          shiny::actionButton(ns("confirm"), aa_text(settings, "totp_confirm_button"), class = "btn btn-success"), " ",
          shiny::actionButton(ns("cancel"), aa_text(settings, "button_cancel"), class = "btn btn-default")
        )
      }

      shiny::div(
        class = "aa-totp",
        shiny::h4(aa_text(settings, "totp_section")),
        body,
        shiny::div(class = "aa-login-message", shiny::textOutput(ns("message")))
      )
    })

    output$message <- shiny::renderText(message_text())
    shiny::outputOptions(output, "message", suspendWhenHidden = FALSE)

    shiny::observeEvent(input$start, {
      login <- acting_login()
      shiny::req(aa_is_string(login))
      message_text("")

      setup <- tryCatch(
        aa_totp_setup(conn, login, settings),
        appauth_error_user = function(e) {
          message_text(conditionMessage(e))
          NULL
        }
      )

      enrolling(setup)
      version(version() + 1)
    })

    shiny::observeEvent(input$cancel, {
      enrolling(NULL)
      message_text("")
      version(version() + 1)
    })

    shiny::observeEvent(input$confirm, {
      login <- acting_login()
      shiny::req(aa_is_string(login), enrolling())
      message_text("")

      if (!gate_open(login)) {
        return()
      }

      codes <- tryCatch(
        aa_totp_enable(conn, login, input$code, settings),
        appauth_error_user = function(e) {
          if (identical(e$reason, "totp_wrong")) wrong(login)
          message_text(conditionMessage(e))
          NULL
        }
      )

      if (is.null(codes)) {
        return()
      }

      # включение 2FA завершает остальные сессии: токен текущей остаётся
      keep <- auth$token()
      aa_revoke_user_tokens(conn, login, keep_hash = if (aa_is_string(keep)) aa_token_hash(keep) else NULL)

      enrolling(NULL)
      emit("totp_enabled")
      notify(aa_text(settings, "done_totp_enabled"))
      version(version() + 1)

      shiny::showModal(shiny::modalDialog(
        title = aa_text(settings, "totp_recovery_title"),
        size = "s",
        easyClose = FALSE,
        footer = shiny::modalButton(aa_text(settings, "button_close")),
        shiny::p(aa_text(settings, "totp_recovery_hint")),
        shiny::tags$pre(class = "aa-totp-codes", paste(codes, collapse = "\n"))
      ))
    })

    shiny::observeEvent(input$disable_btn, {
      login <- acting_login()
      shiny::req(aa_is_string(login))
      message_text("")

      if (!gate_open(login)) {
        return()
      }

      # код проверяется только при верном пароле: иначе чужая попытка тратила бы резервные коды
      password_ok <- !is.null(aa_authenticate(conn, login, input$disable_password))
      code_ok <- password_ok && isTRUE(aa_verify_second_factor(conn, login, input$disable_code, settings)$ok)

      if (!code_ok) {
        wrong(login)
        message_text(aa_text(settings, "totp_disable_wrong"))
        return()
      }

      aa_totp_disable(conn, login)
      emit("totp_disabled")
      notify(aa_text(settings, "done_totp_disabled"))
      version(version() + 1)
    })

    list(refresh = function() version(shiny::isolate(version()) + 1))
  })
}
