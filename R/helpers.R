#' Подключение к SQLite, которое закрывается вместе с сессией
#'
#' Открывает подключение к базе и сразу регистрирует его закрытие при завершении
#' сессии Shiny. Без этого подключение остаётся открытым до остановки процесса R
#' и держит файл базы: на Windows такой файл нельзя переименовать или удалить.
#'
#' @param db_path Путь к файлу базы SQLite.
#' @param session Сессия Shiny. По умолчанию текущая, поэтому функцию нужно
#'   вызывать внутри `server`.
#' @param prepare Подготовить схему базы ([aa_prepare_db()]) сразу после
#'   подключения.
#' @param settings Настройки, результат [aa_settings()], нужны для `prepare`.
#'
#' @returns Подключение к базе (`SQLiteConnection`).
#' @export
#'
#' @examples
#' \dontrun{
#' server <- function(input, output, session) {
#'   conn <- aa_session_connection("app.db", prepare = TRUE)
#'   auth <- aa_auth_server("auth", conn)
#' }
#' }
aa_session_connection <- function(db_path, session = shiny::getDefaultReactiveDomain(),
                                  prepare = FALSE, settings = aa_settings()) {
  if (!aa_is_string(db_path)) {
    rlang::abort("`db_path` должен быть путём к файлу базы.", class = "appauth_error_connection")
  }

  if (is.null(session) || !is.function(session$onSessionEnded)) {
    rlang::abort(
      "Нужна сессия Shiny: вызывайте функцию внутри `server` или передайте `session`.",
      class = "appauth_error_connection"
    )
  }

  if (!requireNamespace("RSQLite", quietly = TRUE)) {
    rlang::abort("Для работы с базой нужен пакет RSQLite.", class = "appauth_error_connection")
  }

  conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)

  session$onSessionEnded(function() {
    try(DBI::dbDisconnect(conn), silent = TRUE)
  })

  if (isTRUE(prepare)) {
    aa_prepare_db(conn, settings)
  }

  conn
}

#' Принудительно завершать недействительные сессии
#'
#' Раз в `session_check_seconds` (из [aa_settings()]) проверяет открытую сессию
#' ([aa_user_session_valid()]). Если пользователя заблокировали, удалили или
#' сменили ему роль, сессия завершается через `auth$logout()`: хук `on_event`
#' получает `session_forced_logout` с причиной, токены отзываются. Благодаря
#' этому блокировка и понижение роли действуют в течение интервала проверки, а не
#' при следующем входе.
#'
#' Если базу прочитать не удалось, сессия не завершается.
#'
#' @param auth Результат [aa_auth_server()].
#' @param conn Подключение к базе SQLite.
#' @param settings Настройки, результат [aa_settings()].
#' @param reload Перезагружать страницу после выхода, чтобы модули прежнего
#'   пользователя исчезли. Рекомендуется `TRUE`.
#'
#' @returns Невидимо наблюдатель Shiny (его можно остановить через `$destroy()`).
#' @export
#'
#' @examples
#' \dontrun{
#' auth <- aa_auth_server("auth", conn)
#' aa_session_guard(auth, conn)
#' }
aa_session_guard <- function(auth, conn, settings = aa_settings(), reload = TRUE) {
  aa_check_sqlite(conn)

  interval <- max(1, settings$session_check_seconds) * 1000

  invisible(shiny::observe({
    shiny::req(auth$logged_in())
    shiny::invalidateLater(interval)

    usr <- shiny::isolate(auth$user())
    check <- aa_user_session_valid(conn, usr$login, usr$role)

    if (!check$valid) {
      message("appauth: сессия закрыта: ", usr$login, " (", check$reason, ")")
      auth$logout(reason = check$reason, reload = reload)
    }
  }))
}

#' Подключить серверную часть модуля, только если есть право
#'
#' Вызывает `server()` один раз за сессию, когда вошедший пользователь получает
#' право `permission`. Для остальных пользователей серверная часть модуля не
#' регистрируется вообще, а права по-прежнему нужно проверять внутри обработчиков
#' ([aa_require()]): регистрация это защита от лишней работы, а не от подделанных
#' запросов.
#'
#' Зарегистрированные модули нельзя убрать из сессии, поэтому при выходе
#' используйте `auth$logout(reload = TRUE)`: страница перезагрузится и модули
#' прежнего пользователя исчезнут.
#'
#' @param auth Результат [aa_auth_server()].
#' @param permission Название права.
#' @param provider Источник прав, см. [aa_can()].
#' @param server Функция без аргументов, которая регистрирует модуль, например
#'   `function() mod_tasks_server("tasks")`.
#'
#' @returns Невидимо наблюдатель Shiny.
#' @export
#'
#' @examples
#' \dontrun{
#' provider <- aa_permissions_from_matrix(conf$access_managemet)
#' aa_register_module(auth, "Tasks", provider, function() mod_tasks_server("tasks"))
#' }
aa_register_module <- function(auth, permission, provider, server) {
  if (!is.function(server)) {
    rlang::abort("`server` должен быть функцией без аргументов.", class = "appauth_error_permissions")
  }

  started <- FALSE

  invisible(shiny::observe({
    user <- auth$user()

    if (!started && !is.null(user) && aa_can(user, permission, provider)) {
      started <<- TRUE
      shiny::isolate(server())
    }
  }))
}
