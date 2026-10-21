test_that("пакет загружается и имеет ожидаемое имя", {
  expect_identical(utils::packageDescription("appauth")$Package, "appauth")
})
