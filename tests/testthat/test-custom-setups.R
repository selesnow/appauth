# Нестандартные настройки: свои роли, своя роль администратора, свои тексты,
# и регрессионные проверки безопасности на уровне модулей.

owner_settings <- aa_settings(roles = c("owner", "editor", "viewer"), admin_role = "owner")

test_that("свои роли: первый администратор получает роль администратора из настроек", {
  con <- users_db()

  expect_true(aa_create_first_admin(con, "boss", "secret123", owner_settings))
  expect_equal(aa_get_user(con, "boss")$role, "owner")
})

test_that("свои роли: создание, смена и отказ для чужих ролей", {
  con <- users_db()
  aa_create_first_admin(con, "boss", "secret123", owner_settings)

  aa_create_user(con, "ann", "secret123", "editor", owner_settings)
  expect_equal(aa_get_user(con, "ann")$role, "editor")
  expect_error(aa_create_user(con, "bob", "secret123", "user", owner_settings), class = "appauth_error_user")
  expect_error(aa_create_user(con, "bob", "secret123", "admin", owner_settings), class = "appauth_error_user")

  aa_set_role(con, "ann", "viewer", owner_settings)
  expect_equal(aa_get_user(con, "ann")$role, "viewer")
  expect_error(aa_set_role(con, "ann", "admin", owner_settings), class = "appauth_error_user")
})

test_that("своя роль администратора: правило последнего администратора работает для неё", {
  con <- users_db()
  aa_create_first_admin(con, "boss", "secret123", owner_settings)
  aa_create_user(con, "ann", "secret123", "editor", owner_settings)

  expect_error(aa_set_role(con, "boss", "editor", owner_settings), class = "appauth_error_user")
  expect_error(aa_delete_user(con, "boss", "ann", owner_settings), class = "appauth_error_user")
  expect_error(aa_set_blocked(con, "boss", TRUE, "ann", owner_settings), class = "appauth_error_user")
})

test_that("модуль входа со своей ролью администратора создаёт owner", {
  con <- users_db()

  run_auth(con, settings = owner_settings, {
    session$setInputs(setup_login = "boss", setup_password = "secret123", setup_confirm = "secret123", setup_btn = 1)
    expect_equal(session$returned$user(), list(login = "boss", role = "owner"))
  })
})

test_that("модуль пользователей: управляет только владелец, роль admin при таких настройках ничего не значит", {
  con <- users_db()
  aa_create_first_admin(con, "boss", "secret123", owner_settings)
  aa_create_user(con, "ann", "secret123", "editor", owner_settings)
  raw_user(con, "fake", "admin")

  run_users(con, auth = fake_auth("fake", "admin"), settings = owner_settings, {
    session$setInputs(open = "ann")
    session$setInputs(block = 1)
  })
  expect_equal(blocked_of(con, "ann"), 0)

  run_users(con, auth = fake_auth("boss", "owner"), settings = owner_settings, {
    session$setInputs(open = "ann")
    session$setInputs(block = 1)
  })
  expect_equal(blocked_of(con, "ann"), 1)
})

test_that("права по матрице работают со своими ролями", {
  provider <- aa_permissions_from_matrix(list(Edit = c("owner", "editor"), Admin = "owner"))

  expect_true(aa_can(list(login = "a", role = "editor"), "Edit", provider))
  expect_false(aa_can(list(login = "a", role = "editor"), "Admin", provider))
  expect_false(aa_can(list(login = "a", role = "admin"), "Admin", provider))
})

test_that("переопределённый текст кнопки входа попадает в форму", {
  con <- users_db()
  aa_create_user(con, "ivan", "secret123", "user")
  settings <- aa_settings(texts = aa_texts("ru", login_button = "Войти в систему", login_title = "Вход для команды"))

  run_auth(con, settings = settings, {
    session$flushReact()
    html <- form_html(output)
    expect_match(html, "Войти в систему", fixed = TRUE)
    expect_match(html, "Вход для команды", fixed = TRUE)
  })
})

test_that("SQL-инъекция в логине и пароле не даёт войти и не ломает базу", {
  con <- users_db()
  aa_create_user(con, "ivan", "secret123", "user")

  for (payload in c("' OR '1'='1", "ivan' --", "x'; DROP TABLE users; --", "\" OR \"\"=\"")) {
    run_auth(con, {
      session$setInputs(login = payload, password = payload, login_btn = 1)
      expect_false(session$returned$logged_in())
    })
    run_auth(con, {
      session$setInputs(login = "ivan", password = payload, login_btn = 1)
      expect_false(session$returned$logged_in())
    })
  }

  expect_true("users" %in% DBI::dbListTables(con))
  expect_equal(count_users(con), 1)
})

test_that("огромный логин и пароль не роняют вход и не раздувают базу попыток", {
  con <- users_db()
  aa_create_user(con, "ivan", "secret123", "user")
  huge <- strrep("a", 50000)

  run_auth(con, {
    session$setInputs(login = huge, password = huge, login_btn = 1)
    expect_equal(output$message, "Неверный логин или пароль")
    expect_false(session$returned$logged_in())
  })

  stored <- DBI::dbGetQuery(con, "SELECT MAX(LENGTH(login)) AS n FROM login_attempts")$n
  expect_lte(stored, aa_settings()$login_max)
})

test_that("пароль, похожий на хеш из базы, не принимается как пароль", {
  con <- users_db()
  aa_create_user(con, "ivan", "secret123", "user")
  hash <- stored_password(con, "ivan")

  run_auth(con, {
    session$setInputs(login = "ivan", password = hash, login_btn = 1)
    expect_false(session$returned$logged_in())
  })
})

test_that("каждое событие каталога реально отправляется кодом пакета", {
  files <- list.files(testthat::test_path("..", "..", "R"), pattern = "\\.R$", full.names = TRUE)
  files <- files[basename(files) != "events.R"]
  skip_if(length(files) == 0, "исходники недоступны (установленный пакет)")

  code <- paste(unlist(lapply(files, readLines, encoding = "UTF-8")), collapse = "\n")

  for (event in aa_events()$event) {
    expect_true(grepl(paste0("\"", event, "\""), code, fixed = TRUE), info = event)
  }
})
