test_that("the package loads and has the expected name", {
  expect_identical(utils::packageDescription("appauth")$Package, "appauth")
})
