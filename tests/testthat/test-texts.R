test_that("Russian and English sets contain the same keys", {
  expect_setequal(names(aa_texts("ru")), names(aa_texts("en")))
  expect_setequal(aa_text_keys(), names(aa_texts("en")))
})

test_that("all texts are non-empty strings", {
  for (lang in c("ru", "en")) {
    texts <- aa_texts(lang)

    for (key in names(texts)) {
      expect_true(aa_is_string(texts[[key]]), info = paste(lang, key))
    }
  }
})

test_that("substitution markers match between the Russian and English sets", {
  markers <- function(x) sort(regmatches(x, gregexpr("%[ds]", x))[[1]])

  for (key in aa_text_keys()) {
    expect_identical(
      markers(aa_texts("ru")[[key]]),
      markers(aa_texts("en")[[key]]),
      info = key
    )
  }
})

test_that("English texts are the default", {
  texts <- aa_texts()

  expect_s3_class(texts, "aa_texts")
  expect_identical(attr(texts, "lang"), "en")
  expect_identical(texts$login_title, "Authorization")
  expect_identical(texts$login_button, "Sign in")
  expect_identical(texts, aa_texts("en"))
})

test_that("Russian texts are available and differ from English ones", {
  texts <- aa_texts("ru")

  expect_identical(attr(texts, "lang"), "ru")
  expect_true(all(vapply(texts, function(x) !is.na(x), logical(1))))
  expect_false(identical(texts$login_title, aa_texts("en")$login_title))
  # Russian texts are not plain ASCII
  expect_true(any(vapply(texts, function(x) any(utf8ToInt(x) > 127L), logical(1))))
})

test_that("unknown language is rejected", {
  expect_error(aa_texts("de"))
})

test_that("custom texts replace the defaults, the rest stay", {
  texts <- aa_texts("en", login_button = "Log in")

  expect_identical(texts$login_button, "Log in")
  expect_identical(texts$login_title, aa_texts("en")$login_title)
  expect_length(texts, length(aa_text_keys()))
})

test_that("invalid custom texts are rejected", {
  expect_error(aa_texts("en", "unnamed"), class = "appauth_error_texts")
  expect_error(aa_texts("en", no_such_key = "x"), "no_such_key", class = "appauth_error_texts")
  expect_error(aa_texts("en", login_button = ""), class = "appauth_error_texts")
  expect_error(aa_texts("en", login_button = NA_character_), class = "appauth_error_texts")
  expect_error(aa_texts("en", login_button = 5), class = "appauth_error_texts")
  expect_error(aa_texts("en", login_button = c("a", "b")), class = "appauth_error_texts")
})

test_that("aa_text returns a string and substitutes values", {
  texts <- aa_texts("en")

  expect_identical(aa_text(texts, "login_button"), "Sign in")
  expect_identical(
    aa_text(texts, "locked", 15),
    "Too many failed sign-in attempts. Try again in 15 min."
  )
  expect_identical(
    aa_text(texts, "setup_hint", "admin"),
    "The application has no users yet. The first user you create gets the admin role."
  )
  expect_identical(aa_text(texts, "password_too_short", 8), "Password must be at least 8 characters long")

  ru <- aa_texts("ru")
  expect_identical(aa_text(ru, "locked", 15), sprintf(ru$locked, 15))
})

test_that("aa_text accepts settings", {
  expect_identical(aa_text(aa_settings(), "login_button"), "Sign in")
  expect_identical(
    aa_text(aa_settings(texts = aa_texts("ru")), "login_button"),
    aa_texts("ru")$login_button
  )
})

test_that("aa_text rejects invalid arguments", {
  texts <- aa_texts()

  expect_error(aa_text(texts, "no_such_key"), class = "appauth_error_texts")
  expect_error(aa_text(texts, NA_character_), class = "appauth_error_texts")
  expect_error(aa_text(texts, c("login_button", "login_title")), class = "appauth_error_texts")
  expect_error(aa_text(list(login_button = "x"), "login_button"), class = "appauth_error_texts")
})

test_that("print shows the language and the number of strings", {
  expect_output(print(aa_texts("ru")), "language: ru")
  expect_output(print(aa_texts()), paste0("strings: ", length(aa_text_keys())))
})
