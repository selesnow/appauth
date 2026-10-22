# Модуль входа через testServer. Пароли хешируются scrypt, поэтому пользователи
# создаются только там, где они нужны. Помощники в helper-modules.R.

test_that("при наличии пользователей показывается форма входа, после входа она исчезает", {
  con <- auth_db()

  run_auth(con, {
    session$flushReact()
    html <- form_html(output)
    expect_match(html, "login_btn", fixed = TRUE)
    expect_match(html, "Авторизация", fixed = TRUE)
    expect_false(grepl("setup_btn", html, fixed = TRUE))
    expect_false(logged_in <- session$returned$logged_in())

    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    expect_true(session$returned$logged_in())
    expect_equal(session$returned$user(), list(login = "ivan", role = "user"))
    expect_equal(session$returned$role(), "user")
    expect_true(is.null(output$form$html) || !nzchar(form_html(output)))
  })
})

test_that("успешный вход выдаёт токен, отправляет cookie и событие", {
  con <- auth_db()

  log <- run_auth(con, {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
  })

  expect_equal(log$names(), "login_success")
  expect_equal(log$events[[1]]$user, "ivan")
  expect_equal(count_rows <- nrow(rows_of(con, "auth_sessions")), 1)
  expect_equal(count_attempts(con), 1)
})

test_that("логин берётся из базы, а роль не подменить", {
  con <- auth_db()

  run_auth(con, {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    expect_equal(session$returned$user()$login, "ivan")
    expect_equal(session$returned$user()$role, "user")
  })
})

test_that("неверный пароль: сообщение, событие, попытка записана, вход не выполнен", {
  con <- auth_db()

  log <- run_auth(con, {
    session$setInputs(login = "ivan", password = "wrong-pass", login_btn = 1)
    expect_equal(output$message, "Неверный логин или пароль")
    expect_false(session$returned$logged_in())
  })

  expect_equal(log$names(), "login_failed")
  expect_equal(nrow(rows_of(con, "auth_sessions")), 0)
  expect_equal(count_attempts(con), 1)
})

test_that("несуществующий логин неотличим от неверного пароля", {
  con <- auth_db()

  run_auth(con, {
    session$setInputs(login = "ghost", password = "secret123", login_btn = 1)
    expect_equal(output$message, "Неверный логин или пароль")
  })
})

test_that("пустые поля не вход и не попытка", {
  con <- auth_db()

  log <- run_auth(con, {
    session$setInputs(login = "", password = "", login_btn = 1)
    expect_equal(output$message, "Неверный логин или пароль")
  })

  expect_length(log$events, 0)
  expect_equal(count_attempts(con), 0)
})

test_that("после серии неудач логин блокируется, верный пароль тоже не пускает", {
  con <- auth_db()
  settings <- aa_settings(max_failed_logins = 3)

  log <- run_auth(con, settings = settings, {
    for (i in 1:2) {
      session$setInputs(login = "ivan", password = "bad", login_btn = i)
      expect_equal(output$message, "Неверный логин или пароль")
    }
    session$setInputs(login = "ivan", password = "bad", login_btn = 3)
    expect_match(output$message, "Слишком много неудачных попыток")

    session$setInputs(login = "ivan", password = "secret123", login_btn = 4)
    expect_match(output$message, "Слишком много неудачных попыток")
    expect_false(session$returned$logged_in())
  })

  expect_equal(log$names(), c("login_failed", "login_failed", "login_locked", "login_locked"))
  # попытки во время блокировки не записываются и не продлевают её
  expect_equal(count_attempts(con), 3)
})

test_that("блокировка одного логина не мешает другому, регистр логина различается", {
  con <- auth_db()
  raw_user(con, "Ivan", "user")
  aa_set_password(con, "Ivan", "other-pass1")
  settings <- aa_settings(max_failed_logins = 2)

  run_auth(con, settings = settings, {
    session$setInputs(login = "ivan", password = "bad", login_btn = 1)
    session$setInputs(login = "ivan", password = "bad", login_btn = 2)
    expect_match(output$message, "Слишком много")

    session$setInputs(login = "Ivan", password = "other-pass1", login_btn = 3)
    expect_true(session$returned$logged_in())
    expect_equal(session$returned$user()$login, "Ivan")
  })
})

test_that("общий лимит неудач в минуту останавливает вход", {
  con <- auth_db()
  settings <- aa_settings(max_failed_logins_per_minute = 2, max_failed_logins = 50)

  log <- run_auth(con, settings = settings, {
    session$setInputs(login = "a", password = "x", login_btn = 1)
    session$setInputs(login = "b", password = "x", login_btn = 2)
    session$setInputs(login = "ivan", password = "secret123", login_btn = 3)
    expect_match(output$message, "Слишком много попыток входа")
    expect_false(session$returned$logged_in())
  })

  expect_equal(log$names()[3], "login_throttled")
})

test_that("заблокированный администратором: сообщение только при верном пароле, токена нет", {
  con <- auth_db()
  aa_set_blocked(con, "ivan", TRUE, acting_login = "alsey")

  log <- run_auth(con, {
    session$setInputs(login = "ivan", password = "bad-pass", login_btn = 1)
    expect_equal(output$message, "Неверный логин или пароль")

    session$setInputs(login = "ivan", password = "secret123", login_btn = 2)
    expect_match(output$message, "заблокирована администратором")
    expect_false(session$returned$logged_in())
  })

  expect_equal(log$names(), c("login_failed", "login_blocked_user"))
  expect_equal(nrow(rows_of(con, "auth_sessions")), 0)
})

test_that("успешный вход сбрасывает счётчик неудач", {
  con <- auth_db()
  settings <- aa_settings(max_failed_logins = 3)

  run_auth(con, settings = settings, {
    session$setInputs(login = "ivan", password = "bad", login_btn = 1)
    session$setInputs(login = "ivan", password = "bad", login_btn = 2)
    session$setInputs(login = "ivan", password = "secret123", login_btn = 3)
    expect_true(session$returned$logged_in())
  })

  expect_equal(aa_login_lock_remaining(con, "ivan", settings), 0)
})

test_that("пустая база: форма создания администратора, проверки и создание", {
  con <- users_db()

  log <- run_auth(con, {
    session$flushReact()
    html <- form_html(output)
    expect_match(html, "setup_btn", fixed = TRUE)
    expect_match(html, "Создание администратора", fixed = TRUE)
    expect_false(grepl("login_btn", html, fixed = TRUE))

    session$setInputs(setup_login = "boss", setup_password = "secret123", setup_confirm = "other", setup_btn = 1)
    expect_equal(output$message, "Пароли не совпадают")
    expect_equal(count_users(con), 0)

    session$setInputs(setup_login = "boss", setup_password = "123", setup_confirm = "123", setup_btn = 2)
    expect_match(output$message, "Пароль")
    expect_equal(count_users(con), 0)

    session$setInputs(setup_login = "boss", setup_password = "secret123", setup_confirm = "secret123", setup_btn = 3)
    expect_true(session$returned$logged_in())
    expect_equal(session$returned$user(), list(login = "boss", role = "admin"))
  })

  expect_equal(log$names(), "first_admin_created")
  expect_equal(count_users(con), 1)
  expect_equal(nrow(rows_of(con, "auth_sessions")), 1)
})

test_that("создание администратора не срабатывает, если пользователь уже появился", {
  con <- users_db()

  run_auth(con, {
    session$flushReact()
    aa_create_user(con, "early", "secret123", "admin")
    session$setInputs(setup_login = "late", setup_password = "secret123", setup_confirm = "secret123", setup_btn = 1)
    expect_false(session$returned$logged_in())
  })

  expect_equal(count_users(con), 1)
})

test_that("автовход по cookie работает, токен не перевыдаётся", {
  con <- auth_db()
  token <- aa_issue_token(con, "ivan")

  log <- run_auth(con, {
    session$setInputs(cookie = token)
    expect_true(session$returned$logged_in())
    expect_equal(session$returned$user()$login, "ivan")
  })

  expect_equal(log$names(), "login_success")
  expect_equal(log$events[[1]]$value, "cookie")
  expect_equal(nrow(rows_of(con, "auth_sessions")), 1)
})

test_that("чужой, отозванный и принадлежащий заблокированному токен не пускает", {
  con <- auth_db()
  revoked <- aa_issue_token(con, "ivan")
  aa_revoke_token(con, revoked)
  raw_user(con, "boss", "admin")
  blocked_token <- aa_issue_token(con, "alsey")
  aa_set_blocked(con, "alsey", TRUE, acting_login = "ivan")

  for (token in c("not-a-token", revoked, blocked_token)) {
    run_auth(con, {
      session$setInputs(cookie = token)
      expect_false(session$returned$logged_in())
    })
  }
})

test_that("при выключенном автовходе cookie игнорируется, токены не выдаются", {
  con <- auth_db()
  token <- aa_issue_token(con, "ivan")

  run_auth(con, settings = aa_settings(autologin = FALSE), {
    session$setInputs(cookie = token)
    expect_false(session$returned$logged_in())

    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    expect_true(session$returned$logged_in())
  })

  expect_equal(nrow(rows_of(con, "auth_sessions")), 1)
})

test_that("выход отзывает токен, сбрасывает пользователя и шлёт logout", {
  con <- auth_db()

  log <- run_auth(con, {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    expect_true(session$returned$logged_in())

    session$returned$logout()
    expect_false(session$returned$logged_in())
    expect_null(session$returned$user())
  })

  expect_equal(log$names(), c("login_success", "logout"))
  expect_equal(rows_of(con, "auth_sessions")$revoked, 1)
})

test_that("принудительный выход шлёт session_forced_logout с причиной", {
  con <- auth_db()

  log <- run_auth(con, {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    session$returned$logout(reason = "role_changed")
  })

  expect_equal(log$names(), c("login_success", "session_forced_logout"))
  expect_equal(log$events[[2]]$value, "role_changed")
})

test_that("после выхода cookie больше не работает", {
  con <- auth_db()
  token <- NULL

  run_auth(con, {
    session$setInputs(cookie = aa_issue_token(con, "ivan"))
    token <- rows_of(con, "auth_sessions")$token_hash
    session$returned$logout()
  })

  expect_equal(rows_of(con, "auth_sessions")$revoked, 1)
})

test_that("заголовок и тексты берутся из настроек, логотип и английский язык", {
  con <- auth_db()

  run_auth(con, settings = aa_settings(texts = aa_texts("en")), title = "My App", logo = "logo.png", {
    session$flushReact()
    html <- form_html(output)
    expect_match(html, "My App", fixed = TRUE)
    expect_match(html, "logo.png", fixed = TRUE)
    expect_match(html, "Sign in", fixed = TRUE)
    expect_false(grepl("Авторизация", html, fixed = TRUE))
  })
})

test_that("сбой хука событий не мешает входу", {
  con <- auth_db()
  log <- auth_events()
  log$hook <- function(event, user, session_id, value) stop("лог недоступен")

  suppressMessages(run_auth(con, log = log, {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    expect_true(session$returned$logged_in())
  }))
})
