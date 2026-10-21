#' Источник прав из матрицы «право -> роли»
#'
#' Создаёт источник прав (`provider`) для [aa_can()] и [aa_require()] по схеме,
#' которая используется в Server Manager: именованный список, где имя это право,
#' а значение это роли, которым оно доступно (вектор или одна строка).
#'
#' Роль администратора не получает прав автоматически: право есть только у тех
#' ролей, которые перечислены в матрице.
#'
#' Если матрица меняется во время работы приложения (редактор прав), передайте
#' функцию без аргументов, которая возвращает актуальную матрицу, например
#' `function() conf_rv()$access_managemet`. Тогда она читается при каждой проверке.
#'
#' Источник прав это любая функция `function(user)`, возвращающая вектор названий
#' прав пользователя. Если матрица вам не подходит (права на пользователя из базы,
#' по группам), напишите такую функцию сами: остальные функции пакета работают с
#' ней одинаково.
#'
#' @param matrix Именованный список «право -> роли» либо функция без аргументов,
#'   возвращающая такой список.
#'
#' @returns Функция `function(user)`: по списку с полем `role` возвращает
#'   названия прав. Для пустой или неизвестной роли возвращает `character(0)`.
#' @export
#'
#' @examples
#' provider <- aa_permissions_from_matrix(list(
#'   Tasks = c("admin", "user", "viewer"),
#'   Access = "admin"
#' ))
#' provider(list(login = "ivan", role = "user"))
#' aa_can(list(login = "ivan", role = "user"), "Access", provider)
aa_permissions_from_matrix <- function(matrix) {
  if (!is.function(matrix)) {
    aa_check_matrix(matrix)
  }
  force(matrix)

  function(user) {
    current <- if (is.function(matrix)) matrix() else matrix
    aa_check_matrix(current)

    role <- if (is.list(user)) user$role else NULL
    if (!aa_is_string(role)) {
      return(character(0))
    }

    has_role <- vapply(
      current,
      function(roles) role %in% as.character(unlist(roles)),
      logical(1)
    )

    names(current)[has_role]
  }
}

aa_check_matrix <- function(matrix, call = rlang::caller_env()) {
  ok <- is.list(matrix) &&
    (length(matrix) == 0 || (!is.null(names(matrix)) && all(nzchar(names(matrix)))))

  if (!ok) {
    rlang::abort(
      "`matrix` должен быть именованным списком вида право -> роли (или функцией, которая его возвращает).",
      class = "appauth_error_permissions",
      call = call
    )
  }

  invisible(matrix)
}

#' Есть ли у пользователя право
#'
#' Серверная проверка права. Скрытие кнопок и вкладок защитой не является,
#' поэтому её нужно вызывать в каждом обработчике действия (см. [aa_require()]).
#'
#' Проверка закрыта по умолчанию: любая неопределённость (пользователя нет,
#' право не строка, источник прав вернул мусор или упал с ошибкой) даёт `FALSE`.
#'
#' @param user Пользователь: список с полями `login` и `role`, например
#'   `auth$user()`. Роль нужно брать из серверного состояния, а не из `input`.
#' @param permission Название права (одна непустая строка).
#' @param provider Источник прав: функция `function(user)`, возвращающая вектор
#'   названий прав, например результат [aa_permissions_from_matrix()].
#'
#' @returns `TRUE` или `FALSE`.
#' @export
#'
#' @examples
#' provider <- aa_permissions_from_matrix(list(Access = "admin"))
#' aa_can(list(login = "root", role = "admin"), "Access", provider)
#' aa_can(list(login = "ivan", role = "user"), "Access", provider)
#' aa_can(NULL, "Access", provider)
aa_can <- function(user, permission, provider) {
  if (!is.function(provider)) {
    rlang::abort(
      "`provider` должен быть функцией `function(user)`, например результатом `aa_permissions_from_matrix()`.",
      class = "appauth_error_permissions"
    )
  }

  if (!is.list(user) || !aa_is_string(permission)) {
    return(FALSE)
  }

  granted <- tryCatch(
    provider(user),
    error = function(e) {
      message("appauth: источник прав завершился ошибкой: ", conditionMessage(e))
      NULL
    }
  )

  if (!is.character(granted)) {
    return(FALSE)
  }

  permission %in% granted
}

#' Требовать право в обработчике действия
#'
#' Вызывается первой строкой обработчика. Если право есть, возвращает `TRUE`.
#' Если нет, сообщает хуку `on_event` событие `access_denied` (в `value`
#' название права), показывает пользователю уведомление и тихо прерывает
#' обработчик через [shiny::req()].
#'
#' @param auth Объект авторизации (список с реактивным значением `user`, как
#'   возвращает модуль входа) либо сам пользователь (список с `login` и `role`).
#' @param permission Название права.
#' @param provider Источник прав, см. [aa_can()].
#' @param on_event Хук событий `function(event, user, session_id, value)` или `NULL`.
#' @param settings Настройки, результат [aa_settings()] (язык текста отказа).
#' @param session_id Идентификатор сессии для хука. По умолчанию берётся из
#'   текущей сессии Shiny.
#'
#' @returns Невидимо `TRUE`. При отсутствии права прерывает обработчик.
#' @export
#'
#' @examples
#' \dontrun{
#' observeEvent(input$run_task, {
#'   aa_require(auth, "Run", provider, on_event = log_event)
#'   # ... действие ...
#' })
#' }
aa_require <- function(auth, permission, provider, on_event = NULL,
                       settings = aa_settings(), session_id = NULL) {
  user <- if (is.list(auth) && is.function(auth$user)) auth$user() else auth

  if (aa_can(user, permission, provider)) {
    return(invisible(TRUE))
  }

  login <- if (is.list(user)) user$login else NULL
  domain <- shiny::getDefaultReactiveDomain()
  if (is.null(session_id) && !is.null(domain)) {
    session_id <- domain$token
  }

  message(
    "appauth: отказано в доступе: пользователь=",
    if (aa_is_string(login)) login else "anonymous",
    ", право=", if (aa_is_string(permission)) permission else "?"
  )
  aa_emit(on_event, "access_denied", login, session_id, permission)

  if (!is.null(domain)) {
    try(
      shiny::showNotification(aa_text(settings, "access_denied"), type = "error"),
      silent = TRUE
    )
  }

  shiny::req(FALSE)
}
