test_that("aa_app_head подключает CSS и JS пакета как зависимость", {
  head <- aa_app_head()
  deps <- htmltools::findDependencies(head)

  expect_length(deps, 1)
  expect_equal(deps[[1]]$name, "appauth")
  expect_equal(deps[[1]]$script, "appauth.js")
  expect_equal(deps[[1]]$stylesheet, "appauth.css")
  expect_true(file.exists(file.path(deps[[1]]$src$file, "appauth.js")))
  expect_true(file.exists(file.path(deps[[1]]$src$file, "appauth.css")))
})

test_that("JS содержит обработчики cookie и ставит SameSite и Secure", {
  js <- paste(readLines(system.file("www", "appauth.js", package = "appauth"), encoding = "UTF-8"), collapse = "\n")

  expect_match(js, "appauth_set_cookie", fixed = TRUE)
  expect_match(js, "appauth_clear_cookie", fixed = TRUE)
  expect_match(js, "appauth_read_cookie", fixed = TRUE)
  expect_match(js, "SameSite=Lax", fixed = TRUE)
  expect_match(js, "Secure", fixed = TRUE)
})

test_that("CSS содержит классы, на которые опираются модули", {
  css <- paste(readLines(system.file("www", "appauth.css", package = "appauth"), encoding = "UTF-8"), collapse = "\n")

  for (cls in c("aa-login", "aa-login-card", "aa-login-message", "aa-row-blocked", "aa-row-locked",
                "aa-theme-light", "--aa-primary", "--aa-danger")) {
    expect_match(css, cls, fixed = TRUE, info = cls)
  }
})
