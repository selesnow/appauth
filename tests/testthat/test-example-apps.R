skip_if_not_sqlite()

# Сквозные проверки двух пример-приложений (inst/examples) через testServer:
# каждое приложение запускается целиком, с настоящими модулями и базой SQLite.

example_dir <- function(name) {
  dir <- system.file("examples", name, package = "appauth")
  testthat::skip_if(!nzchar(dir), "примеры недоступны")
  testthat::skip_if_not_installed("RSQLite")
  testthat::skip_if_not_installed("yaml")
  dir
}

# приложение собирается из app.R примера; рабочая папка нужна для config.yaml
example_app <- function(name, env = parent.frame()) {
  dir <- example_dir(name)
  db <- tempfile(fileext = ".db")
  withr::local_envvar(APPAUTH_EXAMPLE_DB = db, .local_envir = env)
  withr::local_dir(dir, .local_envir = env)
  withr::defer(unlink(db), envir = env)
  list(app = shiny::shinyAppDir(dir), db = db)
}

custom_settings <- aa_settings(roles = c("owner", "editor", "viewer"), admin_role = "owner")

html_of <- function(x) paste(as.character(x$html), collapse = "")

db_do <- function(db, fn) {
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con))
  fn(con)
}

db_active_tokens <- function(db, login) {
  db_do(db, function(con) {
    tquery(con, "SELECT COUNT(*) AS n FROM auth_sessions WHERE user_login = ? AND revoked = 0", params = list(login))$n
  })
}

run_app <- function(example, expr) {
  rlang::inject(suppressMessages(shiny::testServer(example$app, expr = !!rlang::enquo(expr))))
}

test_that("minimal-app: первый запуск создаёт администратора, вкладки по правам матрицы", {
  ex <- example_app("minimal-app")

  run_app(ex, {
    session$flushReact()
    expect_match(html_of(output[["auth-form"]]), "setup_btn", fixed = TRUE)

    session$setInputs(
      `auth-setup_login` = "boss", `auth-setup_password` = "secret123",
      `auth-setup_confirm` = "secret123", `auth-setup_btn` = 1
    )
    html <- html_of(output$main)
    expect_match(html, "Задачи", fixed = TRUE)
    expect_match(html, "Запустить задачу", fixed = TRUE)
    expect_match(html, "Доступ", fixed = TRUE)
    expect_match(html, "Сменить пароль", fixed = TRUE)
    expect_match(html, "Выйти на всех устройствах", fixed = TRUE)
  })

  db_do(ex$db, function(con) {
    expect_equal(aa_get_user(con, "boss")$role, "admin")
    expect_true(aa_is_password_hash(tquery(con, "SELECT password FROM users")$password))
  })
})

test_that("minimal-app: роли user и viewer видят разные вкладки и кнопки", {
  ex <- example_app("minimal-app")
  run_app(ex, {
    session$setInputs(`auth-setup_login` = "boss", `auth-setup_password` = "secret123",
                      `auth-setup_confirm` = "secret123", `auth-setup_btn` = 1)
  })
  db_do(ex$db, function(con) {
    aa_create_user(con, "ivan", "secret123", "user")
    aa_create_user(con, "olga", "secret123", "viewer")
  })

  run_app(ex, {
    session$setInputs(`auth-login` = "ivan", `auth-password` = "secret123", `auth-login_btn` = 1)
    html <- html_of(output$main)
    expect_match(html, "Запустить задачу", fixed = TRUE)
    expect_false(grepl("Доступ", html, fixed = TRUE))
  })

  run_app(ex, {
    session$setInputs(`auth-login` = "olga", `auth-password` = "secret123", `auth-login_btn` = 1)
    html <- html_of(output$main)
    expect_match(html, "Задачи", fixed = TRUE)
    expect_false(grepl("Запустить задачу", html, fixed = TRUE))
    expect_false(grepl("Доступ", html, fixed = TRUE))
  })
})

test_that("minimal-app: обработчик защищён на сервере, даже если кнопка скрыта", {
  ex <- example_app("minimal-app")
  run_app(ex, {
    session$setInputs(`auth-setup_login` = "boss", `auth-setup_password` = "secret123",
                      `auth-setup_confirm` = "secret123", `auth-setup_btn` = 1)
  })
  db_do(ex$db, function(con) aa_create_user(con, "olga", "secret123", "viewer"))

  msgs <- character()
  withCallingHandlers(
    shiny::testServer(ex$app, {
      session$setInputs(`auth-login` = "olga", `auth-password` = "secret123", `auth-login_btn` = 1)
      session$setInputs(run = 1)
    }),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )

  expect_true(any(grepl("access_denied user=olga value=Run", msgs, fixed = TRUE)))
  expect_false(any(grepl("Задача запущена", msgs, fixed = TRUE)))
})

test_that("minimal-app: смена пароля в окне и выход на всех устройствах после подтверждения", {
  ex <- example_app("minimal-app")
  run_app(ex, {
    session$setInputs(`auth-setup_login` = "boss", `auth-setup_password` = "secret123",
                      `auth-setup_confirm` = "secret123", `auth-setup_btn` = 1)
  })
  other_device <- NULL
  db_do(ex$db, function(con) other_device <<- aa_issue_token(con, "boss"))

  run_app(ex, {
    session$setInputs(`auth-login` = "boss", `auth-password` = "secret123", `auth-login_btn` = 1)
    expect_match(html_of(output$main), "Сменить пароль", fixed = TRUE)
    session$setInputs(change_password = 1)               # открывает окно со сменой пароля
    session$setInputs(`password-old` = "secret123", `password-new` = "brand-new-1",
                      `password-confirm` = "brand-new-1", `password-change` = 1)

    session$setInputs(logout_all = 1)                   # только окно подтверждения
    expect_true(db_active_tokens(ex$db, "boss") >= 1)
    session$setInputs(logout_all_confirm = 1)           # подтверждение
  })

  expect_equal(db_active_tokens(ex$db, "boss"), 0)
  db_do(ex$db, function(con) {
    expect_null(aa_find_session_user(con, other_device))
    expect_false(is.null(aa_authenticate(con, "boss", "brand-new-1")))
    expect_null(aa_authenticate(con, "boss", "secret123"))
  })
})

test_that("minimal-app: администратор через приложение блокирует пользователя", {
  ex <- example_app("minimal-app")
  run_app(ex, {
    session$setInputs(`auth-setup_login` = "boss", `auth-setup_password` = "secret123",
                      `auth-setup_confirm` = "secret123", `auth-setup_btn` = 1)
  })
  db_do(ex$db, function(con) aa_create_user(con, "ivan", "secret123", "user"))

  run_app(ex, {
    session$setInputs(`auth-login` = "boss", `auth-password` = "secret123", `auth-login_btn` = 1)
    session$flushReact()
    session$setInputs(`users-open` = "ivan")
    session$setInputs(`users-block` = 1)
  })

  db_do(ex$db, function(con) expect_equal(aa_get_user(con, "ivan")$blocked, 1))
})

test_that("custom-permissions-app: свои роли, английский интерфейс, права из базы", {
  ex <- example_app("custom-permissions-app")

  run_app(ex, {
    session$flushReact()
    html <- html_of(output[["auth-form"]])
    expect_match(html, "Create administrator", fixed = TRUE)

    session$setInputs(
      `auth-setup_login` = "boss", `auth-setup_password` = "secret123",
      `auth-setup_confirm` = "secret123", `auth-setup_btn` = 1
    )
    html <- html_of(output$main)
    expect_match(html, "Reports", fixed = TRUE)
    expect_match(html, "Export to CSV", fixed = TRUE)
    expect_match(html, "Users", fixed = TRUE)
    expect_match(html, "Sign out", fixed = TRUE)
  })

  db_do(ex$db, function(con) expect_equal(aa_get_user(con, "boss")$role, "owner"))
})

test_that("custom-permissions-app: права редактора берутся из таблицы, слот карточки их сохраняет", {
  ex <- example_app("custom-permissions-app")
  run_app(ex, {
    session$setInputs(`auth-setup_login` = "boss", `auth-setup_password` = "secret123",
                      `auth-setup_confirm` = "secret123", `auth-setup_btn` = 1)
  })
  db_do(ex$db, function(con) aa_create_user(con, "ann", "secret123", "editor", custom_settings))

  # у редактора пока нет прав
  run_app(ex, {
    session$setInputs(`auth-login` = "ann", `auth-password` = "secret123", `auth-login_btn` = 1)
    html <- html_of(output$main)
    expect_false(grepl("Export to CSV", html, fixed = TRUE))
    expect_false(grepl("Quarterly report", html, fixed = TRUE))
    expect_false(grepl("Users", html, fixed = TRUE))
  })

  # владелец выдаёт право через слот карточки
  run_app(ex, {
    session$setInputs(`auth-login` = "boss", `auth-password` = "secret123", `auth-login_btn` = 1)
    session$flushReact()
    session$setInputs(`users-open` = "ann")
    session$setInputs(`users-permissions` = "export", `users-save_permissions` = 1)
  })
  db_do(ex$db, function(con) {
    expect_equal(tquery(con, "SELECT permission FROM user_permissions WHERE login = 'ann'")$permission, "export")
  })

  run_app(ex, {
    session$setInputs(`auth-login` = "ann", `auth-password` = "secret123", `auth-login_btn` = 1)
    html <- html_of(output$main)
    expect_match(html, "Export to CSV", fixed = TRUE)
    expect_false(grepl("Quarterly report", html, fixed = TRUE))
  })
})

test_that("custom-permissions-app: сохранять права может только владелец", {
  ex <- example_app("custom-permissions-app")
  run_app(ex, {
    session$setInputs(`auth-setup_login` = "boss", `auth-setup_password` = "secret123",
                      `auth-setup_confirm` = "secret123", `auth-setup_btn` = 1)
  })
  db_do(ex$db, function(con) {
    aa_create_user(con, "ann", "secret123", "editor", custom_settings)
    aa_create_user(con, "bob", "secret123", "editor", custom_settings)
  })

  run_app(ex, {
    session$setInputs(`auth-login` = "ann", `auth-password` = "secret123", `auth-login_btn` = 1)
    session$setInputs(`users-open` = "bob")
    session$setInputs(`users-permissions` = c("reports", "export"), `users-save_permissions` = 1)
  })

  db_do(ex$db, function(con) {
    expect_equal(tquery(con, "SELECT COUNT(*) AS n FROM user_permissions")$n, 0)
  })
})

test_that("custom-permissions-app: у редактора без права обработчик экспорта отказывает", {
  ex <- example_app("custom-permissions-app")
  run_app(ex, {
    session$setInputs(`auth-setup_login` = "boss", `auth-setup_password` = "secret123",
                      `auth-setup_confirm` = "secret123", `auth-setup_btn` = 1)
  })
  db_do(ex$db, function(con) aa_create_user(con, "ann", "secret123", "editor", custom_settings))

  msgs <- character()
  withCallingHandlers(
    shiny::testServer(ex$app, {
      session$setInputs(`auth-login` = "ann", `auth-password` = "secret123", `auth-login_btn` = 1)
      session$setInputs(export = 1)
    }),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )

  expect_true(any(grepl("access_denied user=ann value=export", msgs, fixed = TRUE)))
})

test_that("база рекрутинга (старая схема, открытые пароли, root/root) работает с английским интерфейсом", {
  skip_if_not_installed("RSQLite")
  db <- tempfile(fileext = ".db")
  withr::defer(unlink(c(db, paste0(db, ".bak"))))

  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  fixture_recruitment(con)
  DBI::dbDisconnect(con)

  settings <- aa_settings(texts = aa_texts("en"), roles = c("admin", "user", "viewer"))

  # до миграции пароли открытые: вход невозможен ни у кого
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  withr::defer(if (DBI::dbIsValid(con)) DBI::dbDisconnect(con))
  aa_init_db(con)
  expect_null(aa_authenticate(con, "root", "root"))

  weak <- aa_check_default_accounts(con)
  expect_true("root" %in% weak$login)

  DBI::dbDisconnect(con)
  res <- aa_migrate_plaintext_passwords(db, backup = FALSE)
  con <- DBI::dbConnect(RSQLite::SQLite(), db)

  run_auth(con, settings = settings, {
    session$flushReact()
    expect_match(form_html(output), "Sign in", fixed = TRUE)

    session$setInputs(login = "hr_one", password = "wrong", login_btn = 1)
    expect_equal(output$message, "Incorrect login or password")

    session$setInputs(login = "hr_one", password = "secret12", login_btn = 2)
    expect_true(session$returned$logged_in())
    expect_equal(session$returned$user(), list(login = "hr_one", role = "user"))
  })

  expect_true(all(vapply(
    tquery(con, "SELECT password FROM users")$password, aa_is_password_hash, logical(1)
  )))
  expect_true("action_log" %in% DBI::dbListTables(con))
})
