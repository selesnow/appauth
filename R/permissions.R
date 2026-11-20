#' Permission provider from a "permission -> roles" matrix
#'
#' Creates a permission provider (`provider`) for [aa_can()] and [aa_require()]
#' from a named list, where the name is a permission and the value is the roles
#' that hold it (a vector or a single string).
#'
#' The administrator role does not receive permissions automatically: a
#' permission is held only by the roles listed in the matrix.
#'
#' If the matrix changes while the app is running (a permission editor), pass a
#' function without arguments that returns the current matrix, for example
#' `function() conf_rv()$access_matrix`. It is then read on every check.
#'
#' A permission provider is any function `function(user)` that returns a vector
#' of the user's permission names. If a matrix does not suit you (per-user
#' permissions from a database, group-based permissions), write such a function
#' yourself: the other package functions treat it the same way.
#'
#' @param matrix A named list "permission -> roles", or a function without
#'   arguments that returns such a list.
#'
#' @returns A function `function(user)`: for a list with a `role` field it
#'   returns the permission names. For an empty or unknown role it returns
#'   `character(0)`.
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
    (length(matrix) == 0 ||
      (!is.null(names(matrix)) && all(nzchar(names(matrix)))))

  if (!ok) {
    rlang::abort(
      "`matrix` must be a named list of the form permission -> roles (or a function that returns one).",
      class = "appauth_error_permissions",
      call = call
    )
  }

  invisible(matrix)
}

#' Does the user have a permission
#'
#' Server-side permission check. Hiding buttons and tabs is not protection, so
#' call this in every action handler (see [aa_require()]).
#'
#' The check is closed by default: any uncertainty (no user, the permission is
#' not a string, the provider returned garbage or failed with an error) gives
#' `FALSE`.
#'
#' @param user The user: a list with `login` and `role` fields, for example
#'   `auth$user()`. Take the role from server-side state, not from `input`.
#' @param permission Permission name (a single non-empty string).
#' @param provider Permission provider: a function `function(user)` that returns
#'   a vector of permission names, for example the result of
#'   [aa_permissions_from_matrix()].
#'
#' @returns `TRUE` or `FALSE`.
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
      "`provider` must be a function `function(user)`, for example the result of `aa_permissions_from_matrix()`.",
      class = "appauth_error_permissions"
    )
  }

  if (!is.list(user) || !aa_is_string(permission)) {
    return(FALSE)
  }

  granted <- tryCatch(
    provider(user),
    error = function(e) {
      message("appauth: the permission provider failed: ", conditionMessage(e))
      NULL
    }
  )

  if (!is.character(granted)) {
    return(FALSE)
  }

  permission %in% granted
}

#' Require a permission in an action handler
#'
#' Call it on the first line of a handler. If the user has the permission, it
#' returns `TRUE`. If not, it reports an `access_denied` event to the `on_event`
#' hook (the permission name goes into `value`), shows the user a notification
#' and quietly aborts the handler through [shiny::req()].
#'
#' @param auth The authorization object (a list with a reactive `user` value, as
#'   returned by the login module) or the user itself (a list with `login` and
#'   `role`).
#' @param permission Permission name.
#' @param provider Permission provider, see [aa_can()].
#' @param on_event Event hook `function(event, user, session_id, value)` or
#' `NULL`.
#' @param settings Settings, the result of [aa_settings()] (language of the
#'   denial text).
#' @param session_id Session identifier for the hook. By default it is taken
#'   from the current Shiny session.
#'
#' @returns Invisibly `TRUE`. If the permission is missing, aborts the handler.
#' @export
#'
#' @examples
#' \dontrun{
#' observeEvent(input$run_task, {
#'   aa_require(auth, "Run", provider, on_event = log_event)
#'   # ... the action ...
#' })
#' }
aa_require <- function(
  auth,
  permission,
  provider,
  on_event = NULL,
  settings = aa_settings(),
  session_id = NULL
) {
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
    "appauth: access denied: user=",
    if (aa_is_string(login)) login else "anonymous",
    ", permission=",
    if (aa_is_string(permission)) permission else "?"
  )
  aa_emit(on_event, "access_denied", login, session_id, permission)

  if (!is.null(domain)) {
    try(
      shiny::showNotification(
        aa_text(settings, "access_denied"),
        type = "error"
      ),
      silent = TRUE
    )
  }

  shiny::req(FALSE)
}
