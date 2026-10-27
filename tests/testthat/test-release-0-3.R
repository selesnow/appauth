# Возможности версии 0.3.0: даты создания и последнего входа, политика слабых
# паролей, готовый обработчик событий, подтверждение удаления пользователя.

# ---- даты создания и последнего входа ------------------------------------------

test_that("новый пользователь получает created_at (UTC), last_login_at пустая", {
  con <- users_db()
  aa_create_user(con, "ivan", "secret123", "user")

  u <- aa_get_user(con, "ivan")

  expect_named(u, c("login", "role", "blocked", "created_at", "last_login_at"))
  expect_match(u$created_at, "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$")
  expect_lt(abs(as.numeric(difftime(as.POSIXct(u$created_at, tz = "UTC"), Sys.time(), units = "secs"))), 120)
  expect_true(is.na(u$last_login_at))
  expect_named(aa_list_users(con), c("login", "role", "blocked", "created_at", "last_login_at"))
})

test_that("первый администратор тоже получает created_at", {
  con <- users_db()
  aa_create_first_admin(con, "boss", "secret123")

  expect_false(is.na(aa_get_user(con, "boss")$created_at))
})

test_that("миграция достраивает колонки в существующей базе, данные сохраняются", {
  con <- new_db()
  DBI::dbExecute(con, "CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, login TEXT UNIQUE NOT NULL,
                        password TEXT NOT NULL, role TEXT NOT NULL, blocked INTEGER NOT NULL DEFAULT 0)")
  DBI::dbExecute(con, "INSERT INTO users (login, password, role) VALUES ('old', 'x', 'user')")

  # до миграции чтение работает, даты неизвестны
  before <- aa_list_users(con)
  expect_true(is.na(before$created_at) && is.na(before$last_login_at))

  aa_init_db(con)

  expect_true(all(c("created_at", "last_login_at") %in% columns_of(con, "users")))
  after <- aa_get_user(con, "old")
  expect_equal(after$login, "old")
  expect_true(is.na(after$created_at))
  expect_identical(aa_schema_version(con), 8L)
})

test_that("вход по паролю обновляет last_login_at, вход по cookie не обновляет", {
  con <- auth_db()
  token <- aa_issue_token(con, "ivan")

  run_auth(con, {
    session$setInputs(cookie = token)
    expect_true(session$returned$logged_in())
  })
  expect_true(is.na(aa_get_user(con, "ivan")$last_login_at))

  run_auth(con, {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    expect_true(session$returned$logged_in())
  })
  expect_match(aa_get_user(con, "ivan")$last_login_at, "^[0-9]{4}-[0-9]{2}-[0-9]{2} ")
  expect_true(is.na(aa_get_user(con, "alsey")$last_login_at))
})

test_that("неверный пароль last_login_at не меняет", {
  con <- auth_db()

  run_auth(con, {
    session$setInputs(login = "ivan", password = "wrong-pass", login_btn = 1)
  })

  expect_true(is.na(aa_get_user(con, "ivan")$last_login_at))
})

test_that("создание первого администратора через модуль записывает last_login_at", {
  con <- users_db()

  run_auth(con, {
    session$flushReact()
    session$setInputs(setup_login = "boss", setup_password = "secret123", setup_confirm = "secret123", setup_btn = 1)
    expect_true(session$returned$logged_in())
  })

  expect_false(is.na(aa_get_user(con, "boss")$last_login_at))
})

test_that("aa_format_db_time переводит UTC в местное время и подставляет текст для пустых", {
  withr::local_timezone("Asia/Tokyo")

  out <- appauth:::aa_format_db_time(c("2026-01-01 00:00:00", NA, ""), "нет")

  expect_identical(out[2:3], c("нет", "нет"))
  expect_match(out[1], "^2026-01-01 [0-9]{2}:[0-9]{2}$")
  # 9 часов разницы, если часовой пояс из TZ применился; иначе хотя бы формат верен
  if (identical(Sys.timezone(), "Asia/Tokyo")) expect_identical(out[1], "2026-01-01 09:00")
})

test_that("обзор пользователей: даты для показа и тексты для неизвестных дат", {
  con <- users_db()
  raw_user(con, "legacy")
  aa_create_user(con, "fresh", "secret123", "user")
  DBI::dbExecute(con, "UPDATE users SET last_login_at = '2026-03-04 10:20:30' WHERE login = 'fresh'")

  ov <- aa_users_overview(con)

  expect_identical(ov$created[1], "неизвестно")
  expect_identical(ov$last_login[1], "не входил")
  expect_match(ov$created[2], "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$")
  expect_match(ov$last_login[2], "^2026-03-0[34] ")
  expect_identical(ov$last_login_at[2], "2026-03-04 10:20:30")

  en <- aa_users_overview(con, aa_settings(texts = aa_texts("en")))
  expect_identical(en$created[1], "unknown")
  expect_identical(en$last_login[1], "never signed in")
})

# ---- политика слабых паролей ----------------------------------------------------

test_that("настройка password_policy: значение по умолчанию и проверка", {
  expect_identical(aa_settings()$password_policy, "warn")
  expect_identical(aa_settings(password_policy = "reject")$password_policy, "reject")
  expect_identical(aa_settings_from_list(list(password_policy = "off"))$password_policy, "off")

  for (bad in list("strict", NA_character_, 1, c("off", "warn"), NULL, "")) {
    expect_error(aa_settings(password_policy = bad), class = "appauth_error_settings")
  }

  expect_output(print(aa_settings(password_policy = "reject")), "отклоняются")
})

test_that("слабые места пароля: список, логин, один символ, регистр", {
  weak <- appauth:::aa_password_weakness

  expect_identical(weak("123456"), "password_common")
  expect_identical(weak("PassWord"), "password_common")
  expect_identical(weak("Morgan", login = "morgan"), "password_equals_login")
  expect_identical(weak("aaaaaaaa"), "password_repeated")
  expect_identical(weak("morgan", login = "someone"), NULL)
  expect_null(weak("long-and-unusual-phrase"))
  expect_null(weak("long-and-unusual-phrase", login = "ivan"))
  expect_null(weak(NULL))
  expect_null(weak(NA_character_))
})

test_that("off: слабый пароль принимается без предупреждения", {
  s <- aa_settings(password_policy = "off")
  con <- users_db()

  expect_null(aa_validate_password("123456", s))
  expect_null(aa_weak_password_warning("123456", s))
  expect_no_error(aa_create_user(con, "ivan", "123456", "user", s))
})

test_that("warn: пароль принимается, предупреждение даёт текст причины", {
  s <- aa_settings()
  con <- users_db()

  expect_null(aa_validate_password("123456", s))
  expect_no_error(aa_create_user(con, "ivan", "123456", "user", s))
  expect_match(aa_weak_password_warning("123456", s), "слабый.*распространённых")
  expect_match(aa_weak_password_warning("morgan", s, login = "Morgan"), "совпадает с логином")
  expect_match(aa_weak_password_warning("zzzzzz", s), "повторяющегося символа")
  expect_null(aa_weak_password_warning("long-and-unusual-phrase", s))
  expect_match(aa_weak_password_warning("123456", aa_settings(texts = aa_texts("en"))), "weak")
})

test_that("reject: слабый пароль отклоняется при создании, сбросе, смене и первом администраторе", {
  s <- aa_settings(password_policy = "reject")
  con <- users_db()

  expect_error(aa_create_first_admin(con, "boss", "123456", s), class = "appauth_error_user")
  expect_equal(count_users(con), 0)
  expect_true(aa_create_first_admin(con, "boss", "strong-passphrase", s))

  err <- tryCatch(aa_create_user(con, "ivan", "qwerty123", "user", s), appauth_error_user = identity)
  expect_s3_class(err, "appauth_error_user")
  expect_identical(err$reason, "password_common")
  expect_equal(count_users(con), 1)

  err <- tryCatch(aa_create_user(con, "Morgan", "morgan", "user", s), appauth_error_user = identity)
  expect_identical(err$reason, "password_equals_login")

  aa_create_user(con, "ivan", "strong-passphrase", "user", s)
  expect_error(aa_set_password(con, "ivan", "password", s), class = "appauth_error_user")
  expect_error(aa_change_own_password(con, "ivan", "strong-passphrase", "1234567", s), class = "appauth_error_user")
  expect_false(is.null(aa_authenticate(con, "ivan", "strong-passphrase")))

  expect_match(aa_validate_password("123456", s), "распространённых")
  expect_match(aa_validate_password("ivan11", aa_settings(password_policy = "reject", password_min = 4), login = "IVAN11"), "совпадает")
  expect_null(aa_validate_password("long-and-unusual-phrase", s))
})

test_that("правила длины проверяются раньше слабых мест", {
  s <- aa_settings(password_policy = "reject")

  expect_match(aa_validate_password("123", s), "минимум")
})

test_that("модуль пользователей: warn пропускает слабый пароль и сообщает событием", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(add = 1)
    session$setInputs(new_login = "weak1", new_user_password = "123456", new_user_confirm = "123456", new_user_role = "user", add_confirm = 1)
  })

  expect_false(is.null(aa_get_user(con, "weak1")))
  expect_equal(log$names(), c("user_added", "weak_password_set"))
  expect_equal(log$events[[2]]$value, "weak1: password_common")
})

test_that("модуль пользователей: сильный пароль не даёт события о слабом пароле", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(add = 1)
    session$setInputs(new_login = "strong1", new_user_password = "long-and-unusual-phrase", new_user_confirm = "long-and-unusual-phrase", new_user_role = "user", add_confirm = 1)
  })

  expect_equal(log$names(), "user_added")
})

test_that("модуль пользователей: reject отклоняет слабый пароль при добавлении и сбросе", {
  con <- users_fixture()
  s <- aa_settings(password_policy = "reject")

  log <- run_users(con, {
    session$setInputs(add = 1)
    session$setInputs(new_login = "weak1", new_user_password = "123456", new_user_confirm = "123456", new_user_role = "user", add_confirm = 1)
    expect_match(output$add_message, "распространённых")

    session$setInputs(open = "ivan")
    session$setInputs(new_password = "password", new_password_confirm = "password", reset_password = 1)
  }, settings = s)

  expect_null(aa_get_user(con, "weak1"))
  expect_false(is.null(aa_authenticate(con, "ivan", "secret123")))
  expect_length(log$events, 0)
})

test_that("модуль пользователей: сброс пароля на слабый в режиме warn даёт событие", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(new_password = "password", new_password_confirm = "password", reset_password = 1)
  })

  expect_equal(log$names(), c("password_reset", "weak_password_set"))
  expect_equal(log$events[[2]]$value, "ivan: password_common")
})

test_that("модуль входа: слабый пароль первого администратора и смены пароля даёт событие", {
  con <- users_db()

  log <- run_auth(con, {
    session$flushReact()
    session$setInputs(setup_login = "boss", setup_password = "123456", setup_confirm = "123456", setup_btn = 1)
    expect_true(session$returned$logged_in())
  })
  expect_true("weak_password_set" %in% log$names())

  con <- users_db()
  aa_create_user(con, "ann", "secret123", "user", must_change = TRUE)
  log <- run_auth(con, {
    session$setInputs(login = "ann", password = "secret123", login_btn = 1)
    session$setInputs(change_password = "password", change_confirm = "password", change_btn = 1)
    expect_true(session$returned$logged_in())
  })
  expect_true("weak_password_set" %in% log$names())
  expect_equal(log$events[[which(log$names() == "weak_password_set")]]$value, "ann: password_common")
})

test_that("модуль смены пароля: слабый новый пароль в режиме warn принимается и даёт событие", {
  con <- users_db()
  aa_create_user(con, "ann", "secret123", "user")
  auth <- fake_auth("ann", "user")
  auth$token <- function() NULL

  log <- password_run(con, auth, {
    session$flushReact()
    session$setInputs(old = "secret123", new = "123456", confirm = "123456", change = 1)
  })

  expect_equal(log$names(), c("password_changed", "weak_password_set"))
  expect_false(is.null(aa_authenticate(con, "ann", "123456")))
})

# ---- подтверждение удаления пользователя ----------------------------------------

test_that("кнопка «Удалить» только открывает подтверждение, пользователь остаётся", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(delete = 1)
  })

  expect_false(is.null(aa_get_user(con, "ivan")))
  expect_length(log$events, 0)
})

test_that("отмена подтверждения удаления: пользователь остаётся, подтверждение после отмены не работает", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(delete = 1)
    session$setInputs(delete_cancel = 1)
    session$setInputs(delete_confirm = 1)
  })

  expect_false(is.null(aa_get_user(con, "ivan")))
  expect_length(log$events, 0)
})

test_that("подтверждение без нажатия «Удалить» ничего не удаляет (подделанный запрос)", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(delete_confirm = 1)
  })

  expect_equal(count_users(con), 3)
  expect_length(log$events, 0)
})

test_that("подтверждение удаляет только того, для кого показано окно", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(delete = 1)
    session$setInputs(open = "boss") # открыли другую карточку, пока висело окно
    session$setInputs(delete_confirm = 1)
  })

  expect_false(is.null(aa_get_user(con, "ivan")))
  expect_false(is.null(aa_get_user(con, "boss")))
  expect_length(log$events, 0)
})

test_that("подтверждение удаления работает один раз", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(delete = 1)
    session$setInputs(delete_confirm = 1)
    session$setInputs(delete_confirm = 2)
  })

  expect_null(aa_get_user(con, "ivan"))
  expect_equal(log$names(), "user_removed")
})

test_that("не администратор не может подтвердить удаление", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(delete = 1)
    session$setInputs(delete_confirm = 1)
  }, auth = fake_auth("ivan", "user"))

  expect_equal(count_users(con), 3)
  expect_true(all(log$names() == "access_denied"))
})

# ---- готовый обработчик событий ---------------------------------------------------

collect_writer <- function() {
  rows <- new.env()
  rows$items <- list()
  rows$writer <- function(action, user, session_id, value) {
    rows$items[[length(rows$items) + 1]] <- list(action = action, user = user, session_id = session_id, value = value)
  }
  rows
}

test_that("aa_event_logger: без настроек пишет все события под ключами событий", {
  rows <- collect_writer()
  handler <- aa_event_logger(rows$writer)

  handler("login_failed", "boss", "s1", "")
  handler("user_added", "boss", "s1", "olga (user)")

  expect_length(rows$items, 2)
  expect_identical(rows$items[[1]], list(action = "login_failed", user = "boss", session_id = "s1", value = ""))
  expect_identical(rows$items[[2]]$value, "olga (user)")
})

test_that("aa_event_logger: actions переименовывает и отбирает события", {
  rows <- collect_writer()
  handler <- aa_event_logger(rows$writer, actions = c(login_failed = "Login failed", user_added = "User add"))

  handler("login_failed", "boss", "s1", "")
  handler("logout", "boss", "s1", "")
  handler("user_added", "boss", "s1", "x")

  expect_identical(vapply(rows$items, `[[`, "", "action"), c("Login failed", "User add"))
})

test_that("aa_event_logger: events отбирает события, enabled включает и выключает на ходу", {
  rows <- collect_writer()
  on <- TRUE
  handler <- aa_event_logger(rows$writer, events = c("login_failed", "logout"), enabled = function(event) on)

  handler("login_failed", "a", "s", "")
  handler("user_added", "a", "s", "")
  on <- FALSE
  handler("logout", "a", "s", "")
  on <- TRUE
  handler("logout", "a", "s", "")

  expect_identical(vapply(rows$items, `[[`, "", "action"), c("login_failed", "logout"))

  off <- aa_event_logger(rows$writer, enabled = FALSE)
  n <- length(rows$items)
  off("login_failed", "a", "s", "")
  expect_length(rows$items, n)
})

test_that("aa_event_logger: format_value преобразует значение", {
  rows <- collect_writer()
  handler <- aa_event_logger(
    rows$writer,
    format_value = function(event, user, value) if (event == "user_added") sub(" \\(.*\\)$", "", value) else value
  )

  handler("user_added", "boss", "s", "olga (user)")
  handler("user_removed", "boss", "s", "ivan")

  expect_identical(rows$items[[1]]$value, "olga")
  expect_identical(rows$items[[2]]$value, "ivan")
})

test_that("aa_event_logger: ошибки в настройках понятны, неизвестные события ловятся", {
  w <- function(action, user, session_id, value) NULL

  expect_error(aa_event_logger("не функция"), class = "appauth_error_settings")
  expect_error(aa_event_logger(w, actions = c("a", "b")), class = "appauth_error_settings")
  expect_error(aa_event_logger(w, actions = c(no_such_event = "x")), "неизвестные события")
  expect_error(aa_event_logger(w, events = "no_such_event"), "неизвестные события")
  expect_error(aa_event_logger(w, enabled = NA), class = "appauth_error_settings")
  expect_error(aa_event_logger(w, enabled = "yes"), class = "appauth_error_settings")
  expect_error(aa_event_logger(w, format_value = "x"), class = "appauth_error_settings")
})

test_that("aa_event_logger в модуле: сбой записи не прерывает действие пакета", {
  con <- auth_db()
  handler <- aa_event_logger(function(action, user, session_id, value) stop("журнал недоступен"))

  expect_message(
    run_auth(con, {
      session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
      expect_true(session$returned$logged_in())
    }, log = list(hook = handler)),
    "ошибка в on_event"
  )
})

test_that("aa_event_logger работает как on_event у модулей и пишет реальные события", {
  con <- users_fixture()
  rows <- collect_writer()
  handler <- aa_event_logger(rows$writer, actions = c(user_blocked = "User block"))

  run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(block = 1)
  }, log = list(hook = handler))

  expect_length(rows$items, 1)
  expect_identical(rows$items[[1]]$action, "User block")
  expect_identical(rows$items[[1]]$user, "alsey")
  expect_identical(rows$items[[1]]$value, "ivan")
})

test_that("каталог событий содержит weak_password_set", {
  expect_true("weak_password_set" %in% aa_events()$event)
})
