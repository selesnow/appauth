# Содержимое карточки пользователя. showModal подменяется, чтобы получить HTML,
# который увидел бы браузер.

capture_card <- function(env = parent.frame()) {
  store <- new.env()
  store$html <- NULL
  testthat::local_mocked_bindings(
    showModal = function(ui, ...) store$html <- paste(as.character(ui), collapse = ""),
    .package = "shiny",
    .env = env
  )
  store
}

card_users <- function(env = parent.frame()) {
  con <- users_db(env)
  raw_user(con, "alsey", "admin")
  raw_user(con, "boss", "admin")
  raw_user(con, "ivan", "user")
  con
}

open_card <- function(con, login, acting = "alsey", ..., prepare = NULL) {
  card <- capture_card(parent.frame())
  if (is.function(prepare)) prepare(con)
  run_users(con, auth = fake_auth(acting, "admin"), ..., {
    session$setInputs(open = login)
  })
  card$html
}

test_that("карточка активного пользователя: действия, роль, пароль, удаление", {
  con <- card_users()
  html <- open_card(con, "ivan")

  expect_match(html, "Карточка пользователя: ivan", fixed = TRUE)
  expect_match(html, "proxy1-block", fixed = TRUE)
  expect_match(html, "proxy1-change_role", fixed = TRUE)
  expect_match(html, "proxy1-reset_password", fixed = TRUE)
  expect_match(html, "proxy1-delete", fixed = TRUE)
  expect_false(grepl("proxy1-unblock", html, fixed = TRUE))
  expect_false(grepl("proxy1-unlock", html, fixed = TRUE))
})

test_that("карточка заблокированного: только разблокировка", {
  con <- card_users()
  html <- open_card(con, "ivan", prepare = function(con) aa_set_blocked(con, "ivan", TRUE, acting_login = "alsey"))

  expect_match(html, "proxy1-unblock", fixed = TRUE)
  expect_false(grepl("proxy1-block\"", html, fixed = TRUE))
  expect_match(html, "заблокирована администратором", fixed = TRUE)
})

test_that("карточка заблокированного по попыткам: кнопка снятия блокировки входа", {
  con <- card_users()
  settings <- aa_settings(max_failed_logins = 2)
  html <- open_card(con, "ivan", settings = settings, prepare = function(con) {
    add_attempt(con, "ivan", FALSE)
    add_attempt(con, "ivan", FALSE)
  })

  expect_match(html, "proxy1-unlock", fixed = TRUE)
  expect_match(html, "заблокирован ещё", fixed = TRUE)
})

test_that("в своей карточке нет кнопок блокировки и удаления, причина удаления показана", {
  con <- card_users()
  html <- open_card(con, "alsey")

  expect_false(grepl("proxy1-block\"", html, fixed = TRUE))
  expect_false(grepl("id=\"proxy1-delete\"", html, fixed = TRUE))
  expect_match(html, "Удаление этого пользователя недоступно", fixed = TRUE)
  expect_match(html, "самого себя", fixed = TRUE)
})

test_that("логин с HTML и скриптами в карточке экранируется", {
  con <- card_users()
  evil <- "<img src=x onerror=alert(1)>"
  html <- open_card(con, evil, prepare = function(con) raw_user(con, evil, "user"))

  expect_false(grepl("<img src=x", html, fixed = TRUE))
  expect_match(html, "&lt;img src=x onerror=alert(1)&gt;", fixed = TRUE)
})

test_that("слот карточки выводится в окне, идентификаторы получают пространство имён", {
  con <- card_users()
  html <- open_card(
    con, "ivan",
    extra_card_ui = function(login, ns) shiny::div(class = "my-extra", shiny::actionButton(ns("my_btn"), paste("Проекты", login)))
  )

  expect_match(html, "my-extra", fixed = TRUE)
  expect_match(html, "Проекты ivan", fixed = TRUE)
  expect_match(html, "-my_btn", fixed = TRUE)
})

test_that("карточка на английском и с переопределённым текстом", {
  con <- card_users()
  html <- open_card(con, "ivan", settings = aa_settings(texts = aa_texts("en", button_block = "Lock account")))

  expect_match(html, "User: ivan", fixed = TRUE)
  expect_match(html, "Lock account", fixed = TRUE)
  expect_false(grepl("Заблокировать", html, fixed = TRUE))
})

test_that("карточка предлагает роли из настроек и выбирает текущую", {
  con <- card_users()
  settings <- aa_settings(roles = c("admin", "editor", "viewer", "user"))
  html <- open_card(con, "ivan", settings = settings)

  expect_match(html, "editor", fixed = TRUE)
  expect_match(html, "<option value=\"user\" selected>", fixed = TRUE)
})

checkbox_checked <- function(html, id) {
  grepl(paste0("<input id=\"", id, "\"[^>]*checked"), html)
}

test_that("галочка временного пароля при сбросе: по умолчанию включена, настройка выключает", {
  con <- card_users()

  html_on <- open_card(con, "ivan")
  html_off <- open_card(con, "ivan", settings = aa_settings(must_change_default = FALSE))

  expect_true(checkbox_checked(html_on, "proxy1-reset_must_change"))
  expect_match(html_off, "proxy1-reset_must_change", fixed = TRUE)
  expect_false(checkbox_checked(html_off, "proxy1-reset_must_change"))
})

test_that("галочка временного пароля в окне добавления зависит от настройки", {
  con <- card_users()
  card <- capture_card()

  run_users(con, {
    session$setInputs(add = 1)
  })
  html_on <- card$html

  run_users(con, settings = aa_settings(must_change_default = FALSE), {
    session$setInputs(add = 2)
  })
  html_off <- card$html

  expect_true(checkbox_checked(html_on, "proxy1-new_user_must_change"))
  expect_match(html_off, "proxy1-new_user_must_change", fixed = TRUE)
  expect_false(checkbox_checked(html_off, "proxy1-new_user_must_change"))
})
