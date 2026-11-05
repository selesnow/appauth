# Вход через Google: настройки, проверка токена, завершение входа и модуль.
# Google не вызывается: ключи и обмен кода подменяются, токены подписаны тестовым ключом.

g_key <- openssl::rsa_keygen(2048)
g_other_key <- openssl::rsa_keygen(2048)
g_client_id <- "cid.apps.googleusercontent.com"

g_settings <- function(...) {
  args <- list(
    google_enabled       = TRUE,
    google_client_id     = g_client_id,
    google_client_secret = "s3cret-value",
    google_redirect_uri  = "https://apps.example.com/",
    google_domains       = c("example.com", "example.net")
  )

  do.call(aa_settings, utils::modifyList(args, list(...)))
}

g_jwk <- function(key, kid = "K1") {
  jwk <- jsonlite::fromJSON(jose::write_jwk(as.list(key)$pubkey), simplifyVector = FALSE)
  jwk$kid <- kid
  jwk$kty <- "RSA"
  jwk
}

# ключи Google подменяются, кеш ключей сбрасывается
g_fake_jwks <- function(env = parent.frame(), keys = list(g_jwk(g_key))) {
  aa_google_jwks_cache$keys <- NULL
  testthat::local_mocked_bindings(aa_google_fetch_jwks = function() keys, .package = "appauth", .env = env)
}

# подписанный токен; значение NULL убирает поле из токена
g_token <- function(nonce = "n1", key = g_key, kid = "K1", ...) {
  claims <- utils::modifyList(
    list(
      iss = "https://accounts.google.com", aud = g_client_id, exp = as.numeric(Sys.time()) + 600,
      nonce = nonce, email = "ann@example.com", email_verified = TRUE, hd = "example.com"
    ),
    list(...)
  )

  # jose принимает в aud одну строку, поэтому несколько аудиторий подставляем после сборки
  audience <- claims$aud
  claims$aud <- "placeholder"
  claim <- do.call(jose::jwt_claim, claims)
  claim$aud <- unlist(audience)

  jose::jwt_encode_sig(claim, key, header = list(kid = kid))
}

g_verify <- function(token, settings = g_settings(), nonce = "n1") {
  aa_google_verify_id_token(token, settings, nonce)
}

# база с пользователями: ann (admin) и bob (заблокирован) с адресами, cat без адреса
g_db <- function(env = parent.frame()) {
  con <- users_db(env)
  raw_user(con, "ann", role = "admin")
  raw_user(con, "bob", role = "user", blocked = 1)
  raw_user(con, "cat", role = "viewer")
  aa_set_email(con, "ann", "ann@example.com")
  aa_set_email(con, "bob", "bob@example.com")
  con
}

# обмен кода на токен: токен собирается с nonce, который сохранён для этого входа
g_fake_exchange <- function(con, env = parent.frame(), ...) {
  extra <- list(...)

  testthat::local_mocked_bindings(
    aa_google_exchange_code = function(settings, code, verifier) {
      nonce <- aa_query(
        con, "SELECT nonce FROM oauth_states WHERE code_verifier = ?", params = list(verifier)
      )$nonce
      do.call(g_token, c(list(nonce = nonce), extra))
    },
    .package = "appauth", .env = env
  )
}

g_url <- function(search, env = parent.frame()) {
  testthat::local_mocked_bindings(aa_url_search = function(session) search, .package = "appauth", .env = env)
}

# переходы браузера перехватываются: смотрим, куда и с каким разрешённым адресом отправили
g_capture_redirects <- function(env = parent.frame()) {
  box <- new.env()
  box$calls <- list()
  testthat::local_mocked_bindings(
    aa_redirect = function(session, url, origin) box$calls[[length(box$calls) + 1]] <- list(url = url, origin = origin),
    .package = "appauth", .env = env
  )
  box
}

g_page <- function(url, env = parent.frame()) {
  testthat::local_mocked_bindings(aa_page_origin = function(session) aa_url_origin(url), .package = "appauth", .env = env)
}

# --- настройки ----------------------------------------------------------------

test_that("по умолчанию Google выключен, пароль разрешён", {
  s <- aa_settings()

  expect_false(s$google_enabled)
  expect_true(s$password_login)
  expect_length(s$google_domains, 0)
})

test_that("включение Google требует идентификатор, секрет и адрес возврата", {
  expect_error(aa_settings(google_enabled = TRUE), class = "appauth_error_settings")
  expect_error(aa_settings(google_enabled = TRUE, google_client_id = "a", google_client_secret = "b"),
               class = "appauth_error_settings")
  expect_error(g_settings(google_client_secret = NULL), class = "appauth_error_settings")
  expect_error(g_settings(google_enabled = "yes"), class = "appauth_error_settings")
  expect_true(g_settings()$google_enabled)
})

test_that("адрес возврата: https или localhost", {
  expect_error(g_settings(google_redirect_uri = "http://apps.example.com/"), class = "appauth_error_settings")
  expect_error(g_settings(google_redirect_uri = "ftp://apps.example.com/"), class = "appauth_error_settings")
  expect_error(g_settings(google_redirect_uri = "apps.example.com"), class = "appauth_error_settings")
  expect_no_error(g_settings(google_redirect_uri = "https://apps.example.com/app"))
  expect_no_error(g_settings(google_redirect_uri = "http://localhost:3838/"))
})

test_that("домены приводятся к нижнему регистру, принимаются списком из конфига, плохие отклоняются", {
  expect_identical(g_settings(google_domains = list("Example.COM", " example.net "))$google_domains,
                   c("example.com", "example.net"))
  expect_length(g_settings(google_domains = NULL)$google_domains, 0)
  expect_error(g_settings(google_domains = "not a domain"), class = "appauth_error_settings")
  expect_error(g_settings(google_domains = "localhost"), class = "appauth_error_settings")
})

test_that("отключить пароль можно только вместе с Google", {
  expect_error(aa_settings(password_login = FALSE), class = "appauth_error_settings")
  expect_false(g_settings(password_login = FALSE)$password_login)
  expect_error(g_settings(password_login = NA), class = "appauth_error_settings")
})

test_that("секрет не попадает в print, настройки читаются из списка конфига", {
  s <- g_settings()
  out <- paste(utils::capture.output(print(s)), collapse = "\n")

  expect_false(grepl("s3cret-value", out, fixed = TRUE))
  expect_match(out, "Вход через Google: включён", fixed = TRUE)
  expect_match(out, "example.com, example.net", fixed = TRUE)

  from_list <- aa_settings_from_list(list(
    google_enabled = TRUE, google_client_id = g_client_id, google_client_secret = "x",
    google_redirect_uri = "https://apps.example.com/", google_domains = list("example.com"),
    password_login = FALSE
  ))
  expect_true(from_list$google_enabled)
  expect_false(from_list$password_login)
  expect_identical(from_list$google_domains, "example.com")
})

# --- начало входа и state ------------------------------------------------------

test_that("старт входа: адрес Google с PKCE, state в базе только хешем", {
  con <- g_db()
  started <- aa_google_start(con, g_settings())

  expect_match(started$url, "^https://accounts.google.com/o/oauth2/v2/auth\\?")
  expect_match(started$url, "response_type=code", fixed = TRUE)
  expect_match(started$url, "scope=openid%20email", fixed = TRUE)
  expect_match(started$url, "code_challenge_method=S256", fixed = TRUE)
  expect_match(started$url, paste0("state=", started$state), fixed = TRUE)
  expect_match(started$url, "redirect_uri=https%3A%2F%2Fapps.example.com%2F", fixed = TRUE)
  expect_false(grepl("s3cret-value", started$url, fixed = TRUE))

  row <- tquery(con, "SELECT * FROM oauth_states")
  expect_equal(nrow(row), 1)
  expect_false(identical(row$state_hash, started$state))
  expect_identical(row$state_hash, aa_token_hash(started$state))
  expect_equal(row$used, 0)
})

test_that("подсказка домена hd только когда домен один", {
  con <- g_db()

  expect_false(grepl("hd=", aa_google_start(con, g_settings())$url, fixed = TRUE))
  expect_match(aa_google_start(con, g_settings(google_domains = "example.com"))$url, "hd=example.com", fixed = TRUE)
})

test_that("старт входа выключенным Google и сверх лимита запусков отклоняется", {
  con <- g_db()

  expect_error(aa_google_start(con, aa_settings()), class = "appauth_error_settings")

  for (i in 1:60) aa_google_start(con, g_settings())
  expect_error(aa_google_start(con, g_settings()), class = "appauth_error_throttled")
})

test_that("state принимается один раз, просроченный и неизвестный отклоняются", {
  con <- g_db()
  started <- aa_google_start(con, g_settings())

  first <- aa_google_take_state(con, started$state)
  expect_named(first, c("nonce", "code_verifier"))
  expect_null(aa_google_take_state(con, started$state))

  expired <- aa_google_start(con, g_settings())
  texec(con, "UPDATE oauth_states SET expires_at = datetime('now', '-1 minutes') WHERE state_hash = ?",
                 params = list(aa_token_hash(expired$state)))
  expect_null(aa_google_take_state(con, expired$state))

  expect_null(aa_google_take_state(con, "unknown"))
  expect_null(aa_google_take_state(con, NULL))
  expect_null(aa_google_take_state(con, strrep("a", 500)))
})

test_that("очистка удаляет старые параметры входа и не трогает свежие", {
  con <- g_db()
  fresh <- aa_google_start(con, g_settings())
  old <- aa_google_start(con, g_settings())
  texec(con, "UPDATE oauth_states SET expires_at = datetime('now', '-3 days') WHERE state_hash = ?",
                 params = list(aa_token_hash(old$state)))

  res <- aa_cleanup(con, g_settings())

  expect_equal(res$oauth_states, 1)
  expect_equal(tquery(con, "SELECT COUNT(*) AS n FROM oauth_states")$n, 1)
  expect_false(is.null(aa_google_take_state(con, fresh$state)))
})

# --- проверка id_token ---------------------------------------------------------

test_that("верный токен принимается, email приводится к нижнему регистру", {
  g_fake_jwks()

  res <- g_verify(g_token(email = "Ann@Example.com"))

  expect_true(res$ok)
  expect_identical(res$email, "ann@example.com")
})

test_that("подпись чужим ключом, неизвестный kid и мусор отклоняются", {
  g_fake_jwks()

  expect_identical(g_verify(g_token(key = g_other_key))$reason, "bad_token")
  expect_identical(g_verify(g_token(kid = "NOPE"))$reason, "bad_token")
  expect_identical(g_verify("not-a-jwt")$reason, "bad_token")
  expect_identical(g_verify("a.b")$reason, "bad_token")
  expect_identical(g_verify("..")$reason, "bad_token")
})

test_that("алгоритм только RS256: none и HS256 отклоняются", {
  g_fake_jwks()

  enc <- function(x) aa_b64url_encode(charToRaw(jsonlite::toJSON(x, auto_unbox = TRUE)))
  payload <- list(iss = "https://accounts.google.com", aud = g_client_id, exp = as.numeric(Sys.time()) + 600,
                  nonce = "n1", email = "ann@example.com", email_verified = TRUE, hd = "example.com")
  none <- paste(enc(list(alg = "none", kid = "K1", typ = "JWT")), enc(payload), "sig", sep = ".")
  expect_identical(g_verify(none)$reason, "bad_token")

  hs <- jose::jwt_encode_hmac(do.call(jose::jwt_claim, payload), secret = charToRaw("x"), header = list(kid = "K1"))
  expect_identical(g_verify(hs)$reason, "bad_token")
})

test_that("издатель, аудитория, срок и nonce проверяются", {
  g_fake_jwks()

  expect_identical(g_verify(g_token(iss = "https://evil.example.com"))$reason, "bad_token")
  expect_identical(g_verify(g_token(iss = NULL))$reason, "bad_token")
  expect_true(g_verify(g_token(iss = "accounts.google.com"))$ok)
  expect_identical(g_verify(g_token(aud = "other-client"))$reason, "bad_token")
  expect_identical(g_verify(g_token(exp = as.numeric(Sys.time()) - 60))$reason, "bad_token")
  expect_identical(g_verify(g_token(), nonce = "other")$reason, "bad_nonce")
  expect_identical(g_verify(g_token(nonce = NULL))$reason, "bad_nonce")
})

test_that("несколько аудиторий требуют azp с нашим клиентом", {
  g_fake_jwks()

  expect_identical(g_verify(g_token(aud = list(g_client_id, "other")))$reason, "bad_token")
  expect_true(g_verify(g_token(aud = list(g_client_id, "other"), azp = g_client_id))$ok)
})

test_that("неподтверждённый email отклоняется, строка true принимается", {
  g_fake_jwks()

  expect_identical(g_verify(g_token(email_verified = FALSE))$reason, "email_unverified")
  expect_identical(g_verify(g_token(email_verified = NULL))$reason, "email_unverified")
  expect_identical(g_verify(g_token(email = NULL))$reason, "email_unverified")
  expect_true(g_verify(g_token(email_verified = "true"))$ok)
})

test_that("домен: и hd, и домен email должны быть из списка", {
  g_fake_jwks()

  expect_true(g_verify(g_token(hd = "example.net", email = "x@example.net"))$ok)
  # вторичный домен организации: hd основной, email на вторичном, оба в списке
  expect_true(g_verify(g_token(hd = "example.com", email = "x@example.net"))$ok)
  expect_identical(g_verify(g_token(hd = "example.com", email = "x@secondary.org"))$reason, "domain")
  expect_identical(g_verify(g_token(hd = "other.com", email = "x@other.com"))$reason, "domain")
  expect_identical(g_verify(g_token(hd = NULL, email = "ann@gmail.com"))$reason, "domain")
  expect_identical(g_verify(g_token(hd = "example.com", email = "x@other.com"))$reason, "domain")
  expect_identical(g_verify(g_token(hd = "EXAMPLE.com"))$ok, TRUE)

  # без списка доменов решает совпадение email с пользователем
  expect_true(g_verify(g_token(hd = NULL, email = "ann@gmail.com"), g_settings(google_domains = NULL))$ok)
})

test_that("ключи Google кешируются, неизвестный kid вызывает одну повторную загрузку", {
  calls <- 0
  aa_google_jwks_cache$keys <- NULL
  testthat::local_mocked_bindings(
    aa_google_fetch_jwks = function() { calls <<- calls + 1; list(g_jwk(g_key)) },
    .package = "appauth"
  )

  expect_true(g_verify(g_token())$ok)
  expect_true(g_verify(g_token())$ok)
  expect_equal(calls, 1)

  expect_identical(g_verify(g_token(kid = "NEW"))$reason, "bad_token")
  expect_equal(calls, 2)
})

# --- завершение входа ----------------------------------------------------------

test_that("успешный вход возвращает логин и роль из базы", {
  g_fake_jwks()
  con <- g_db()
  g_fake_exchange(con)
  started <- aa_google_start(con, g_settings())

  res <- aa_google_complete(con, g_settings(), "code-1", started$state)

  expect_true(res$ok)
  expect_identical(res$login, "ann")
  expect_identical(res$role, "admin")
})

test_that("тот же state второй раз не работает", {
  g_fake_jwks()
  con <- g_db()
  g_fake_exchange(con)
  started <- aa_google_start(con, g_settings())

  expect_true(aa_google_complete(con, g_settings(), "code-1", started$state)$ok)
  expect_identical(aa_google_complete(con, g_settings(), "code-1", started$state)$reason, "bad_state")
})

test_that("нет пользователя с таким email, пользователь без email и заблокированный не входят", {
  g_fake_jwks()
  con <- g_db()
  settings <- g_settings()

  g_fake_exchange(con, email = "stranger@example.com")
  res <- aa_google_complete(con, settings, "c", aa_google_start(con, settings)$state)
  expect_identical(res$reason, "no_user")
  expect_identical(res$email, "stranger@example.com")

  g_fake_exchange(con, email = "bob@example.com")
  expect_identical(aa_google_complete(con, settings, "c", aa_google_start(con, settings)$state)$reason, "blocked")

  # у cat адреса в базе нет: совпадение по email невозможно
  g_fake_exchange(con, email = "cat@example.com")
  expect_identical(aa_google_complete(con, settings, "c", aa_google_start(con, settings)$state)$reason, "no_user")
})

test_that("вход не создаёт пользователей", {
  g_fake_jwks()
  con <- g_db()
  g_fake_exchange(con, email = "stranger@example.com")
  before <- tquery(con, "SELECT COUNT(*) AS n FROM users")$n

  aa_google_complete(con, g_settings(), "c", aa_google_start(con, g_settings())$state)

  expect_equal(tquery(con, "SELECT COUNT(*) AS n FROM users")$n, before)
})

test_that("ошибки обмена, пустой код и выключенный Google дают отказ без исключения", {
  g_fake_jwks()
  con <- g_db()
  settings <- g_settings()

  testthat::local_mocked_bindings(aa_google_exchange_code = function(...) NULL, .package = "appauth")
  expect_identical(aa_google_complete(con, settings, "c", aa_google_start(con, settings)$state)$reason, "exchange_failed")

  testthat::local_mocked_bindings(aa_google_exchange_code = function(...) stop("сеть недоступна"), .package = "appauth")
  expect_identical(suppressMessages(
    aa_google_complete(con, settings, "c", aa_google_start(con, settings)$state)
  )$reason, "exchange_failed")

  expect_identical(aa_google_complete(con, settings, "", aa_google_start(con, settings)$state)$reason, "bad_code")
  expect_identical(aa_google_complete(con, settings, "c", "unknown")$reason, "bad_state")
  expect_identical(aa_google_complete(con, aa_settings(), "c", "x")$reason, "disabled")
})

# --- модуль входа --------------------------------------------------------------

test_that("форма: кнопка Google рядом с паролем, без Google формы прежняя", {
  con <- g_db()

  run_auth(con, {
    session$flushReact()
    html <- form_html(output)
    expect_match(html, "login_btn", fixed = TRUE)
    expect_match(html, "google_btn", fixed = TRUE)
    expect_match(html, "Войти через Google", fixed = TRUE)
    expect_match(html, "aa-login-or", fixed = TRUE)
  }, settings = g_settings())

  run_auth(con, {
    session$flushReact()
    expect_false(grepl("google_btn", form_html(output), fixed = TRUE))
  })
})

test_that("форма: при отключённом пароле только кнопка Google", {
  con <- g_db()

  run_auth(con, {
    session$flushReact()
    html <- form_html(output)
    expect_match(html, "google_btn", fixed = TRUE)
    expect_false(grepl("login_btn", html, fixed = TRUE))
    expect_false(grepl("forgot_link", html, fixed = TRUE))
    expect_false(grepl("aa-login-or", html, fixed = TRUE))
  }, settings = g_settings(password_login = FALSE))
})

test_that("отключённый пароль: попытка входа по паролю отклоняется на сервере", {
  con <- auth_db()
  texec(con, "UPDATE users SET email = 'alsey@example.com' WHERE login = 'alsey'")

  log <- run_auth(con, {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    expect_false(session$returned$logged_in())
    expect_match(output$message, "Вход по паролю отключён", fixed = TRUE)
  }, settings = g_settings(password_login = FALSE))

  expect_equal(log$names(), "login_failed")
  expect_equal(log$events[[1]]$value, "password_disabled")
  expect_equal(count_rows <- nrow(rows_of(con, "auth_sessions")), 0)
})

test_that("кнопка Google создаёт параметры входа и не входит сама", {
  con <- g_db()
  g_capture_redirects()
  g_page("https://apps.example.com/")

  run_auth(con, {
    session$setInputs(google_btn = 1)
    expect_false(session$returned$logged_in())
  }, settings = g_settings())

  expect_equal(tquery(con, "SELECT COUNT(*) AS n FROM oauth_states")$n, 1)
})

test_that("возврат от Google: вход выполнен, роль из базы, токен автовхода выдан, 2FA не спрашивается", {
  g_fake_jwks()
  con <- g_db()
  settings <- g_settings(totp_enabled = TRUE, totp_key = strrep("k", 20))
  texec(con, "UPDATE users SET totp_enabled = 1, totp_secret = 'x' WHERE login = 'ann'")
  g_fake_exchange(con)
  started <- aa_google_start(con, settings)
  g_url(paste0("?code=abc&state=", started$state))

  log <- run_auth(con, {
    session$flushReact()
    session$setInputs(oauth_cookie = started$state)
    expect_true(session$returned$logged_in())
    expect_equal(session$returned$user(), list(login = "ann", role = "admin"))
    expect_true(is.character(session$returned$token()))
  }, settings = settings)

  expect_equal(log$names(), "login_success")
  expect_equal(log$events[[1]]$user, "ann")
  expect_equal(log$events[[1]]$value, "google")
  expect_equal(nrow(rows_of(con, "auth_sessions")), 1)
})

test_that("возврат от Google: cookie другого браузера или без cookie вход не завершает", {
  g_fake_jwks()
  con <- g_db()
  settings <- g_settings()
  g_fake_exchange(con)
  started <- aa_google_start(con, settings)
  g_url(paste0("?code=abc&state=", started$state))

  log <- run_auth(con, {
    session$flushReact()
    session$setInputs(oauth_cookie = "state-of-another-browser")
    expect_false(session$returned$logged_in())
    expect_match(output$message, "Не удалось войти через Google", fixed = TRUE)
  }, settings = settings)

  expect_equal(log$names(), "google_login_failed")
  expect_equal(log$events[[1]]$value, "bad_browser")

  # state не потрачен впустую: вход в чужом браузере его не гасит, но и не завершается
  started2 <- aa_google_start(con, settings)
  g_url(paste0("?code=abc&state=", started2$state))
  log2 <- run_auth(con, {
    session$flushReact()
    session$setInputs(oauth_cookie = "")
    expect_false(session$returned$logged_in())
  }, settings = settings)
  expect_equal(log2$events[[1]]$value, "bad_browser")
})

test_that("возврат от Google: отказ пользователя и неизвестный email показывают понятный текст", {
  g_fake_jwks()
  con <- g_db()
  settings <- g_settings()

  g_url("?error=access_denied&state=xyz")
  log <- run_auth(con, {
    session$flushReact()
    expect_false(session$returned$logged_in())
    expect_match(output$message, "Вход через Google отменён", fixed = TRUE)
  }, settings = settings)
  expect_equal(log$events[[1]]$value, "cancelled")

  g_fake_exchange(con, email = "stranger@example.com")
  started <- aa_google_start(con, settings)
  g_url(paste0("?code=abc&state=", started$state))
  log2 <- run_auth(con, {
    session$flushReact()
    session$setInputs(oauth_cookie = started$state)
    expect_false(session$returned$logged_in())
    expect_match(output$message, "доступ не предоставлен", fixed = TRUE)
  }, settings = settings)
  expect_equal(log2$events[[1]]$value, "no_user stranger@example.com")
})

test_that("возврат от Google: заблокированный пользователь получает текст о блокировке", {
  g_fake_jwks()
  con <- g_db()
  settings <- g_settings()
  g_fake_exchange(con, email = "bob@example.com")
  started <- aa_google_start(con, settings)
  g_url(paste0("?code=abc&state=", started$state))

  run_auth(con, {
    session$flushReact()
    session$setInputs(oauth_cookie = started$state)
    expect_false(session$returned$logged_in())
    expect_match(output$message, "заблокирована", fixed = TRUE)
  }, settings = settings)
})

test_that("без включённого Google параметры code и state в адресе игнорируются", {
  con <- g_db()
  g_url("?code=abc&state=xyz")

  log <- run_auth(con, {
    session$flushReact()
    session$setInputs(oauth_cookie = "xyz")
    expect_false(session$returned$logged_in())
  })

  expect_length(log$events, 0)
})

test_that("тексты Google есть на обоих языках", {
  keys <- c("google_button", "google_or", "google_failed", "google_cancelled", "google_no_user",
            "google_domain", "password_login_disabled")

  expect_true(all(keys %in% names(aa_texts("ru"))))
  expect_true(all(keys %in% names(aa_texts("en"))))
  expect_true(all(nzchar(unlist(aa_texts("en")[keys]))))
})

test_that("события Google описаны в каталоге", {
  expect_true("google_login_failed" %in% aa_events()$event)
})

# --- вход со страницы на другом адресе (по IP) ----------------------------------

test_that("адрес разбирается на схему, хост и порт, порт по умолчанию подставляется", {
  expect_identical(aa_url_origin("https://sm.Example.com/path?x=1"), list(scheme = "https", host = "sm.example.com", port = "443"))
  expect_identical(aa_url_origin("http://localhost:3838/")$port, "3838")
  expect_identical(aa_url_origin("http://127.0.0.1")$port, "80")
  expect_identical(aa_url_origin("https://94.130.22.47")$host, "94.130.22.47")
  expect_null(aa_url_origin("ftp://x.com"))
  expect_null(aa_url_origin("sm.example.com"))
  expect_null(aa_url_origin(NULL))
  expect_identical(aa_origin_string(aa_url_origin("https://sm.example.com:443/x")), "https://sm.example.com")
  expect_identical(aa_origin_string(aa_url_origin("http://localhost:3838/x")), "http://localhost:3838")
})

test_that("адрес для перехода добавляет google=1 к адресу возврата", {
  expect_identical(aa_google_hop_url(g_settings()), "https://apps.example.com/?google=1")
  expect_identical(aa_google_hop_url(g_settings(google_redirect_uri = "https://apps.example.com/app?x=1")),
                   "https://apps.example.com/app?x=1&google=1")
})

test_that("кнопка на адресе возврата начинает вход, а не переходит", {
  con <- g_db()
  calls <- g_capture_redirects()
  g_page("https://apps.example.com/")

  run_auth(con, {
    session$setInputs(google_btn = 1)
  }, settings = g_settings())

  expect_equal(tquery(con, "SELECT COUNT(*) AS n FROM oauth_states")$n, 1)
  expect_length(calls$calls, 1)
  expect_match(calls$calls[[1]]$url, "^https://accounts.google.com/")
})

test_that("кнопка на другом адресе (по IP) переводит на адрес возврата и вход там не начинает", {
  con <- g_db()
  calls <- g_capture_redirects()
  g_page("https://94.130.22.47/")

  run_auth(con, {
    session$setInputs(google_btn = 1)
    expect_false(session$returned$logged_in())
  }, settings = g_settings())

  expect_equal(tquery(con, "SELECT COUNT(*) AS n FROM oauth_states")$n, 0)
  expect_length(calls$calls, 1)
  expect_identical(calls$calls[[1]]$url, "https://apps.example.com/?google=1")
  expect_identical(calls$calls[[1]]$origin, "https://apps.example.com")
})

test_that("другой порт или схема тоже считаются другим адресом", {
  con <- g_db()
  calls <- g_capture_redirects()
  g_page("http://apps.example.com/")

  run_auth(con, { session$setInputs(google_btn = 1) }, settings = g_settings())

  expect_equal(tquery(con, "SELECT COUNT(*) AS n FROM oauth_states")$n, 0)
  expect_match(calls$calls[[1]]$url, "google=1", fixed = TRUE)
})

test_that("?google=1 запускает вход сразу и не переводит снова, даже если адрес не совпал (нет бесконечного перехода)", {
  con <- g_db()
  calls <- g_capture_redirects()
  g_page("https://94.130.22.47/")
  g_url("?google=1")

  run_auth(con, {
    session$flushReact()
    expect_false(session$returned$logged_in())
  }, settings = g_settings())

  expect_equal(tquery(con, "SELECT COUNT(*) AS n FROM oauth_states")$n, 1)
  expect_length(calls$calls, 1)
  expect_match(calls$calls[[1]]$url, "^https://accounts.google.com/")
})

test_that("?google=1 на адресе возврата тоже запускает вход один раз", {
  con <- g_db()
  calls <- g_capture_redirects()
  g_page("https://apps.example.com/")
  g_url("?google=1")

  run_auth(con, { session$flushReact() }, settings = g_settings())

  expect_equal(tquery(con, "SELECT COUNT(*) AS n FROM oauth_states")$n, 1)
  expect_length(calls$calls, 1)
})

test_that("без включённого Google параметр google=1 ничего не запускает", {
  con <- g_db()
  calls <- g_capture_redirects()
  g_url("?google=1")

  run_auth(con, { session$flushReact() })

  expect_equal(tquery(con, "SELECT COUNT(*) AS n FROM oauth_states")$n, 0)
  expect_length(calls$calls, 0)
})

test_that("параметр google=1 вместе с кодом возврата не мешает обычному завершению входа", {
  g_fake_jwks()
  con <- g_db()
  settings <- g_settings()
  g_fake_exchange(con)
  started <- aa_google_start(con, settings)
  calls <- g_capture_redirects()
  g_url(paste0("?google=1&code=abc&state=", started$state))

  run_auth(con, {
    session$flushReact()
    session$setInputs(oauth_cookie = started$state)
    expect_true(session$returned$logged_in())
  }, settings = settings)

  expect_length(calls$calls, 0)
})

test_that("администратор указывает email без проверок домена, пароля и кода: только формат и уникальность", {
  con <- g_db()
  settings <- g_settings(google_domains = "example.com")

  expect_no_error(aa_set_email(con, "cat", "cat@gmail.com", settings))
  expect_identical(aa_get_email(con, "cat"), "cat@gmail.com")
  expect_error(aa_set_email(con, "cat", "ann@example.com", settings), class = "appauth_error_user")
  expect_error(aa_set_email(con, "cat", "не-адрес", settings), class = "appauth_error_user")
})
