# Восстановление пароля по email: email пользователей, запрос ссылки, смена
# пароля по токену и интерфейс модуля входа. Письма перехватывает ящик mailbox().

mailbox <- function() {
  box <- new.env()
  box$sent <- list()
  box$send <- function(email, link, login) {
    box$sent[[length(box$sent) + 1]] <- list(email = email, link = link, login = login)
  }
  box$token <- function(i = length(box$sent)) {
    sub(".*reset=", "", box$sent[[i]]$link)
  }
  box
}

reset_settings <- function(box, ...) {
  aa_settings(
    reset_enabled  = TRUE,
    reset_base_url = "https://apps.example.com/my_app",
    send_reset     = box$send,
    ...
  )
}

# база: пользователь ann с адресом, bob без адреса
reset_db <- function(env = parent.frame()) {
  con <- users_db(env)
  raw_user(con, "ann", password = aa_hash_password("old-password"))
  raw_user(con, "bob")
  aa_set_email(con, "ann", "Ann@Example.com")
  con
}

# подменяет адресную строку страницы: у mock-сессии Shiny она не настраивается
with_url <- function(search, env = parent.frame()) {
  testthat::local_mocked_bindings(aa_url_search = function(session) search, .package = "appauth", .env = env)
}

reset_tokens_of <- function(con, login) {
  DBI::dbGetQuery(con, "SELECT * FROM password_resets WHERE user_login = ? ORDER BY id", params = list(login))
}

# --- email пользователей ------------------------------------------------------

test_that("aa_set_email хранит адрес в нижнем регистре и удаляет пустым значением", {
  con <- reset_db()

  expect_identical(aa_get_email(con, "ann"), "ann@example.com")
  expect_true(is.na(aa_get_email(con, "bob")))
  expect_true(is.na(aa_get_email(con, "nobody")))

  expect_true(aa_set_email(con, "bob", "  Bob@Example.COM "))
  expect_identical(aa_get_email(con, "bob"), "bob@example.com")

  expect_false(aa_set_email(con, "bob", NULL))
  expect_true(is.na(aa_get_email(con, "bob")))

  aa_set_email(con, "bob", "bob@example.com")
  expect_false(aa_set_email(con, "bob", ""))
  expect_true(is.na(aa_get_email(con, "bob")))
})

test_that("aa_set_email отклоняет неверный формат, занятый адрес и неизвестного пользователя", {
  con <- reset_db()

  for (bad in c("no-at-sign", "a@b", "a b@example.com", "@example.com", "a@@example.com", "a@example.")) {
    expect_error(aa_set_email(con, "bob", bad), class = "appauth_error_user", info = bad)
  }

  err <- tryCatch(aa_set_email(con, "bob", "ANN@example.com"), appauth_error_user = identity)
  expect_s3_class(err, "appauth_error_user")
  expect_identical(err$reason, "email_exists")

  # свой собственный адрес занятым не считается
  expect_true(aa_set_email(con, "ann", "ann@example.com"))

  err <- tryCatch(aa_set_email(con, "nobody", "x@example.com"), appauth_error_user = identity)
  expect_identical(err$reason, "user_not_found")

  expect_true(is.na(aa_get_email(con, "bob")))
})

test_that("aa_create_user принимает email и проверяет его до создания пользователя", {
  con <- reset_db()

  aa_create_user(con, "carl", "secret123", "user", email = "Carl@Example.com")
  expect_identical(aa_get_email(con, "carl"), "carl@example.com")

  expect_error(aa_create_user(con, "dina", "secret123", "user", email = "broken"), class = "appauth_error_user")
  expect_error(aa_create_user(con, "dina", "secret123", "user", email = "ann@example.com"), class = "appauth_error_user")
  expect_null(aa_get_user(con, "dina"))

  aa_create_user(con, "erik", "secret123", "user", email = "")
  expect_true(is.na(aa_get_email(con, "erik")))
})

# --- настройки ------------------------------------------------------------------

test_that("настройки восстановления: по умолчанию выключено, включение требует функцию и адрес", {
  s <- aa_settings()
  expect_false(s$reset_enabled)
  expect_null(s$send_reset)
  expect_equal(s$reset_ttl_minutes, 60)
  expect_equal(s$reset_max_per_hour, 3)

  expect_error(aa_settings(reset_enabled = TRUE), class = "appauth_error_settings")
  expect_error(aa_settings(reset_enabled = TRUE, send_reset = function(email, link, login) NULL), class = "appauth_error_settings")
  expect_error(aa_settings(reset_enabled = TRUE, reset_base_url = "https://x.test"), class = "appauth_error_settings")
  expect_error(aa_settings(send_reset = "mail"), class = "appauth_error_settings")
  expect_error(aa_settings(reset_base_url = 1), class = "appauth_error_settings")
  expect_error(aa_settings(reset_ttl_minutes = 0), class = "appauth_error_settings")
  expect_error(aa_settings(reset_max_per_hour = -1), class = "appauth_error_settings")

  ok <- reset_settings(mailbox())
  expect_true(ok$reset_enabled)
  expect_output(print(ok), "Восстановление пароля по email: включено")
  expect_output(print(s), "Восстановление пароля по email: выключено")
})

test_that("aa_settings_from_list понимает настройки восстановления", {
  s <- aa_settings_from_list(list(reset_ttl_minutes = 15, reset_max_per_hour = 1))
  expect_equal(s$reset_ttl_minutes, 15)
  expect_equal(s$reset_max_per_hour, 1)
})

# --- запрос ссылки --------------------------------------------------------------

test_that("запрос по логину и по email отправляет письмо со ссылкой и хранит только хеш", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)

  res <- aa_request_password_reset(con, "ann", settings)
  expect_true(res$sent)
  expect_identical(res$reason, "sent")
  expect_identical(res$login, "ann")

  expect_length(box$sent, 1)
  expect_identical(box$sent[[1]]$email, "ann@example.com")
  expect_identical(box$sent[[1]]$login, "ann")
  expect_match(box$sent[[1]]$link, "^https://apps\\.example\\.com/my_app/\\?reset=[0-9a-f]{64}$")

  rows <- reset_tokens_of(con, "ann")
  expect_equal(nrow(rows), 1)
  expect_false(grepl(box$token(), paste(unlist(rows), collapse = " "), fixed = TRUE))
  expect_identical(rows$token_hash, aa_token_hash(box$token()))
  expect_equal(rows$used, 0)

  # адрес вводится в любом регистре и с пробелами
  res <- aa_request_password_reset(con, "  ANN@example.com ", settings)
  expect_true(res$sent)
  expect_identical(res$login, "ann")
  expect_length(box$sent, 2)
})

test_that("ссылка строится от адреса приложения с завершающим слэшем и с параметрами", {
  con <- reset_db()
  box <- mailbox()

  aa_request_password_reset(con, "ann", aa_settings(
    reset_enabled = TRUE, send_reset = box$send, reset_base_url = "https://apps.example.com/app/"
  ))
  expect_match(box$sent[[1]]$link, "^https://apps\\.example\\.com/app/\\?reset=")

  aa_request_password_reset(con, "ann", aa_settings(
    reset_enabled = TRUE, send_reset = box$send, reset_base_url = "https://apps.example.com/?app=1"
  ))
  expect_match(box$sent[[2]]$link, "^https://apps\\.example\\.com/\\?app=1&reset=")
})

test_that("письмо не уходит, если пользователя нет, нет адреса, пользователь заблокирован или функция выключена", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)

  expect_identical(aa_request_password_reset(con, "nobody", settings)$reason, "no_user")
  expect_identical(aa_request_password_reset(con, "nobody@example.com", settings)$reason, "no_user")
  expect_identical(aa_request_password_reset(con, "", settings)$reason, "no_user")
  expect_identical(aa_request_password_reset(con, NULL, settings)$reason, "no_user")
  expect_identical(aa_request_password_reset(con, "bob", settings)$reason, "no_email")

  aa_set_blocked(con, "ann", TRUE)
  expect_identical(aa_request_password_reset(con, "ann", settings)$reason, "blocked")

  expect_identical(aa_request_password_reset(con, "ann", aa_settings())$reason, "disabled")

  expect_length(box$sent, 0)
  expect_equal(nrow(reset_tokens_of(con, "ann")), 0)
})

test_that("новый запрос гасит предыдущую ссылку", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)

  aa_request_password_reset(con, "ann", settings)
  aa_request_password_reset(con, "ann", settings)

  expect_null(aa_reset_token_login(con, box$token(1)))
  expect_identical(aa_reset_token_login(con, box$token(2)), "ann")
})

test_that("лимиты: на пользователя в час и общий в минуту", {
  con <- reset_db()
  box <- mailbox()

  settings <- reset_settings(box, reset_max_per_hour = 2)
  expect_true(aa_request_password_reset(con, "ann", settings)$sent)
  expect_true(aa_request_password_reset(con, "ann", settings)$sent)
  res <- aa_request_password_reset(con, "ann", settings)
  expect_false(res$sent)
  expect_identical(res$reason, "throttled")
  expect_length(box$sent, 2)

  # запросы старше часа в лимит не входят
  DBI::dbExecute(con, "UPDATE password_resets SET created_at = datetime('now', '-2 hours')")
  expect_true(aa_request_password_reset(con, "ann", settings)$sent)

  # общий лимит по всем пользователям
  con <- reset_db()
  aa_set_email(con, "bob", "bob@example.com")
  box <- mailbox()
  settings <- reset_settings(box, reset_max_per_minute = 1)
  expect_true(aa_request_password_reset(con, "ann", settings)$sent)
  expect_identical(aa_request_password_reset(con, "bob", settings)$reason, "throttled")
})

test_that("ошибка отправки письма не прерывает запрос и гасит токен", {
  con <- reset_db()
  settings <- aa_settings(
    reset_enabled = TRUE, reset_base_url = "https://x.test",
    send_reset = function(email, link, login) stop("smtp is down")
  )

  expect_message(res <- aa_request_password_reset(con, "ann", settings), "smtp is down")
  expect_false(res$sent)
  expect_identical(res$reason, "send_failed")
  expect_equal(reset_tokens_of(con, "ann")$used, 1)
})

# --- смена пароля по ссылке -----------------------------------------------------

test_that("смена пароля по ссылке: пароль меняется, вход работает, токен одноразовый", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)
  aa_request_password_reset(con, "ann", settings)
  token <- box$token()

  expect_identical(aa_reset_token_login(con, token), "ann")
  expect_identical(aa_reset_password_with_token(con, token, "brand-new-pass", settings), "ann")

  expect_null(aa_authenticate(con, "ann", "old-password"))
  expect_equal(aa_authenticate(con, "ann", "brand-new-pass")$login, "ann")

  expect_null(aa_reset_token_login(con, token))
  err <- tryCatch(aa_reset_password_with_token(con, token, "another-pass-1", settings), appauth_error_user = identity)
  expect_identical(err$reason, "reset_link_invalid")
  expect_null(aa_authenticate(con, "ann", "another-pass-1"))
})

test_that("после смены по ссылке отзываются сессии, гасятся другие ссылки, снимаются блокировка и must_change", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)

  session_token <- aa_issue_token(con, "ann")
  DBI::dbExecute(con, "UPDATE users SET must_change = 1 WHERE login = 'ann'")
  for (i in 1:5) aa_record_attempt(con, "ann", FALSE, settings)
  expect_gt(aa_login_lock_remaining(con, "ann", settings), 0)

  aa_request_password_reset(con, "ann", settings)
  # вторая ссылка гасит первую, поэтому имитируем две живые ссылки вручную
  DBI::dbExecute(
    con, "INSERT INTO password_resets (user_login, token_hash, expires_at) VALUES ('ann', 'other', datetime('now', '+1 hours'))"
  )

  aa_reset_password_with_token(con, box$token(), "brand-new-pass", settings)

  expect_null(aa_find_session_user(con, session_token))
  expect_true(all(reset_tokens_of(con, "ann")$used == 1))
  expect_equal(aa_login_lock_remaining(con, "ann", settings), 0)
  expect_equal(aa_authenticate(con, "ann", "brand-new-pass")$must_change, 0)
})

test_that("неверный, просроченный и чужой токен не меняют пароль", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)
  aa_request_password_reset(con, "ann", settings)
  token <- box$token()

  for (bad in list(NULL, NA_character_, "", "abc", strrep("0", 64), toupper(token))) {
    expect_error(aa_reset_password_with_token(con, bad, "brand-new-pass", settings), class = "appauth_error_user")
  }

  DBI::dbExecute(con, "UPDATE password_resets SET expires_at = datetime('now', '-1 minutes')")
  expect_null(aa_reset_token_login(con, token))
  err <- tryCatch(aa_reset_password_with_token(con, token, "brand-new-pass", settings), appauth_error_user = identity)
  expect_identical(err$reason, "reset_link_invalid")

  expect_equal(aa_authenticate(con, "ann", "old-password")$login, "ann")
})

test_that("слабый пароль отклоняется без траты токена", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box, password_policy = "reject")
  aa_request_password_reset(con, "ann", settings)
  token <- box$token()

  expect_error(aa_reset_password_with_token(con, token, "short", settings), class = "appauth_error_user")
  expect_error(aa_reset_password_with_token(con, token, "password", settings), class = "appauth_error_user")
  expect_identical(aa_reset_token_login(con, token), "ann")

  expect_identical(aa_reset_password_with_token(con, token, "brand-new-pass", settings), "ann")
})

test_that("токен заблокированного или удалённого пользователя не работает", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)
  aa_request_password_reset(con, "ann", settings)
  token <- box$token()

  aa_set_blocked(con, "ann", TRUE)
  expect_null(aa_reset_token_login(con, token))
  expect_error(aa_reset_password_with_token(con, token, "brand-new-pass", settings), class = "appauth_error_user")

  aa_set_blocked(con, "ann", FALSE)
  expect_identical(aa_reset_token_login(con, token), "ann")

  aa_delete_user(con, "ann")
  expect_equal(nrow(reset_tokens_of(con, "ann")), 0)
  expect_null(aa_reset_token_login(con, token))
})

test_that("сброс пароля администратором и смена пароля гасят ссылки восстановления", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)

  aa_request_password_reset(con, "ann", settings)
  aa_set_password(con, "ann", "admin-chosen-1", settings)
  expect_null(aa_reset_token_login(con, box$token()))
})

test_that("aa_cleanup удаляет старые токены восстановления и оставляет свежие", {
  con <- reset_db()
  DBI::dbExecute(con, "
    INSERT INTO password_resets (user_login, token_hash, created_at, expires_at, used) VALUES
      ('ann', 'old_expired', datetime('now', '-3 days'), datetime('now', '-3 days', '+1 hours'), 0),
      ('ann', 'old_used',    datetime('now', '-3 days'), datetime('now', '+1 hours'),            1),
      ('ann', 'fresh_used',  datetime('now'),            datetime('now', '+1 hours'),            1),
      ('ann', 'fresh',       datetime('now'),            datetime('now', '+1 hours'),            0)")

  res <- aa_cleanup(con)

  expect_identical(res$password_resets, 2L)
  expect_identical(sort(reset_tokens_of(con, "ann")$token_hash), c("fresh", "fresh_used"))
})

test_that("миграция 7 достраивает старую базу и не трогает пользователей", {
  con <- new_db()
  fixture_server_manager_prod(con)
  before <- rows_of(con, "users")

  res <- aa_init_db(con)

  expect_true(7L %in% res$applied)
  expect_true("email" %in% columns_of(con, "users"))
  expect_true("password_resets" %in% table_names(con))
  expect_identical(rows_of(con, "users")[, names(before)], before)
  expect_true(all(is.na(rows_of(con, "users")$email)))

  # повторный запуск ничего не меняет
  expect_identical(aa_init_db(con)$applied, integer())
})

test_that("на уровне базы адрес уникален, но у многих пользователей может не быть адреса", {
  con <- reset_db()
  raw_user(con, "carl")

  expect_error(DBI::dbExecute(con, "UPDATE users SET email = 'ann@example.com' WHERE login = 'bob'"), "UNIQUE")
  expect_no_error(DBI::dbExecute(con, "UPDATE users SET email = NULL"))
})

# --- модуль входа ----------------------------------------------------------------

test_that("ссылка «Забыли пароль?» есть только при включённом восстановлении", {
  con <- reset_db()

  run_auth(con, {
    session$flushReact()
    expect_false(grepl("forgot_link", form_html(output), fixed = TRUE))
  })

  box <- mailbox()
  run_auth(con, settings = reset_settings(box), {
    session$flushReact()
    expect_true(grepl("forgot_link", form_html(output), fixed = TRUE))
  })
})

test_that("модуль: запрос ссылки показывает один ответ для найденного и ненайденного пользователя", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)
  log <- auth_events()

  run_auth(con, settings = settings, log = log, {
    session$setInputs(forgot_link = 1)
    session$flushReact()
    expect_true(grepl("forgot_identifier", form_html(output), fixed = TRUE))

    session$setInputs(forgot_identifier = "ann", forgot_btn = 1)
    found <- output$message

    session$setInputs(forgot_identifier = "ghost", forgot_btn = 2)
    missing <- output$message

    expect_identical(found, missing)
    expect_match(found, "60 мин")

    session$setInputs(forgot_identifier = "bob", forgot_btn = 3)
    expect_identical(output$message, found)
  })

  expect_length(box$sent, 1)
  expect_identical(
    vapply(log$events, `[[`, character(1), "value"),
    c("sent", "no_user", "no_email")
  )
  expect_identical(vapply(log$events, `[[`, character(1), "user"), c("ann", "anonymous", "bob"))
  expect_true(all(log$names() == "password_reset_requested"))
})

test_that("модуль: ссылка из письма открывает форму нового пароля, пароль меняется, токен сгорает", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)
  aa_request_password_reset(con, "ann", settings)
  token <- box$token()
  log <- auth_events()

  with_url(paste0("?reset=", token))
  run_auth(con, settings = settings, log = log, {
    session$flushReact()

    html <- form_html(output)
    expect_true(grepl("reset_password", html, fixed = TRUE))
    expect_false(grepl("login_btn", html, fixed = TRUE))

    session$setInputs(reset_password = "brand-new-pass", reset_confirm = "different", reset_btn = 1)
    expect_identical(output$message, aa_text(settings, "passwords_mismatch"))
    expect_identical(aa_reset_token_login(con, token), "ann")

    session$setInputs(reset_password = "brand-new-pass", reset_confirm = "brand-new-pass", reset_btn = 2)
    expect_identical(output$message, aa_text(settings, "reset_done"))
    expect_true(grepl("login_btn", form_html(output), fixed = TRUE))
    expect_false(logged_in <- session$returned$logged_in())
  })

  expect_equal(aa_authenticate(con, "ann", "brand-new-pass")$login, "ann")
  expect_null(aa_reset_token_login(con, token))
  expect_identical(log$names(), "password_reset_done")
})

test_that("модуль: неверная ссылка показывает сообщение и форму входа", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box)
  log <- auth_events()

  with_url("?reset=0000")
  run_auth(con, settings = settings, log = log, {
    session$flushReact()

    expect_identical(output$message, aa_text(settings, "reset_link_invalid"))
    expect_true(grepl("login_btn", form_html(output), fixed = TRUE))
  })

  expect_identical(log$names(), "password_reset_failed")
})

test_that("модуль: параметр reset игнорируется, если восстановление выключено", {
  con <- reset_db()
  log <- auth_events()

  with_url("?reset=0000")
  run_auth(con, log = log, {
    session$flushReact()
    expect_true(grepl("login_btn", form_html(output), fixed = TRUE))
  })

  expect_length(log$events, 0)
})

test_that("модуль: слабый пароль в режиме reject не тратит ссылку", {
  con <- reset_db()
  box <- mailbox()
  settings <- reset_settings(box, password_policy = "reject")
  aa_request_password_reset(con, "ann", settings)
  token <- box$token()

  with_url(paste0("?reset=", token))
  run_auth(con, settings = settings, {
    session$flushReact()

    session$setInputs(reset_password = "password", reset_confirm = "password", reset_btn = 1)
    expect_true(grepl("reset_password", form_html(output), fixed = TRUE))
    expect_true(nzchar(output$message))
    expect_identical(aa_reset_token_login(con, token), "ann")
  })
})

# --- модуль пользователей ---------------------------------------------------------

test_that("модуль пользователей: администратор указывает и удаляет email, события и проверки", {
  con <- users_fixture()
  log <- users_events()

  shiny::testServer(
    aa_users_server,
    args = list(conn = con, auth = fake_auth(), on_event = log$hook),
    expr = {
      session$setInputs(open = "ivan")
      session$setInputs(email = "Ivan@Example.com", save_email = 1)
      expect_identical(aa_get_email(con, "ivan"), "ivan@example.com")

      session$setInputs(email = "broken", save_email = 2)
      expect_identical(aa_get_email(con, "ivan"), "ivan@example.com")

      session$setInputs(email = "", save_email = 3)
      expect_true(is.na(aa_get_email(con, "ivan")))
    }
  )

  expect_identical(log$names(), c("email_changed", "email_changed"))
})

test_that("модуль пользователей: не администратор не может менять email", {
  con <- users_fixture()
  log <- users_events()

  shiny::testServer(
    aa_users_server,
    args = list(conn = con, auth = fake_auth("ivan", "user"), on_event = log$hook),
    expr = {
      session$setInputs(open = "boss")
      suppressWarnings(try(session$setInputs(email = "x@example.com", save_email = 1), silent = TRUE))
    }
  )

  expect_true(is.na(aa_get_email(con, "boss")))
})

test_that("каталог событий и тексты содержат новые ключи восстановления", {
  expect_true(all(c(
    "password_reset_requested", "password_reset_done", "password_reset_failed", "email_changed"
  ) %in% aa_events()$event))

  keys <- c("forgot_link", "forgot_done", "reset_link_invalid", "reset_done", "email_invalid", "email_exists")
  expect_true(all(keys %in% aa_text_keys()))
  expect_identical(names(aa_texts("ru")), names(aa_texts("en")))
})
