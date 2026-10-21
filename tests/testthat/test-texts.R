test_that("русский и английский словари содержат одинаковые ключи", {
  expect_setequal(names(aa_texts("ru")), names(aa_texts("en")))
  expect_setequal(aa_text_keys(), names(aa_texts("en")))
})

test_that("все тексты это непустые строки", {
  for (lang in c("ru", "en")) {
    texts <- aa_texts(lang)

    for (key in names(texts)) {
      expect_true(aa_is_string(texts[[key]]), info = paste(lang, key))
    }
  }
})

test_that("маркеры подстановки в русском и английском словарях совпадают", {
  markers <- function(x) sort(regmatches(x, gregexpr("%[ds]", x))[[1]])

  for (key in aa_text_keys()) {
    expect_identical(
      markers(aa_texts("ru")[[key]]),
      markers(aa_texts("en")[[key]]),
      info = key
    )
  }
})

test_that("русские тексты по умолчанию", {
  texts <- aa_texts()

  expect_s3_class(texts, "aa_texts")
  expect_identical(attr(texts, "lang"), "ru")
  expect_identical(texts$login_title, "Авторизация")
  expect_identical(texts$bad_credentials, "Неверный логин или пароль")
})

test_that("английские тексты", {
  texts <- aa_texts("en")

  expect_identical(attr(texts, "lang"), "en")
  expect_identical(texts$login_title, "Authorization")
  expect_identical(texts$login_button, "Sign in")
})

test_that("неизвестный язык отклоняется", {
  expect_error(aa_texts("de"))
})

test_that("свои тексты заменяют стандартные, остальные остаются", {
  texts <- aa_texts("ru", login_button = "Войти в систему")

  expect_identical(texts$login_button, "Войти в систему")
  expect_identical(texts$login_title, "Авторизация")
  expect_length(texts, length(aa_text_keys()))
})

test_that("некорректные свои тексты отклоняются", {
  expect_error(aa_texts("ru", "без названия"), class = "appauth_error_texts")
  expect_error(aa_texts("ru", no_such_key = "x"), "no_such_key", class = "appauth_error_texts")
  expect_error(aa_texts("ru", login_button = ""), class = "appauth_error_texts")
  expect_error(aa_texts("ru", login_button = NA_character_), class = "appauth_error_texts")
  expect_error(aa_texts("ru", login_button = 5), class = "appauth_error_texts")
  expect_error(aa_texts("ru", login_button = c("a", "b")), class = "appauth_error_texts")
})

test_that("aa_text возвращает строку и подставляет значения", {
  texts <- aa_texts("ru")

  expect_identical(aa_text(texts, "login_button"), "Войти")
  expect_identical(
    aa_text(texts, "locked", 15),
    "Слишком много неудачных попыток входа. Повторите через 15 мин."
  )
  expect_identical(
    aa_text(texts, "setup_hint", "admin"),
    "В приложении ещё нет пользователей. Первый созданный пользователь получает роль admin."
  )
  expect_identical(aa_text(aa_texts("en"), "password_too_short", 8), "Password must be at least 8 characters long")
})

test_that("aa_text принимает настройки", {
  expect_identical(aa_text(aa_settings(), "login_button"), "Войти")
  expect_identical(aa_text(aa_settings(texts = aa_texts("en")), "login_button"), "Sign in")
})

test_that("aa_text отклоняет неверные аргументы", {
  texts <- aa_texts()

  expect_error(aa_text(texts, "no_such_key"), class = "appauth_error_texts")
  expect_error(aa_text(texts, NA_character_), class = "appauth_error_texts")
  expect_error(aa_text(texts, c("login_button", "login_title")), class = "appauth_error_texts")
  expect_error(aa_text(list(login_button = "x"), "login_button"), class = "appauth_error_texts")
})

test_that("print показывает язык и число строк", {
  expect_output(print(aa_texts("en")), "язык: en")
  expect_output(print(aa_texts()), paste0("строк: ", length(aa_text_keys())))
})
