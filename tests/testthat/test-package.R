test_that("the package loads and has the expected name and version", {
  desc <- utils::packageDescription("appauth")

  expect_identical(desc$Package, "appauth")
  expect_match(as.character(desc$Version), "^[0-9]+\\.[0-9]+\\.[0-9]+$")
  expect_setequal(
    c("aa_settings", "aa_auth_server", "aa_users_server", "aa_install_skills"),
    intersect(
      c(
        "aa_settings",
        "aa_auth_server",
        "aa_users_server",
        "aa_install_skills"
      ),
      getNamespaceExports("appauth")
    )
  )
})

test_that("bundled skill references match the package version", {
  version <- as.character(utils::packageDescription("appauth")$Version)
  dir <- system.file("skills", "appauth", "references", package = "appauth")
  files <- list.files(
    dir,
    pattern = "^(api.*|events|schema|ui-ids)\\.md$",
    full.names = TRUE
  )

  expect_gt(length(files), 0)

  for (file in files) {
    lines <- readLines(file, warn = FALSE)
    expect_true(
      any(grepl(paste0("version: ", version), lines, fixed = TRUE)) ||
        any(grepl(paste0("version ", version), lines, fixed = TRUE)),
      info = basename(file)
    )
  }
})
