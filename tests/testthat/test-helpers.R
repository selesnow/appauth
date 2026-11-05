test_that("сторож не трогает действующую сессию", {
  con <- users_db()
  raw_user(con, "ivan", "user")
  auth <- fake_auth_obj("ivan", "user")

  with_guard(con, auth, {
    session$flushReact()
    session$elapse(35000)
    session$elapse(35000)
  })

  expect_length(auth$calls$logout, 0)
})

test_that("сторож завершает сессию заблокированного, удалённого и с изменённой ролью", {
  for (case in list(
    list(reason = "blocked", change = function(con) texec(con, "UPDATE users SET blocked = 1 WHERE login = 'ivan'")),
    list(reason = "deleted", change = function(con) texec(con, "DELETE FROM users WHERE login = 'ivan'")),
    list(reason = "role_changed", change = function(con) texec(con, "UPDATE users SET role = 'viewer' WHERE login = 'ivan'"))
  )) {
    con <- users_db()
    raw_user(con, "ivan", "user")
    auth <- fake_auth_obj("ivan", "user")

    with_guard(con, auth, reload = FALSE, {
      session$flushReact()
      case$change(con)
      session$elapse(35000)
    })

    expect_length(auth$calls$logout, 1)
    expect_equal(auth$calls$logout[[1]]$reason, case$reason)
    expect_false(auth$calls$logout[[1]]$reload)
  }
})

test_that("сторож по умолчанию просит перезагрузку страницы", {
  con <- users_db()
  raw_user(con, "ivan", "user", blocked = 1)
  auth <- fake_auth_obj("ivan", "user")

  with_guard(con, auth, {
    session$flushReact()
    session$elapse(35000)
  })

  expect_true(auth$calls$logout[[1]]$reload)
})

test_that("сторож ждёт интервал из настроек", {
  con <- users_db()
  raw_user(con, "ivan", "user")
  auth <- fake_auth_obj("ivan", "user")

  with_guard(con, auth, settings = aa_settings(session_check_seconds = 120), {
    session$flushReact()
    texec(con, "UPDATE users SET blocked = 1 WHERE login = 'ivan'")
    session$elapse(60000)
    expect_length(auth$calls$logout, 0)
    session$elapse(70000)
    expect_length(auth$calls$logout, 1)
  })
})

test_that("сторож при сбое базы сессию не закрывает", {
  con <- users_db()
  raw_user(con, "ivan", "user")
  auth <- fake_auth_obj("ivan", "user")

  with_guard(con, auth, {
    session$flushReact()
    texec(con, "DROP TABLE users")
    session$elapse(35000)
  })

  expect_length(auth$calls$logout, 0)
})

test_that("сторож ничего не делает, пока никто не вошёл", {
  con <- users_db()
  auth <- fake_auth_obj(NULL)

  with_guard(con, auth, {
    session$flushReact()
    session$elapse(35000)
  })

  expect_length(auth$calls$logout, 0)
})

test_that("сторож требует подключение SQLite", {
  expect_error(aa_session_guard(fake_auth_obj(), "не подключение"), class = "appauth_error_connection")
})

test_that("подключение сессии закрывается при её завершении, файл можно удалить", {
  skip_if_not_installed("RSQLite")
  path <- tempfile(fileext = ".db")
  withr::defer(unlink(path))

  ended <- NULL
  fake_session <- list(onSessionEnded = function(f) ended <<- f)

  conn <- aa_session_connection(path, session = fake_session, prepare = TRUE)

  expect_true(DBI::dbIsValid(conn))
  expect_true("users" %in% DBI::dbListTables(conn))
  expect_true(is.function(ended))

  ended()
  expect_false(DBI::dbIsValid(conn))
  expect_true(file.remove(path))
})

test_that("подключение сессии: без сессии и с неверным путём это понятная ошибка", {
  expect_error(aa_session_connection(tempfile(), session = NULL), class = "appauth_error_connection")
  expect_error(aa_session_connection(NULL, session = list(onSessionEnded = function(f) NULL)), class = "appauth_error_connection")
})

test_that("модуль регистрируется один раз и только при наличии права", {
  provider <- aa_permissions_from_matrix(list(Tasks = c("admin", "user"), Access = "admin"))
  counter <- new.env()
  counter$tasks <- 0
  counter$access <- 0
  auth <- fake_auth_obj("olga", "viewer")

  shiny::testServer(
    function(input, output, session) {
      aa_register_module(auth, "Tasks", provider, function() counter$tasks <- counter$tasks + 1)
      aa_register_module(auth, "Access", provider, function() counter$access <- counter$access + 1)
    },
    {
      session$flushReact()
      expect_equal(c(counter$tasks, counter$access), c(0, 0))

      auth$user(list(login = "ivan", role = "user"))
      session$flushReact()
      expect_equal(c(counter$tasks, counter$access), c(1, 0))

      auth$user(list(login = "ivan", role = "user"))
      session$flushReact()
      auth$user(list(login = "boss", role = "admin"))
      session$flushReact()
      expect_equal(c(counter$tasks, counter$access), c(1, 1))
    }
  )
})

test_that("регистрация модуля требует функцию", {
  expect_error(aa_register_module(fake_auth_obj(), "Tasks", function(user) "Tasks", "не функция"),
               class = "appauth_error_permissions")
})
