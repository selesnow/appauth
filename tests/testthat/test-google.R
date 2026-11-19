# Sign-in with Google: settings, token verification, completing sign-in and the module.
# Google is not called: keys and the code exchange are mocked, tokens are signed with a test key.

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

# Google keys are mocked, the key cache is reset
g_fake_jwks <- function(env = parent.frame(), keys = list(g_jwk(g_key))) {
  aa_google_jwks_cache$keys <- NULL
  testthat::local_mocked_bindings(aa_google_fetch_jwks = function() keys, .package = "appauth", .env = env)
}

# a signed token; a NULL value removes the field from the token
g_token <- function(nonce = "n1", key = g_key, kid = "K1", ...) {
  claims <- utils::modifyList(
    list(
      iss = "https://accounts.google.com", aud = g_client_id, exp = as.numeric(Sys.time()) + 600,
      nonce = nonce, email = "ann@example.com", email_verified = TRUE, hd = "example.com"
    ),
    list(...)
  )

  # jose accepts a single string in aud, so several audiences are substituted after assembly
  audience <- claims$aud
  claims$aud <- "placeholder"
  claim <- do.call(jose::jwt_claim, claims)
  claim$aud <- unlist(audience)

  jose::jwt_encode_sig(claim, key, header = list(kid = kid))
}

g_verify <- function(token, settings = g_settings(), nonce = "n1") {
  aa_google_verify_id_token(token, settings, nonce)
}

# a database with users: ann (admin) and bob (blocked) with addresses, cat without an address
g_db <- function(env = parent.frame()) {
  con <- users_db(env)
  raw_user(con, "ann", role = "admin")
  raw_user(con, "bob", role = "user", blocked = 1)
  raw_user(con, "cat", role = "viewer")
  aa_set_email(con, "ann", "ann@example.com")
  aa_set_email(con, "bob", "bob@example.com")
  con
}

# code exchange for a token: the token is built with the nonce saved for this sign-in
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

# browser redirects are intercepted: we look at where and with which allowed address they were sent
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

# --- settings ---------------------------------------------------------------

test_that("by default Google is off, the password is allowed", {
  s <- aa_settings()

  expect_false(s$google_enabled)
  expect_true(s$password_login)
  expect_length(s$google_domains, 0)
})

test_that("enabling Google requires an id, a secret and a return address", {
  expect_error(aa_settings(google_enabled = TRUE), class = "appauth_error_settings")
  expect_error(aa_settings(google_enabled = TRUE, google_client_id = "a", google_client_secret = "b"),
               class = "appauth_error_settings")
  expect_error(g_settings(google_client_secret = NULL), class = "appauth_error_settings")
  expect_error(g_settings(google_enabled = "yes"), class = "appauth_error_settings")
  expect_true(g_settings()$google_enabled)
})

test_that("return address: https or localhost", {
  expect_error(g_settings(google_redirect_uri = "http://apps.example.com/"), class = "appauth_error_settings")
  expect_error(g_settings(google_redirect_uri = "ftp://apps.example.com/"), class = "appauth_error_settings")
  expect_error(g_settings(google_redirect_uri = "apps.example.com"), class = "appauth_error_settings")
  expect_no_error(g_settings(google_redirect_uri = "https://apps.example.com/app"))
  expect_no_error(g_settings(google_redirect_uri = "http://localhost:3838/"))
})

test_that("domains are lower-cased, accepted as a list from the config, bad ones are rejected", {
  expect_identical(g_settings(google_domains = list("Example.COM", " example.net "))$google_domains,
                   c("example.com", "example.net"))
  expect_length(g_settings(google_domains = NULL)$google_domains, 0)
  expect_error(g_settings(google_domains = "not a domain"), class = "appauth_error_settings")
  expect_error(g_settings(google_domains = "localhost"), class = "appauth_error_settings")
})

test_that("the password can be disabled only together with Google", {
  expect_error(aa_settings(password_login = FALSE), class = "appauth_error_settings")
  expect_false(g_settings(password_login = FALSE)$password_login)
  expect_error(g_settings(password_login = NA), class = "appauth_error_settings")
})

test_that("the secret does not appear in print, settings are read from a config list", {
  s <- g_settings()
  out <- paste(utils::capture.output(print(s)), collapse = "\n")

  expect_false(grepl("s3cret-value", out, fixed = TRUE))
  expect_match(out, "Google sign-in: enabled", fixed = TRUE)
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

# --- sign-in start and state ---------------------------------------------------

test_that("sign-in start: Google address with PKCE, state in the database only as a hash", {
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

test_that("the hd domain hint only when there is one domain", {
  con <- g_db()

  expect_false(grepl("hd=", aa_google_start(con, g_settings())$url, fixed = TRUE))
  expect_match(aa_google_start(con, g_settings(google_domains = "example.com"))$url, "hd=example.com", fixed = TRUE)
})

test_that("starting sign-in with Google off and over the start limit is rejected", {
  con <- g_db()

  expect_error(aa_google_start(con, aa_settings()), class = "appauth_error_settings")

  for (i in 1:60) aa_google_start(con, g_settings())
  expect_error(aa_google_start(con, g_settings()), class = "appauth_error_throttled")
})

test_that("state is accepted once, expired and unknown ones are rejected", {
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

test_that("cleanup deletes old sign-in parameters and does not touch fresh ones", {
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

# --- id_token verification -----------------------------------------------------

test_that("a valid token is accepted, email is lower-cased", {
  g_fake_jwks()

  res <- g_verify(g_token(email = "Ann@Example.com"))

  expect_true(res$ok)
  expect_identical(res$email, "ann@example.com")
})

test_that("a signature by a foreign key, an unknown kid and garbage are rejected", {
  g_fake_jwks()

  expect_identical(g_verify(g_token(key = g_other_key))$reason, "bad_token")
  expect_identical(g_verify(g_token(kid = "NOPE"))$reason, "bad_token")
  expect_identical(g_verify("not-a-jwt")$reason, "bad_token")
  expect_identical(g_verify("a.b")$reason, "bad_token")
  expect_identical(g_verify("..")$reason, "bad_token")
})

test_that("only the RS256 algorithm: none and HS256 are rejected", {
  g_fake_jwks()

  enc <- function(x) aa_b64url_encode(charToRaw(jsonlite::toJSON(x, auto_unbox = TRUE)))
  payload <- list(iss = "https://accounts.google.com", aud = g_client_id, exp = as.numeric(Sys.time()) + 600,
                  nonce = "n1", email = "ann@example.com", email_verified = TRUE, hd = "example.com")
  none <- paste(enc(list(alg = "none", kid = "K1", typ = "JWT")), enc(payload), "sig", sep = ".")
  expect_identical(g_verify(none)$reason, "bad_token")

  hs <- jose::jwt_encode_hmac(do.call(jose::jwt_claim, payload), secret = charToRaw("x"), header = list(kid = "K1"))
  expect_identical(g_verify(hs)$reason, "bad_token")
})

test_that("issuer, audience, expiry and nonce are verified", {
  g_fake_jwks()

  expect_identical(g_verify(g_token(iss = "https://evil.example.com"))$reason, "bad_token")
  expect_identical(g_verify(g_token(iss = NULL))$reason, "bad_token")
  expect_true(g_verify(g_token(iss = "accounts.google.com"))$ok)
  expect_identical(g_verify(g_token(aud = "other-client"))$reason, "bad_token")
  expect_identical(g_verify(g_token(exp = as.numeric(Sys.time()) - 60))$reason, "bad_token")
  expect_identical(g_verify(g_token(), nonce = "other")$reason, "bad_nonce")
  expect_identical(g_verify(g_token(nonce = NULL))$reason, "bad_nonce")
})

test_that("several audiences require azp with our client", {
  g_fake_jwks()

  expect_identical(g_verify(g_token(aud = list(g_client_id, "other")))$reason, "bad_token")
  expect_true(g_verify(g_token(aud = list(g_client_id, "other"), azp = g_client_id))$ok)
})

test_that("an unverified email is rejected, the string true is accepted", {
  g_fake_jwks()

  expect_identical(g_verify(g_token(email_verified = FALSE))$reason, "email_unverified")
  expect_identical(g_verify(g_token(email_verified = NULL))$reason, "email_unverified")
  expect_identical(g_verify(g_token(email = NULL))$reason, "email_unverified")
  expect_true(g_verify(g_token(email_verified = "true"))$ok)
})

test_that("domain: both hd and the email domain must be from the list", {
  g_fake_jwks()

  expect_true(g_verify(g_token(hd = "example.net", email = "x@example.net"))$ok)
  # a secondary organization domain: hd is primary, email is on the secondary one, both in the list
  expect_true(g_verify(g_token(hd = "example.com", email = "x@example.net"))$ok)
  expect_identical(g_verify(g_token(hd = "example.com", email = "x@secondary.org"))$reason, "domain")
  expect_identical(g_verify(g_token(hd = "other.com", email = "x@other.com"))$reason, "domain")
  expect_identical(g_verify(g_token(hd = NULL, email = "ann@gmail.com"))$reason, "domain")
  expect_identical(g_verify(g_token(hd = "example.com", email = "x@other.com"))$reason, "domain")
  expect_identical(g_verify(g_token(hd = "EXAMPLE.com"))$ok, TRUE)

  # without a domain list the match of email with a user decides
  expect_true(g_verify(g_token(hd = NULL, email = "ann@gmail.com"), g_settings(google_domains = NULL))$ok)
})

test_that("Google keys are cached, an unknown kid causes one reload", {
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

# --- completing sign-in --------------------------------------------------------

test_that("successful sign-in returns the login and role from the database", {
  g_fake_jwks()
  con <- g_db()
  g_fake_exchange(con)
  started <- aa_google_start(con, g_settings())

  res <- aa_google_complete(con, g_settings(), "code-1", started$state)

  expect_true(res$ok)
  expect_identical(res$login, "ann")
  expect_identical(res$role, "admin")
})

test_that("the same state does not work a second time", {
  g_fake_jwks()
  con <- g_db()
  g_fake_exchange(con)
  started <- aa_google_start(con, g_settings())

  expect_true(aa_google_complete(con, g_settings(), "code-1", started$state)$ok)
  expect_identical(aa_google_complete(con, g_settings(), "code-1", started$state)$reason, "bad_state")
})

test_that("no user with this email, a user without an email and a blocked one do not sign in", {
  g_fake_jwks()
  con <- g_db()
  settings <- g_settings()

  g_fake_exchange(con, email = "stranger@example.com")
  res <- aa_google_complete(con, settings, "c", aa_google_start(con, settings)$state)
  expect_identical(res$reason, "no_user")
  expect_identical(res$email, "stranger@example.com")

  g_fake_exchange(con, email = "bob@example.com")
  expect_identical(aa_google_complete(con, settings, "c", aa_google_start(con, settings)$state)$reason, "blocked")

  # cat has no address in the database: matching by email is impossible
  g_fake_exchange(con, email = "cat@example.com")
  expect_identical(aa_google_complete(con, settings, "c", aa_google_start(con, settings)$state)$reason, "no_user")
})

test_that("sign-in does not create users", {
  g_fake_jwks()
  con <- g_db()
  g_fake_exchange(con, email = "stranger@example.com")
  before <- tquery(con, "SELECT COUNT(*) AS n FROM users")$n

  aa_google_complete(con, g_settings(), "c", aa_google_start(con, g_settings())$state)

  expect_equal(tquery(con, "SELECT COUNT(*) AS n FROM users")$n, before)
})

test_that("exchange errors, an empty code and Google off give a refusal without an exception", {
  g_fake_jwks()
  con <- g_db()
  settings <- g_settings()

  testthat::local_mocked_bindings(aa_google_exchange_code = function(...) NULL, .package = "appauth")
  expect_identical(aa_google_complete(con, settings, "c", aa_google_start(con, settings)$state)$reason, "exchange_failed")

  testthat::local_mocked_bindings(aa_google_exchange_code = function(...) stop("network unavailable"), .package = "appauth")
  expect_identical(suppressMessages(
    aa_google_complete(con, settings, "c", aa_google_start(con, settings)$state)
  )$reason, "exchange_failed")

  expect_identical(aa_google_complete(con, settings, "", aa_google_start(con, settings)$state)$reason, "bad_code")
  expect_identical(aa_google_complete(con, settings, "c", "unknown")$reason, "bad_state")
  expect_identical(aa_google_complete(con, aa_settings(), "c", "x")$reason, "disabled")
})

# --- sign-in module ------------------------------------------------------------

test_that("form: the Google button next to the password, without Google the form is as before", {
  con <- g_db()

  run_auth(con, {
    session$flushReact()
    html <- form_html(output)
    expect_match(html, "login_btn", fixed = TRUE)
    expect_match(html, "google_btn", fixed = TRUE)
    expect_match(html, "Sign in with Google", fixed = TRUE)
    expect_match(html, "aa-login-or", fixed = TRUE)
  }, settings = g_settings())

  run_auth(con, {
    session$flushReact()
    expect_false(grepl("google_btn", form_html(output), fixed = TRUE))
  })
})

test_that("form: with the password disabled only the Google button", {
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

test_that("disabled password: a password sign-in attempt is rejected on the server", {
  con <- auth_db()
  texec(con, "UPDATE users SET email = 'alsey@example.com' WHERE login = 'alsey'")

  log <- run_auth(con, {
    session$setInputs(login = "ivan", password = "secret123", login_btn = 1)
    expect_false(session$returned$logged_in())
    expect_match(output$message, "Password sign-in is disabled", fixed = TRUE)
  }, settings = g_settings(password_login = FALSE))

  expect_equal(log$names(), "login_failed")
  expect_equal(log$events[[1]]$value, "password_disabled")
  expect_equal(count_rows <- nrow(rows_of(con, "auth_sessions")), 0)
})

test_that("the Google button creates sign-in parameters and does not sign in by itself", {
  con <- g_db()
  g_capture_redirects()
  g_page("https://apps.example.com/")

  run_auth(con, {
    session$setInputs(google_btn = 1)
    expect_false(session$returned$logged_in())
  }, settings = g_settings())

  expect_equal(tquery(con, "SELECT COUNT(*) AS n FROM oauth_states")$n, 1)
})

test_that("return from Google: signed in, role from the database, auto-login token issued, 2FA not asked", {
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

test_that("return from Google: a cookie of another browser or no cookie does not complete sign-in", {
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
    expect_match(output$message, "Could not sign in with Google", fixed = TRUE)
  }, settings = settings)

  expect_equal(log$names(), "google_login_failed")
  expect_equal(log$events[[1]]$value, "bad_browser")

  # state is not wasted: sign-in in a foreign browser does not consume it, but does not complete either
  started2 <- aa_google_start(con, settings)
  g_url(paste0("?code=abc&state=", started2$state))
  log2 <- run_auth(con, {
    session$flushReact()
    session$setInputs(oauth_cookie = "")
    expect_false(session$returned$logged_in())
  }, settings = settings)
  expect_equal(log2$events[[1]]$value, "bad_browser")
})

test_that("return from Google: a user refusal and an unknown email show a clear text", {
  g_fake_jwks()
  con <- g_db()
  settings <- g_settings()

  g_url("?error=access_denied&state=xyz")
  log <- run_auth(con, {
    session$flushReact()
    expect_false(session$returned$logged_in())
    expect_match(output$message, "Google sign-in was cancelled", fixed = TRUE)
  }, settings = settings)
  expect_equal(log$events[[1]]$value, "cancelled")

  g_fake_exchange(con, email = "stranger@example.com")
  started <- aa_google_start(con, settings)
  g_url(paste0("?code=abc&state=", started$state))
  log2 <- run_auth(con, {
    session$flushReact()
    session$setInputs(oauth_cookie = started$state)
    expect_false(session$returned$logged_in())
    expect_match(output$message, "has not been granted access", fixed = TRUE)
  }, settings = settings)
  expect_equal(log2$events[[1]]$value, "no_user stranger@example.com")
})

test_that("return from Google: a blocked user gets the block text", {
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
    expect_match(output$message, "blocked", fixed = TRUE)
  }, settings = settings)
})

test_that("without Google enabled the code and state parameters in the address are ignored", {
  con <- g_db()
  g_url("?code=abc&state=xyz")

  log <- run_auth(con, {
    session$flushReact()
    session$setInputs(oauth_cookie = "xyz")
    expect_false(session$returned$logged_in())
  })

  expect_length(log$events, 0)
})

test_that("Google texts exist in both languages", {
  keys <- c("google_button", "google_or", "google_failed", "google_cancelled", "google_no_user",
            "google_domain", "password_login_disabled")

  expect_true(all(keys %in% names(aa_texts("ru"))))
  expect_true(all(keys %in% names(aa_texts("en"))))
  expect_true(all(nzchar(unlist(aa_texts("en")[keys]))))
})

test_that("Google events are described in the catalog", {
  expect_true("google_login_failed" %in% aa_events()$event)
})

# --- sign-in from a page at another address (by IP) -----------------------------

test_that("an address is parsed into scheme, host and port, the default port is filled in", {
  expect_identical(aa_url_origin("https://app.Example.com/path?x=1"), list(scheme = "https", host = "app.example.com", port = "443"))
  expect_identical(aa_url_origin("http://localhost:3838/")$port, "3838")
  expect_identical(aa_url_origin("http://127.0.0.1")$port, "80")
  expect_identical(aa_url_origin("https://94.130.22.47")$host, "94.130.22.47")
  expect_null(aa_url_origin("ftp://x.com"))
  expect_null(aa_url_origin("app.example.com"))
  expect_null(aa_url_origin(NULL))
  expect_identical(aa_origin_string(aa_url_origin("https://app.example.com:443/x")), "https://app.example.com")
  expect_identical(aa_origin_string(aa_url_origin("http://localhost:3838/x")), "http://localhost:3838")
})

test_that("the redirect address appends google=1 to the return address", {
  expect_identical(aa_google_hop_url(g_settings()), "https://apps.example.com/?google=1")
  expect_identical(aa_google_hop_url(g_settings(google_redirect_uri = "https://apps.example.com/app?x=1")),
                   "https://apps.example.com/app?x=1&google=1")
})

test_that("the button at the return address starts sign-in instead of redirecting", {
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

test_that("the button at another address (by IP) redirects to the return address and does not start sign-in there", {
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

test_that("another port or scheme also counts as another address", {
  con <- g_db()
  calls <- g_capture_redirects()
  g_page("http://apps.example.com/")

  run_auth(con, { session$setInputs(google_btn = 1) }, settings = g_settings())

  expect_equal(tquery(con, "SELECT COUNT(*) AS n FROM oauth_states")$n, 0)
  expect_match(calls$calls[[1]]$url, "google=1", fixed = TRUE)
})

test_that("?google=1 starts sign-in at once and does not redirect again even if the address did not match (no endless redirect)", {
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

test_that("?google=1 at the return address also starts sign-in once", {
  con <- g_db()
  calls <- g_capture_redirects()
  g_page("https://apps.example.com/")
  g_url("?google=1")

  run_auth(con, { session$flushReact() }, settings = g_settings())

  expect_equal(tquery(con, "SELECT COUNT(*) AS n FROM oauth_states")$n, 1)
  expect_length(calls$calls, 1)
})

test_that("without Google enabled the google=1 parameter starts nothing", {
  con <- g_db()
  calls <- g_capture_redirects()
  g_url("?google=1")

  run_auth(con, { session$flushReact() })

  expect_equal(tquery(con, "SELECT COUNT(*) AS n FROM oauth_states")$n, 0)
  expect_length(calls$calls, 0)
})

test_that("the google=1 parameter together with a return code does not prevent the usual completion of sign-in", {
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

test_that("an administrator sets an email without domain, password and code checks: only format and uniqueness", {
  con <- g_db()
  settings <- g_settings(google_domains = "example.com")

  expect_no_error(aa_set_email(con, "cat", "cat@gmail.com", settings))
  expect_identical(aa_get_email(con, "cat"), "cat@gmail.com")
  expect_error(aa_set_email(con, "cat", "ann@example.com", settings), class = "appauth_error_user")
  expect_error(aa_set_email(con, "cat", "not-an-address", settings), class = "appauth_error_user")
})
