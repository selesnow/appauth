#' Ready-made event handler for writing to a log
#'
#' The package reports events to the function `on_event(event, user,
#' session_id, value)` (catalog: [aa_events()]). This function builds such a
#' handler from a `writer` function, so that the application does not have to
#' write the same code every time: selecting the events needed, action names
#' for your log, switching writing on and off, and transforming the value.
#'
#' What the handler does for each event:
#'
#' 1. skips the event if it is not in `events` (when `events` is set) or has no
#'    name in `actions` (when `actions` is set);
#' 2. asks `enabled`: if writing is off, writes nothing;
#' 3. determines the action name: from `actions`, and if `actions` is not set,
#'    it is the event key;
#' 4. calls `writer(action, user, session_id, value)`, where `value` has passed
#'    through `format_value(event, user, value)` if that function is set.
#'
#' An error in `writer` does not interrupt a package action (the package
#' catches it and prints a message), so a logging failure does not get in the
#' way of sign-in and of users' work.
#'
#' @param writer Writer function `function(action, user, session_id, value)`:
#'   writes a row to your database, file, messenger, etc. All four arguments are
#'   strings.
#' @param actions A named character vector: the name is an event key from
#'   [aa_events()], the value is the action name in your log. If set, only the
#'   listed events are written. If `NULL`, all events are written and the event
#'   key serves as the action name.
#' @param events A vector of event keys to write. If `NULL`, all are taken (or
#'   those listed in `actions`).
#' @param enabled Whether writing is on: `TRUE`, `FALSE` or a function
#'   `function(event)` that decides by event (for example, by switches from a
#'   config). The function is called on every event, so config changes take
#'   effect immediately.
#' @param format_value An optional function `function(event, user, value)` that
#'   returns the value to write (for example, keeps only the login in `value`).
#'   By default `value` is written as is.
#'
#' @returns A function `function(event, user, session_id, value)` to pass as
#'   `on_event` to the package modules.
#' @export
#'
#' @examples
#' # all events into memory
#' rows <- list()
#' handler <- aa_event_logger(function(action, user, session_id, value) {
#'   rows[[length(rows) + 1]] <<- c(action = action, user = user, value = value)
#' })
#' handler("login_failed", "boss", "s1", "")
#' length(rows)
#'
#' # only selected events with their own action names and a switch
#' log_on <- TRUE
#' handler <- aa_event_logger(
#'   function(action, user, session_id, value) message(action, " ", user),
#'   actions = c(login_failed = "Login failed", user_added = "User add"),
#'   enabled = function(event) log_on
#' )
#' handler("login_failed", "boss", "s1", "")
#' handler("logout", "boss", "s1", "")
aa_event_logger <- function(writer, actions = NULL, events = NULL, enabled = TRUE,
                            format_value = NULL) {
  known <- aa_events()$event

  if (!is.function(writer)) {
    rlang::abort("`writer` must be a function.", class = "appauth_error_settings")
  }

  if (!is.null(actions)) {
    if (!(is.character(actions) && length(actions) >= 1 && !anyNA(actions) &&
          !is.null(names(actions)) && all(nzchar(names(actions))) && all(nzchar(actions)))) {
      rlang::abort(
        "`actions` must be a named character vector: the name is an event key, the value is the action name.",
        class = "appauth_error_settings"
      )
    }

    unknown <- setdiff(names(actions), known)
    if (length(unknown) > 0) {
      rlang::abort(
        paste0("`actions` contains unknown events: ", paste(unknown, collapse = ", "), ". List: aa_events()$event."),
        class = "appauth_error_settings"
      )
    }
  }

  if (!is.null(events)) {
    if (!(is.character(events) && !anyNA(events))) {
      rlang::abort("`events` must be a character vector or `NULL`.", class = "appauth_error_settings")
    }

    unknown <- setdiff(events, known)
    if (length(unknown) > 0) {
      rlang::abort(
        paste0("`events` contains unknown events: ", paste(unknown, collapse = ", "), ". List: aa_events()$event."),
        class = "appauth_error_settings"
      )
    }
  }

  if (!(is.function(enabled) || (is.logical(enabled) && length(enabled) == 1 && !is.na(enabled)))) {
    rlang::abort("`enabled` must be TRUE, FALSE or a function `function(event)`.", class = "appauth_error_settings")
  }

  if (!(is.null(format_value) || is.function(format_value))) {
    rlang::abort("`format_value` must be a function or `NULL`.", class = "appauth_error_settings")
  }

  function(event, user, session_id, value) {
    if (!is.null(events) && !event %in% events) {
      return(invisible(FALSE))
    }

    action <- if (is.null(actions)) event else unname(actions[event])
    if (is.na(action)) {
      return(invisible(FALSE))
    }

    on <- if (is.function(enabled)) enabled(event) else enabled
    if (!isTRUE(on)) {
      return(invisible(FALSE))
    }

    if (is.function(format_value)) {
      value <- format_value(event, user, value)
    }

    writer(action, user, session_id, value)
    invisible(TRUE)
  }
}
