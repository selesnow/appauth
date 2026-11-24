test_that("cookie settings validate mode, key, path and SameSite", {
  expect_equal(aa_settings()$cookie_mode, "httponly")
  expect_equal(aa_settings(cookie_mode = "legacy")$cookie_mode, "legacy")

  expect_error(
    aa_settings(cookie_mode = "unsafe"),
    class = "appauth_error_settings"
  )
  expect_error(
    aa_settings(cookie_key = "short"),
    class = "appauth_error_settings"
  )
  expect_error(
    aa_settings(cookie_path = "relative"),
    class = "appauth_error_settings"
  )
  expect_error(
    aa_settings(cookie_samesite = "Sometimes"),
    class = "appauth_error_settings"
  )
  expect_error(
    aa_settings(cookie_samesite = "None", cookie_secure = FALSE),
    class = "appauth_error_settings"
  )

  settings <- aa_settings(
    cookie_key = paste0(strrep("k", 32), "1"),
    cookie_samesite = "Strict",
    cookie_secure = TRUE
  )
  expect_equal(settings$cookie_samesite, "Strict")
  expect_true(settings$cookie_secure)
})

test_that("schema creates the cookie key and ticket tables", {
  con <- new_db()
  aa_init_db(con)

  expect_true(all(
    c("appauth_cookie_keys", "cookie_tickets") %in% table_names(con)
  ))
  expect_true(nrow(tquery(con, "SELECT secret FROM appauth_cookie_keys")) == 1)
  expect_true("consumed_at" %in% columns_of(con, "cookie_tickets"))
})

test_that("cookie tickets are encrypted, one-time and expire", {
  con <- new_db()
  aa_init_db(con)
  settings <- aa_settings()
  payload <- list(
    action = "set",
    name = "appauth_token",
    value = "token+/=",
    max_age = 60L,
    redirect = "/"
  )

  ticket <- aa_cookie_ticket(con, settings, payload)
  stored <- tquery(con, "SELECT payload FROM cookie_tickets")

  expect_true(aa_is_string(ticket))
  expect_false(identical(stored$payload[1], "token+/="))
  expect_identical(aa_cookie_take_ticket(con, settings, ticket), payload)
  expect_null(aa_cookie_take_ticket(con, settings, ticket))
  expect_null(aa_cookie_take_ticket(con, settings, "not-a-ticket"))

  expired <- aa_cookie_ticket(con, settings, payload)
  texec(
    con,
    "UPDATE cookie_tickets SET expires_at = ? WHERE token_hash = ?",
    params = list(aa_utc(-60), aa_token_hash(expired))
  )
  expect_null(aa_cookie_take_ticket(con, settings, expired))
})

test_that("cookie tickets honour an explicit cookie key", {
  con <- new_db()
  aa_init_db(con)
  settings <- aa_settings(cookie_key = paste0(strrep("z", 32), "2"))
  payload <- list(action = "clear", name = "appauth_token")

  ticket <- aa_cookie_ticket(con, settings, payload)
  expect_identical(aa_cookie_take_ticket(con, settings, ticket), payload)
  expect_null(aa_cookie_take_ticket(con, aa_settings(), ticket))
})

test_that("app and cookie endpoint paths are derived from SCRIPT_NAME", {
  root_session <- list(request = list(SCRIPT_NAME = "/"))
  sub_session <- list(request = list(SCRIPT_NAME = "/apps/demo"))

  expect_identical(aa_cookie_app_path(root_session), "/")
  expect_identical(aa_cookie_request_path(root_session), "/__appauth/cookie")
  expect_identical(aa_cookie_app_path(sub_session), "/apps/demo/")
  expect_identical(
    aa_cookie_request_path(sub_session),
    "/apps/demo/__appauth/cookie"
  )
})

test_that("request cookies are parsed from the HTTP header", {
  fake_session <- list(request = list(
    HTTP_COOKIE = paste0(
      "other=x; appauth_token=",
      utils::URLencode("token+/=", reserved = TRUE)
    )
  ))

  expect_identical(
    aa_request_cookie(fake_session, "appauth_token"),
    "token+/="
  )
  expect_null(aa_request_cookie(fake_session, "missing"))
})

test_that("cookie header uses HttpOnly, SameSite, Secure and Max-Age", {
  con <- new_db()
  aa_init_db(con)
  settings <- aa_settings()
  req <- list(HTTPS = "on")

  header <- aa_cookie_header(
    list(
      action = "set",
      value = "token+/=",
      max_age = 120L
    ),
    req,
    settings,
    "appauth_token"
  )

  expect_match(header, "appauth_token=token%2B%2F%3D", fixed = TRUE)
  expect_match(header, "Path=/", fixed = TRUE)
  expect_match(header, "Max-Age=120", fixed = TRUE)
  expect_match(header, "HttpOnly", fixed = TRUE)
  expect_match(header, "SameSite=Lax", fixed = TRUE)
  expect_match(header, "Secure", fixed = TRUE)

  cleared <- aa_cookie_header(
    list(action = "clear"),
    list(),
    settings,
    "appauth_token"
  )
  expect_match(cleared, "Max-Age=0", fixed = TRUE)
  expect_false(grepl("Secure", cleared, fixed = TRUE))
})

test_that("the HTTP endpoint consumes a ticket and returns a cookie response", {
  con <- new_db()
  aa_init_db(con)
  settings <- aa_settings()
  id <- "test-endpoint"

  aa_register_cookie_endpoint(
    id,
    con,
    settings,
    "appauth_token",
    "appauth_token_oauth",
    "/"
  )
  on.exit(aa_unregister_cookie_endpoint(id), add = TRUE)

  ticket <- aa_cookie_set_ticket(
    con,
    settings,
    "appauth_token",
    "abc",
    60,
    redirect = "/app/"
  )
  req <- list(
    REQUEST_METHOD = "GET",
    PATH_INFO = "/__appauth/cookie",
    QUERY_STRING = paste0(
      "id=",
      aa_cookie_url_encode(id),
      "&ticket=",
      aa_cookie_url_encode(ticket)
    ),
    HTTPS = "on"
  )

  response <- aa_cookie_http_handler(req)

  expect_s3_class(response, "httpResponse")
  expect_identical(response$status, 302L)
  expect_identical(response$headers$Location, "/app/")
  expect_match(response$headers$`Set-Cookie`, "HttpOnly", fixed = TRUE)
  expect_null(aa_cookie_take_ticket(con, settings, ticket))

  unknown <- aa_cookie_http_handler(transform(req, QUERY_STRING = "id=nope"))
  expect_identical(unknown$status, 404L)
})
