# Общие помощники тестов модулей (testthat подключает helper-*.R ко всем файлам).

# Модуль входа через testServer. Пароли хешируются scrypt, поэтому пользователи
# создаются только там, где они нужны.

auth_events <- function() {
  log <- new.env()
  log$events <- list()
  log$hook <- function(event, user, session_id, value) {
    log$events[[length(log$events) + 1]] <- list(event = event, user = user, value = value)
  }
  log$names <- function() vapply(log$events, `[[`, character(1), "event")
  log
}

auth_db <- function(env = parent.frame()) {
  con <- users_db(env)
  aa_create_user(con, "alsey", "secret123", "admin")
  aa_create_user(con, "ivan", "secret123", "user")
  con
}

run_auth <- function(con, expr, settings = aa_settings(), log = auth_events(), ...) {
  rlang::inject(shiny::testServer(
    aa_auth_server,
    args = list(conn = con, settings = settings, on_event = log$hook, ...),
    expr = !!rlang::enquo(expr)
  ))
  invisible(log)
}

form_html <- function(output) paste(as.character(output$form$html), collapse = "")

# Модуль пользователей через testServer. Модальные окна в mock-сессии не
# отображаются, поэтому проверяем действия, их результат в базе и события.

users_events <- function() {
  log <- new.env()
  log$events <- list()
  log$hook <- function(event, user, session_id, value) {
    log$events[[length(log$events) + 1]] <- list(event = event, user = user, value = value)
  }
  log$names <- function() vapply(log$events, `[[`, character(1), "event")
  log
}

# база: два администратора, обычный пользователь, настоящие хеши паролей
users_fixture <- function(env = parent.frame()) {
  con <- users_db(env)
  aa_create_user(con, "alsey", "secret123", "admin")
  aa_create_user(con, "boss", "secret123", "admin")
  aa_create_user(con, "ivan", "secret123", "user")
  con
}

fake_auth <- function(login = "alsey", role = "admin") {
  state <- shiny::reactiveVal(list(login = login, role = role))
  list(user = state)
}

# модуль смены своего пароля через testServer
password_run <- function(con, auth, expr, settings = aa_settings(), log = users_events()) {
  rlang::inject(shiny::testServer(
    aa_password_server,
    args = list(conn = con, auth = auth, settings = settings, on_event = log$hook),
    expr = !!rlang::enquo(expr)
  ))
  invisible(log)
}

run_users <- function(con, expr, auth = fake_auth(), settings = aa_settings(), log = users_events(), ...) {
  rlang::inject(shiny::testServer(
    aa_users_server,
    args = list(conn = con, auth = auth, settings = settings, on_event = log$hook, ...),
    expr = !!rlang::enquo(expr)
  ))
  invisible(log)
}

role_of <- function(con, login) aa_query(con, "SELECT role FROM users WHERE login = ?", params = list(login))$role
blocked_of <- function(con, login) aa_query(con, "SELECT blocked FROM users WHERE login = ?", params = list(login))$blocked

fake_auth_obj <- function(login = "ivan", role = "user") {
  state <- shiny::reactiveVal(if (is.null(login)) NULL else list(login = login, role = role))
  calls <- new.env()
  calls$logout <- list()
  list(
    user = state,
    logged_in = shiny::reactive(!is.null(state())),
    logout = function(reason = NULL, reload = FALSE) {
      calls$logout[[length(calls$logout) + 1]] <- list(reason = reason, reload = reload)
      state(NULL)
    },
    calls = calls
  )
}

with_guard <- function(con, auth, expr, settings = aa_settings(session_check_seconds = 30), ...) {
  rlang::inject(shiny::testServer(
    function(input, output, session) aa_session_guard(auth, con, settings, ...),
    expr = !!rlang::enquo(expr)
  ))
}
