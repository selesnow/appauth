# Двухфакторная аутентификация: TOTP (RFC 6238), шифрование секрета, резервные
# коды, вход с кодом и модули личного кабинета и карточки пользователя.

totp_settings <- function(...) {
  aa_settings(totp_enabled = TRUE, totp_key = "a-long-random-key-for-the-tests", ...)
}

# включает 2FA пользователю, возвращает секрет и резервные коды
enable_totp <- function(con, login, settings = totp_settings()) {
  setup <- aa_totp_setup(con, login, settings)
  codes <- aa_totp_enable(con, login, aa_totp_code(setup$secret), settings)

  list(secret = setup$secret, codes = codes)
}

now_code <- function(secret, offset_steps = 0) {
  aa_totp_code(secret, Sys.time() + 30 * offset_steps)
}

# --- алгоритм ---------------------------------------------------------------------

test_that("HOTP и TOTP совпадают с эталонными векторами RFC 4226 и RFC 6238", {
  key <- charToRaw("12345678901234567890")

  # RFC 4226, приложение D
  expect_identical(
    vapply(0:9, function(i) aa_hotp(key, i), character(1)),
    c("755224", "287082", "359152", "969429", "338314", "254676", "287922", "162583", "399871", "520489")
  )

  # RFC 6238, приложение B (SHA-1, 8 цифр)
  at <- function(t) aa_hotp(key, floor(t / 30), 8)
  expect_identical(at(59), "94287082")
  expect_identical(at(1111111109), "07081804")
  expect_identical(at(1111111111), "14050471")
  expect_identical(at(1234567890), "89005924")
  expect_identical(at(2000000000), "69279037")
  expect_identical(at(20000000000), "65353130")

  secret <- aa_base32_encode(key)
  expect_identical(secret, "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
  expect_identical(aa_totp_code(secret, as.POSIXct(59, origin = "1970-01-01", tz = "UTC")), "287082")
})

test_that("base32 кодирует и декодирует без потерь и отклоняет мусор", {
  expect_identical(aa_base32_encode(as.raw(1:7)), "AEBAGBAFAYDQ")
  expect_identical(aa_base32_encode(as.raw(0xff)), "74")
  expect_identical(aa_base32_encode(raw()), "")

  for (n in c(1, 5, 10, 20, 33)) {
    bytes <- openssl::rand_bytes(n)
    expect_identical(aa_base32_decode(aa_base32_encode(bytes)), bytes)
  }

  expect_identical(aa_base32_decode("gezd gnbv-gy3t qoJq=="), aa_base32_decode("GEZDGNBVGY3TQOJQ"))

  for (bad in list(NULL, NA_character_, "", "abc1", "!!!", 5)) {
    expect_null(aa_base32_decode(bad))
  }
  expect_true(is.na(aa_totp_code("not base32 1")))
})

test_that("секрет случайный, 160 бит, а ссылка otpauth собирается для приложения", {
  a <- aa_totp_secret()
  b <- aa_totp_secret()

  expect_match(a, "^[A-Z2-7]{32}$")
  expect_false(identical(a, b))

  uri <- aa_totp_uri("JBSWY3DPEHPK3PXP", "ivan petrov", "Reports portal")
  expect_match(uri, "^otpauth://totp/Reports%20portal:ivan%20petrov\\?secret=JBSWY3DPEHPK3PXP&issuer=Reports%20portal&")
  expect_match(uri, "algorithm=SHA1&digits=6&period=30$")
})

# --- настройки --------------------------------------------------------------------

test_that("настройки 2FA: по умолчанию выключено, включение требует ключ, ключ в печать не попадает", {
  s <- aa_settings()
  expect_false(s$totp_enabled)
  expect_null(s$totp_key)
  expect_equal(s$totp_window, 1)

  expect_error(aa_settings(totp_enabled = TRUE), class = "appauth_error_settings")
  expect_error(aa_settings(totp_enabled = TRUE, totp_key = "short"), class = "appauth_error_settings")
  expect_error(aa_settings(totp_key = 5), class = "appauth_error_settings")
  expect_error(aa_settings(totp_issuer = ""), class = "appauth_error_settings")
  expect_error(aa_settings(totp_window = 6), class = "appauth_error_settings")
  expect_error(aa_settings(totp_window = 1.5), class = "appauth_error_settings")
  expect_no_error(aa_settings(totp_window = 0))

  on <- totp_settings()
  expect_true(on$totp_enabled)
  expect_output(print(on), "Двухфакторная аутентификация: включена")
  expect_output(print(s), "Двухфакторная аутентификация: выключена")
  expect_false(any(grepl("a-long-random-key", capture.output(print(on)), fixed = TRUE)))
})

# --- хранение секрета -------------------------------------------------------------

test_that("секрет в базе зашифрован, расшифровывается только своим ключом", {
  settings <- totp_settings()
  sealed <- aa_totp_seal("JBSWY3DPEHPK3PXP", settings)

  expect_false(grepl("JBSWY3DPEHPK3PXP", sealed, fixed = TRUE))
  expect_false(identical(sealed, aa_totp_seal("JBSWY3DPEHPK3PXP", settings))) # у каждого случайное одноразовое число
  expect_identical(aa_totp_unseal(sealed, settings), "JBSWY3DPEHPK3PXP")

  other <- aa_settings(totp_enabled = TRUE, totp_key = "another-long-random-key-123456")
  expect_true(is.na(aa_totp_unseal(sealed, other)))
  expect_true(is.na(aa_totp_unseal("zz", settings)))
  expect_true(is.na(aa_totp_unseal(NA_character_, settings)))
})

# --- включение и проверка ---------------------------------------------------------

test_that("подключение: 2FA включается только после верного кода, секрет в базе зашифрован", {
  con <- users_db()
  raw_user(con, "ivan")
  settings <- totp_settings()

  expect_false(aa_totp_enabled(con, "ivan"))

  setup <- aa_totp_setup(con, "ivan", settings)
  expect_match(setup$secret, "^[A-Z2-7]{32}$")
  expect_match(setup$uri, "^otpauth://totp/appauth:ivan\\?secret=")
  expect_false(aa_totp_enabled(con, "ivan"))

  stored <- DBI::dbGetQuery(con, "SELECT totp_secret FROM users WHERE login = 'ivan'")$totp_secret
  expect_false(grepl(setup$secret, stored, fixed = TRUE))

  err <- tryCatch(aa_totp_enable(con, "ivan", "000000", settings), appauth_error_user = identity)
  expect_identical(err$reason, "totp_wrong")
  expect_false(aa_totp_enabled(con, "ivan"))

  codes <- aa_totp_enable(con, "ivan", aa_totp_code(setup$secret), settings)
  expect_true(aa_totp_enabled(con, "ivan"))
  expect_length(codes, 10)
  expect_match(codes, "^[0-9a-f]{5}-[0-9a-f]{5}$")
  expect_length(unique(codes), 10)
  expect_identical(aa_recovery_codes_left(con, "ivan"), 10L)

  # в базе только хеши резервных кодов
  hashes <- DBI::dbGetQuery(con, "SELECT code_hash FROM totp_recovery")$code_hash
  expect_false(any(gsub("-", "", codes) %in% hashes))
})

test_that("повторное подключение, неизвестный пользователь и настройка без ключа", {
  con <- users_db()
  raw_user(con, "ivan")
  settings <- totp_settings()

  expect_error(aa_totp_setup(con, "nobody", settings), class = "appauth_error_user")
  expect_error(aa_totp_enable(con, "nobody", "123456", settings), class = "appauth_error_user")
  expect_error(aa_totp_enable(con, "ivan", "123456", settings), class = "appauth_error_user") # без setup

  enable_totp(con, "ivan", settings)
  err <- tryCatch(aa_totp_setup(con, "ivan", settings), appauth_error_user = identity)
  expect_identical(err$reason, "totp_already_enabled")
  expect_error(aa_totp_enable(con, "ivan", "123456", settings), class = "appauth_error_user")

  raw_user(con, "bob")
  expect_error(aa_totp_setup(con, "bob", aa_settings()), class = "appauth_error_settings")
})

test_that("ожидающий секрет можно заменить, прежний секрет после этого не подходит", {
  con <- users_db()
  raw_user(con, "ivan")
  settings <- totp_settings()

  first <- aa_totp_setup(con, "ivan", settings)
  second <- aa_totp_setup(con, "ivan", settings)
  expect_false(identical(first$secret, second$secret))

  if (!identical(aa_totp_code(first$secret), aa_totp_code(second$secret))) {
    expect_error(aa_totp_enable(con, "ivan", aa_totp_code(first$secret), settings), class = "appauth_error_user")
  }
  expect_length(aa_totp_enable(con, "ivan", aa_totp_code(second$secret), settings), 10)
})

test_that("проверка кода: верный принимается один раз, окно времени, неверный отклоняется", {
  con <- users_db()
  raw_user(con, "ivan")
  settings <- totp_settings()
  totp <- enable_totp(con, "ivan", settings)

  # код, принятый при включении, повторно не проходит; следующий шаг проходит
  expect_false(aa_verify_second_factor(con, "ivan", aa_totp_code(totp$secret), settings)$ok)

  ahead <- now_code(totp$secret, 1)
  res <- aa_verify_second_factor(con, "ivan", ahead, settings)
  expect_true(res$ok)
  expect_identical(res$method, "totp")

  # тот же код повторно: подсмотренный код использовать нельзя
  expect_false(aa_verify_second_factor(con, "ivan", ahead, settings)$ok)

  # код из прошлого шага (меньше последнего принятого) не проходит
  expect_false(aa_verify_second_factor(con, "ivan", now_code(totp$secret, -1), settings)$ok)

  # код вне окна не проходит, даже если он верный для своего времени
  expect_false(aa_verify_second_factor(con, "ivan", now_code(totp$secret, 5), settings)$ok)
  # шаг за окном не сдвинул last_step: следующий допустимый шаг ещё работает
  expect_false(aa_verify_second_factor(con, "ivan", "000000", settings)$ok)
})

test_that("окно totp_window настраивается", {
  con <- users_db()
  raw_user(con, "ivan")
  strict <- totp_settings(totp_window = 0)
  totp <- enable_totp(con, "ivan", strict)
  DBI::dbExecute(con, "UPDATE users SET totp_last_step = 0")

  expect_false(aa_verify_second_factor(con, "ivan", now_code(totp$secret, 1), strict)$ok)
  expect_false(aa_verify_second_factor(con, "ivan", now_code(totp$secret, -1), strict)$ok)
  expect_true(aa_verify_second_factor(con, "ivan", now_code(totp$secret, 0), strict)$ok)
})

test_that("код проверяется только при включённой 2FA и корректном формате", {
  con <- users_db()
  raw_user(con, "ivan")
  settings <- totp_settings()

  expect_false(aa_verify_second_factor(con, "ivan", "123456", settings)$ok)
  expect_false(aa_verify_second_factor(con, "nobody", "123456", settings)$ok)

  totp <- enable_totp(con, "ivan", settings)
  for (bad in list(NULL, NA_character_, "", "12345", "1234567", "abcdef", "12 34", 123456)) {
    expect_false(aa_verify_second_factor(con, "ivan", bad, settings)$ok)
  }

  # пробелы внутри кода допустимы (приложения показывают «123 456»)
  code <- now_code(totp$secret, 1)
  expect_true(aa_verify_second_factor(con, "ivan", paste(substr(code, 1, 3), substr(code, 4, 6)), settings)$ok)
})

test_that("резервные коды: любой регистр и дефис, каждый один раз, счётчик уменьшается", {
  con <- users_db()
  raw_user(con, "ivan")
  raw_user(con, "ann")
  settings <- totp_settings()
  totp <- enable_totp(con, "ivan", settings)
  other <- enable_totp(con, "ann", settings)

  code <- totp$codes[1]
  res <- aa_verify_second_factor(con, "ivan", toupper(code), settings)
  expect_true(res$ok)
  expect_identical(res$method, "recovery")
  expect_identical(aa_recovery_codes_left(con, "ivan"), 9L)

  expect_false(aa_verify_second_factor(con, "ivan", code, settings)$ok)

  # код без дефиса и с пробелами тоже подходит
  expect_true(aa_verify_second_factor(con, "ivan", gsub("-", " ", totp$codes[2]), settings)$ok)
  expect_true(aa_verify_second_factor(con, "ivan", gsub("-", "", totp$codes[3]), settings)$ok)
  expect_identical(aa_recovery_codes_left(con, "ivan"), 7L)

  # код другого пользователя не подходит
  expect_false(aa_verify_second_factor(con, "ivan", other$codes[1], settings)$ok)
  expect_identical(aa_recovery_codes_left(con, "ann"), 10L)
})

test_that("выключение стирает секрет и резервные коды, повторное подключение возможно", {
  con <- users_db()
  raw_user(con, "ivan")
  settings <- totp_settings()
  totp <- enable_totp(con, "ivan", settings)

  expect_true(aa_totp_disable(con, "ivan"))
  expect_false(aa_totp_enabled(con, "ivan"))
  expect_identical(aa_recovery_codes_left(con, "ivan"), 0L)
  expect_true(is.na(DBI::dbGetQuery(con, "SELECT totp_secret FROM users WHERE login = 'ivan'")$totp_secret))
  expect_false(aa_verify_second_factor(con, "ivan", now_code(totp$secret, 1), settings)$ok)

  expect_false(aa_totp_disable(con, "ivan"))
  expect_false(aa_totp_disable(con, "nobody"))
  expect_length(enable_totp(con, "ivan", settings)$codes, 10)
})

test_that("удаление пользователя удаляет его резервные коды", {
  con <- users_db()
  raw_user(con, "ivan")
  raw_user(con, "ann")
  enable_totp(con, "ivan")
  enable_totp(con, "ann")

  aa_delete_user(con, "ivan")

  expect_identical(aa_recovery_codes_left(con, "ivan"), 0L)
  expect_identical(aa_recovery_codes_left(con, "ann"), 10L)
})

test_that("миграция 8 достраивает старую базу, у пользователей 2FA выключена", {
  con <- new_db()
  fixture_server_manager_prod(con)
  before <- rows_of(con, "users")

  res <- aa_init_db(con)

  expect_true(8L %in% res$applied)
  expect_true(all(c("totp_secret", "totp_enabled", "totp_last_step") %in% columns_of(con, "users")))
  expect_true("totp_recovery" %in% table_names(con))
  expect_identical(rows_of(con, "users")[, names(before)], before)
  expect_true(all(rows_of(con, "users")$totp_enabled == 0))
  expect_false(aa_totp_enabled(con, "alsey"))
  expect_identical(aa_init_db(con)$applied, integer())
})

test_that("до достройки схемы 2FA считается выключенной и не ломает вход", {
  con <- new_db()
  DBI::dbExecute(con, "CREATE TABLE users (id INTEGER PRIMARY KEY, login TEXT UNIQUE, password TEXT, role TEXT)")
  DBI::dbExecute(con, "INSERT INTO users (login, password, role) VALUES ('ivan', 'x', 'user')")

  expect_false(aa_totp_enabled(con, "ivan"))
  expect_false(aa_verify_second_factor(con, "ivan", "123456", totp_settings())$ok)
  expect_identical(aa_recovery_codes_left(con, "ivan"), 0L)
})

# --- вход с кодом -----------------------------------------------------------------

test_that("после верного пароля показывается форма кода, вход и токен только после кода", {
  con <- auth_db()
  settings <- totp_settings()
  totp <- enable_totp(con, "ivan", settings)
  log <- auth_events()

  run_auth(con, settings = settings, log = log, {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)

    expect_false(session$returned$logged_in())
    expect_null(session$returned$token())
    expect_true(grepl("totp_code", form_html(output), fixed = TRUE))
    expect_false(grepl("login_btn", form_html(output), fixed = TRUE))
    # успешная попытка не записана: она обнулила бы счётчик неудач
    expect_equal(count_attempts(con), 0)
    expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM auth_sessions")$n, 0)

    session$setInputs(totp_code = now_code(totp$secret, 1), totp_btn = 1)

    expect_true(session$returned$logged_in())
    expect_identical(session$returned$user()$login, "ivan")
    expect_false(is.null(session$returned$token()))
  })

  expect_identical(log$names(), "login_success")
})

test_that("неверный пароль форму кода не показывает", {
  con <- auth_db()
  settings <- totp_settings()
  enable_totp(con, "ivan", settings)

  run_auth(con, settings = settings, {
    session$setInputs(login = "ivan", password = "wrong", login_btn = 1)
    expect_false(grepl("totp_code", form_html(output), fixed = TRUE))
    expect_true(grepl("login_btn", form_html(output), fixed = TRUE))
  })
})

test_that("пользователь без 2FA входит как раньше, даже когда функция включена", {
  con <- auth_db()
  settings <- totp_settings()
  enable_totp(con, "ivan", settings)
  log <- auth_events()

  run_auth(con, settings = settings, log = log, {
    session$setInputs(login = "alsey", password = "secret123", login_btn = 1)
    expect_true(session$returned$logged_in())
  })

  expect_identical(log$names(), "login_success")
})

test_that("при выключенной функции 2FA пользователя при входе не требуется", {
  con <- auth_db()
  enable_totp(con, "ivan")

  run_auth(con, settings = aa_settings(), {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    expect_true(session$returned$logged_in())
  })
})

test_that("неверные коды считаются неудачными попытками и блокируют логин", {
  con <- auth_db()
  settings <- totp_settings(max_failed_logins = 3)
  totp <- enable_totp(con, "ivan", settings)
  log <- auth_events()

  run_auth(con, settings = settings, log = log, {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)

    session$setInputs(totp_code = "000000", totp_btn = 1)
    expect_identical(output$message, aa_text(settings, "totp_wrong"))
    session$setInputs(totp_code = "111111", totp_btn = 2)
    expect_identical(output$message, aa_text(settings, "totp_wrong"))
    expect_false(session$returned$logged_in())

    # третья неудача блокирует логин, форма кода закрывается
    session$setInputs(totp_code = "222222", totp_btn = 3)
    expect_false(session$returned$logged_in())
    expect_match(output$message, "Слишком много неудачных попыток")
    expect_true(grepl("login_btn", form_html(output), fixed = TRUE))
    expect_gt(aa_login_lock_remaining(con, "ivan", settings), 0)

    # верный код после блокировки не помогает, пароль тоже не проверяется
    session$setInputs(login = "ivan", password = "secret123", login_btn = 2)
    expect_false(session$returned$logged_in())
    expect_false(grepl("totp_code", form_html(output), fixed = TRUE))
  })

  expect_identical(
    log$names(),
    c("totp_failed", "totp_failed", "totp_failed", "login_locked", "login_locked")
  )
})

test_that("повторный ввод пароля между неверными кодами не обнуляет счётчик", {
  con <- auth_db()
  settings <- totp_settings(max_failed_logins = 3)
  enable_totp(con, "ivan", settings)

  run_auth(con, settings = settings, {
    for (i in 1:2) {
      session$setInputs(login = "ivan", password = "secret123", login_btn = i)
      session$setInputs(totp_code = "000000", totp_btn = i)
    }
    # две неудачи уже есть; пароль не должен был их сбросить
    session$setInputs(login = "ivan", password = "secret123", login_btn = 3)
    session$setInputs(totp_code = "000000", totp_btn = 3)
  })

  expect_gt(aa_login_lock_remaining(con, "ivan", settings), 0)
})

test_that("резервный код подтверждает вход и тратится, событие recovery_code_used", {
  con <- auth_db()
  settings <- totp_settings()
  totp <- enable_totp(con, "ivan", settings)
  log <- auth_events()

  run_auth(con, settings = settings, log = log, {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    session$setInputs(totp_code = totp$codes[1], totp_btn = 1)
    expect_true(session$returned$logged_in())
  })

  expect_identical(log$names(), c("recovery_code_used", "login_success"))
  expect_identical(aa_recovery_codes_left(con, "ivan"), 9L)
})

test_that("тот же код входа второй раз не принимается", {
  con <- auth_db()
  settings <- totp_settings()
  totp <- enable_totp(con, "ivan", settings)
  code <- now_code(totp$secret, 1)

  run_auth(con, settings = settings, {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    session$setInputs(totp_code = code, totp_btn = 1)
    expect_true(session$returned$logged_in())
  })

  run_auth(con, settings = settings, {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    session$setInputs(totp_code = code, totp_btn = 1)
    expect_false(session$returned$logged_in())
  })
})

test_that("обязательная смена пароля идёт после кода, а не вместо него", {
  con <- users_db()
  aa_create_user(con, "ann", "secret123", "user", must_change = TRUE)
  settings <- totp_settings()
  DBI::dbExecute(con, "UPDATE users SET must_change = 0")
  totp <- enable_totp(con, "ann", settings)
  DBI::dbExecute(con, "UPDATE users SET must_change = 1")

  run_auth(con, settings = settings, {
    session$setInputs(login = "ann", password = "secret123", login_btn = 1)
    expect_true(grepl("totp_code", form_html(output), fixed = TRUE))

    session$setInputs(totp_code = now_code(totp$secret, 1), totp_btn = 1)
    expect_false(session$returned$logged_in())
    expect_true(grepl("change_password", form_html(output), fixed = TRUE))

    session$setInputs(change_password = "brand-new-1", change_confirm = "brand-new-1", change_btn = 1)
    expect_true(session$returned$logged_in())
  })
})

test_that("«Вернуться ко входу» отменяет ожидание кода", {
  con <- auth_db()
  settings <- totp_settings()
  enable_totp(con, "ivan", settings)

  run_auth(con, settings = settings, {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    session$setInputs(back_link = 1)

    expect_false(session$returned$logged_in())
    expect_true(grepl("login_btn", form_html(output), fixed = TRUE))
    # без пароля код не принимается
    session$setInputs(totp_code = "123456", totp_btn = 1)
    expect_false(session$returned$logged_in())
  })
})

test_that("восстановление пароля по email не обходит 2FA", {
  con <- auth_db()
  settings <- totp_settings(
    reset_enabled = TRUE, reset_base_url = "https://x.test", send_reset = function(email, link, login) NULL
  )
  totp <- enable_totp(con, "ivan", settings)
  aa_set_email(con, "ivan", "ivan@example.com")

  box <- new.env()
  settings$send_reset <- function(email, link, login) box$link <- link
  aa_request_password_reset(con, "ivan", settings)
  token <- sub(".*reset=", "", box$link)
  aa_reset_password_with_token(con, token, "brand-new-pass", settings)

  run_auth(con, settings = settings, {
    session$setInputs(login = "ivan", password = "brand-new-pass", login_btn = 1)
    expect_false(session$returned$logged_in())
    expect_true(grepl("totp_code", form_html(output), fixed = TRUE))
  })
  expect_true(aa_totp_enabled(con, "ivan"))
  expect_false(is.null(totp$secret))
})

# --- модуль личного кабинета ------------------------------------------------------

totp_module_args <- function(con, login = "ivan", settings = totp_settings(), log = users_events()) {
  list(conn = con, auth = c(fake_auth(login, "user"), list(token = function() NULL)), settings = settings, on_event = log$hook)
}

test_that("модуль: подключение 2FA, коды, события и завершение других сессий", {
  con <- users_db()
  raw_user(con, "ivan", password = aa_hash_password("secret123"))
  other_token <- aa_issue_token(con, "ivan")
  log <- users_events()
  settings <- totp_settings()

  shiny::testServer(aa_totp_server, args = totp_module_args(con, settings = settings, log = log), expr = {
    session$flushReact()
    expect_true(grepl("start", as.character(output$main$html), fixed = TRUE))

    session$setInputs(start = 1)
    secret <- enrolling()$secret
    expect_match(secret, "^[A-Z2-7]{32}$")
    expect_true(grepl("confirm", as.character(output$main$html), fixed = TRUE))

    # неверный код не включает защиту
    session$setInputs(code = "000000", confirm = 1)
    expect_false(aa_totp_enabled(con, "ivan"))
    expect_identical(output$message, aa_text(settings, "totp_wrong"))

    session$setInputs(code = aa_totp_code(secret), confirm = 2)
    expect_true(aa_totp_enabled(con, "ivan"))
    expect_true(grepl("disable_btn", as.character(output$main$html), fixed = TRUE))
  })

  expect_identical(log$names(), c("totp_failed", "totp_enabled"))
  expect_null(aa_find_session_user(con, other_token))
  expect_identical(aa_recovery_codes_left(con, "ivan"), 10L)
})

test_that("модуль: отмена подключения оставляет 2FA выключенной", {
  con <- users_db()
  raw_user(con, "ivan")

  shiny::testServer(aa_totp_server, args = totp_module_args(con), expr = {
    session$setInputs(start = 1)
    expect_false(is.null(enrolling()))
    session$setInputs(cancel = 1)
    expect_null(enrolling())
  })

  expect_false(aa_totp_enabled(con, "ivan"))
})

test_that("модуль: выключение требует и пароль, и код; неверные попытки блокируют логин", {
  con <- users_db()
  raw_user(con, "ivan", password = aa_hash_password("secret123"))
  settings <- totp_settings(max_failed_logins = 3)
  totp <- enable_totp(con, "ivan", settings)
  log <- users_events()

  shiny::testServer(aa_totp_server, args = totp_module_args(con, settings = settings, log = log), expr = {
    # неверный пароль при верном коде: код не тратится, 2FA остаётся
    session$setInputs(disable_password = "wrong", disable_code = totp$codes[1], disable_btn = 1)
    expect_true(aa_totp_enabled(con, "ivan"))
    expect_identical(aa_recovery_codes_left(con, "ivan"), 10L)
    expect_identical(output$message, aa_text(settings, "totp_disable_wrong"))

    # верный пароль, неверный код
    session$setInputs(disable_password = "secret123", disable_code = "000000", disable_btn = 2)
    expect_true(aa_totp_enabled(con, "ivan"))

    # верный пароль и резервный код
    session$setInputs(disable_password = "secret123", disable_code = totp$codes[1], disable_btn = 3)
    expect_false(aa_totp_enabled(con, "ivan"))
  })

  expect_identical(log$names(), c("totp_failed", "totp_failed", "totp_disabled"))
})

test_that("модуль: перебор кода при выключении блокирует логин", {
  con <- users_db()
  raw_user(con, "ivan", password = aa_hash_password("secret123"))
  settings <- totp_settings(max_failed_logins = 2)
  totp <- enable_totp(con, "ivan", settings)

  shiny::testServer(aa_totp_server, args = totp_module_args(con, settings = settings), expr = {
    for (i in 1:2) {
      session$setInputs(disable_password = "secret123", disable_code = "000000", disable_btn = i)
    }
    expect_gt(aa_login_lock_remaining(con, "ivan", settings), 0)

    # после блокировки даже верные пароль и код не снимают защиту
    session$setInputs(disable_password = "secret123", disable_code = totp$codes[1], disable_btn = 3)
    expect_true(aa_totp_enabled(con, "ivan"))
    expect_match(output$message, "Слишком много неудачных попыток")
  })
})

test_that("модуль ничего не показывает, пока 2FA не включена в настройках", {
  con <- users_db()
  raw_user(con, "ivan")

  shiny::testServer(aa_totp_server, args = totp_module_args(con, settings = aa_settings()), expr = {
    session$flushReact()
    expect_true(is.null(output$main$html) || !nzchar(as.character(output$main$html)))
  })
})

# --- карточка пользователя --------------------------------------------------------

test_that("администратор сбрасывает 2FA пользователя: секрет, коды и сессии стираются, событие totp_reset", {
  con <- users_fixture()
  settings <- totp_settings()
  totp <- enable_totp(con, "ivan", settings)
  token <- aa_issue_token(con, "ivan")
  log <- users_events()

  shiny::testServer(
    aa_users_server,
    args = list(conn = con, auth = fake_auth(), settings = settings, on_event = log$hook),
    expr = {
      session$setInputs(open = "ivan")
      session$setInputs(reset_totp = 1)
    }
  )

  expect_false(aa_totp_enabled(con, "ivan"))
  expect_identical(aa_recovery_codes_left(con, "ivan"), 0L)
  expect_null(aa_find_session_user(con, token))
  expect_identical(log$names(), "totp_reset")
  expect_false(is.null(totp$secret))
})

test_that("не администратор не может сбросить чужую 2FA", {
  con <- users_fixture()
  settings <- totp_settings()
  enable_totp(con, "boss", settings)

  shiny::testServer(
    aa_users_server,
    args = list(conn = con, auth = fake_auth("ivan", "user"), settings = settings),
    expr = {
      session$setInputs(open = "boss")
      suppressWarnings(try(session$setInputs(reset_totp = 1), silent = TRUE))
    }
  )

  expect_true(aa_totp_enabled(con, "boss"))
})

# --- каталог ----------------------------------------------------------------------

test_that("каталог событий и тексты содержат ключи 2FA", {
  expect_true(all(c(
    "totp_enabled", "totp_disabled", "totp_failed", "totp_reset", "recovery_code_used"
  ) %in% aa_events()$event))

  keys <- c("totp_title", "totp_wrong", "totp_section", "totp_recovery_left", "totp_reset_button", "done_totp_reset")
  expect_true(all(keys %in% aa_text_keys()))
  expect_identical(names(aa_texts("ru")), names(aa_texts("en")))
  expect_match(aa_text(aa_settings(), "totp_recovery_left", 3), "3")
})

test_that("модуль: кнопка копирования ключа для ручного ввода, текст без пробелов", {
  con <- users_db()
  raw_user(con, "ivan", password = aa_hash_password("secret123"))
  settings <- totp_settings()

  shiny::testServer(aa_totp_server, args = totp_module_args(con, settings = settings), expr = {
    session$flushReact()
    expect_false(grepl("aa-copy", as.character(output$main$html), fixed = TRUE))

    session$setInputs(start = 1)
    secret <- enrolling()$secret
    html <- paste(as.character(output$main$html), collapse = "")

    expect_match(html, "aa-copy", fixed = TRUE)
    # копируется сам секрет (без пробелов, которыми он разбит для чтения)
    expect_match(html, sprintf('data-copy="%s"', secret), fixed = TRUE)
    expect_match(html, aa_text(settings, "copy_button"), fixed = TRUE)
    expect_match(html, aa_text(settings, "copy_done"), fixed = TRUE)
  })
})

test_that("модуль: в окне резервных кодов есть кнопка копирования всех кодов", {
  con <- users_db()
  raw_user(con, "ivan", password = aa_hash_password("secret123"))
  settings <- totp_settings()

  store <- new.env()
  store$html <- NULL
  testthat::local_mocked_bindings(
    showModal = function(ui, ...) store$html <- paste(as.character(ui), collapse = ""),
    .package = "shiny"
  )

  shiny::testServer(aa_totp_server, args = totp_module_args(con, settings = settings), expr = {
    session$setInputs(start = 1)
    session$setInputs(code = aa_totp_code(enrolling()$secret), confirm = 1)
  })

  html <- store$html
  expect_match(html, "aa-totp-codes", fixed = TRUE)
  expect_match(html, "aa-copy", fixed = TRUE)

  # в атрибуте все 10 кодов, по одному в строке
  copied <- sub('.*data-copy="([^"]*)".*', "\\1", gsub("\n", "&#10;", html, fixed = TRUE))
  codes <- strsplit(gsub("&#10;", "\n", copied, fixed = TRUE), "\n", fixed = TRUE)[[1]]
  expect_length(codes, 10)
  expect_true(all(nzchar(codes)))
})

test_that("тексты кнопок копирования и колонок таблицы есть на русском и английском", {
  keys <- c("copy_button", "copy_done", "col_email", "col_totp", "col_autologins")
  for (lang in c("ru", "en")) {
    texts <- aa_texts(lang)
    expect_true(all(keys %in% names(texts)), info = lang)
    expect_true(all(nzchar(unlist(texts[keys]))), info = lang)
  }
  expect_identical(aa_text(aa_settings(), "copy_done"), "Скопировано")
  expect_identical(aa_text(aa_settings(texts = aa_texts("en")), "copy_done"), "Copied")
})
