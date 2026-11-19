test_that("default settings", {
  s <- aa_settings()

  expect_s3_class(s, "aa_settings")
  expect_identical(s$max_failed_logins, 5)
  expect_identical(s$lockout_minutes, 15)
  expect_identical(s$max_failed_logins_per_minute, 30)
  expect_identical(s$password_min, 6)
  expect_identical(s$password_max, 128)
  expect_identical(s$login_max, 64)
  expect_true(s$autologin)
  expect_true(s$must_change_default)
  expect_identical(s$session_days, 30)
  expect_identical(s$session_check_seconds, 30)
  expect_identical(s$attempts_retention_hours, 24)
  expect_identical(s$token_retention_days, 30)
  expect_identical(s$roles, c("admin", "user", "viewer"))
  expect_identical(s$admin_role, "admin")
  expect_s3_class(s$texts, "aa_texts")
  expect_identical(attr(s$texts, "lang"), "en")
})

test_that("settings can be changed", {
  s <- aa_settings(
    max_failed_logins = 3, lockout_minutes = 30, password_min = 10,
    autologin = FALSE, roles = c("boss", "editor"), admin_role = "boss",
    texts = aa_texts("ru")
  )

  expect_identical(s$max_failed_logins, 3)
  expect_identical(s$lockout_minutes, 30)
  expect_identical(s$password_min, 10)
  expect_false(s$autologin)
  expect_identical(s$roles, c("boss", "editor"))
  expect_identical(s$admin_role, "boss")
  expect_identical(attr(s$texts, "lang"), "ru")
})

test_that("numeric parameters are validated", {
  bad <- list(0, -1, NA_real_, Inf, "5", c(1, 2), NULL, 2.5)

  for (value in bad) {
    expect_error(aa_settings(max_failed_logins = value), class = "appauth_error_settings")
  }

  for (name in c("lockout_minutes", "max_failed_logins_per_minute", "password_min", "password_max",
                 "login_max", "session_days", "session_check_seconds",
                 "attempts_retention_hours", "token_retention_days")) {
    args <- setNames(list(0), name)
    expect_error(do.call(aa_settings, args), class = "appauth_error_settings", info = name)
  }
})

test_that("autologin must be TRUE or FALSE", {
  for (value in list(NA, "yes", 1, c(TRUE, FALSE), NULL)) {
    expect_error(aa_settings(autologin = value), class = "appauth_error_settings")
  }
})

test_that("must_change_default must be TRUE or FALSE", {
  expect_false(aa_settings(must_change_default = FALSE)$must_change_default)
  for (value in list(NA, "yes", 1, c(TRUE, FALSE), NULL)) {
    expect_error(aa_settings(must_change_default = value), class = "appauth_error_settings")
  }
  expect_false(aa_settings_from_list(list(must_change_default = FALSE))$must_change_default)
})

test_that("password_min cannot exceed password_max", {
  expect_error(aa_settings(password_min = 20, password_max = 10), "password_min", class = "appauth_error_settings")
  expect_no_error(aa_settings(password_min = 10, password_max = 10))
})

test_that("roles are validated", {
  expect_error(aa_settings(roles = character()), class = "appauth_error_settings")
  expect_error(aa_settings(roles = c("a", "a"), admin_role = "a"), class = "appauth_error_settings")
  expect_error(aa_settings(roles = c("a", ""), admin_role = "a"), class = "appauth_error_settings")
  expect_error(aa_settings(roles = c("a", NA), admin_role = "a"), class = "appauth_error_settings")
  expect_error(aa_settings(roles = 1:2, admin_role = "1"), class = "appauth_error_settings")
})

test_that("the administrator role must be in the roles list", {
  expect_error(aa_settings(roles = c("user", "viewer")), "admin_role", class = "appauth_error_settings")
  expect_error(aa_settings(admin_role = NA_character_), class = "appauth_error_settings")
  expect_error(aa_settings(admin_role = c("admin", "user")), class = "appauth_error_settings")
})

test_that("texts must be a result of aa_texts()", {
  expect_error(aa_settings(texts = list(login_button = "x")), "aa_texts", class = "appauth_error_settings")
  expect_error(aa_settings(texts = "en"), class = "appauth_error_settings")
})

test_that("aa_settings_from_list takes known parameters and ignores the rest", {
  s <- aa_settings_from_list(list(max_failed_logins = 3, lockout_minutes = 10, unknown_key = 1))

  expect_identical(s$max_failed_logins, 3)
  expect_identical(s$lockout_minutes, 10)
  expect_identical(s$max_failed_logins_per_minute, 30)
  expect_null(s$unknown_key)
})

test_that("aa_settings_from_list: the ... arguments override values from the list", {
  s <- aa_settings_from_list(list(lockout_minutes = 10), lockout_minutes = 20, texts = aa_texts("ru"))

  expect_identical(s$lockout_minutes, 20)
  expect_identical(attr(s$texts, "lang"), "ru")
})

test_that("aa_settings_from_list accepts NULL and an empty list, does not take texts from the list", {
  expect_identical(aa_settings_from_list(NULL)$max_failed_logins, 5)
  expect_identical(aa_settings_from_list(list())$max_failed_logins, 5)

  s <- aa_settings_from_list(list(texts = "ru"))
  expect_identical(attr(s$texts, "lang"), "en")
})

test_that("aa_settings_from_list rejects a non-list", {
  expect_error(aa_settings_from_list("max_failed_logins"), class = "appauth_error_settings")
  expect_error(aa_settings_from_list(5), class = "appauth_error_settings")
})

test_that("values of the wrong type from a YAML-like list are rejected", {
  expect_error(aa_settings_from_list(list(max_failed_logins = "many")), class = "appauth_error_settings")
})

test_that("print shows the key settings", {
  expect_output(print(aa_settings()), "appauth settings")
  expect_output(print(aa_settings()), "Auto sign-in: enabled")
  expect_output(print(aa_settings(autologin = FALSE)), "Auto sign-in: disabled")
  expect_output(print(aa_settings(texts = aa_texts("ru"))), "Interface language: ru")
})
