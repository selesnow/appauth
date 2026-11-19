test_that("aa_install_skills() копирует оба навыка в нужный каталог", {
  skip_if(!nzchar(system.file("skills", package = "appauth")), "нет inst/skills")

  dir <- withr::local_tempdir()
  out <- suppressMessages(aa_install_skills(path = file.path(dir, "skills")))

  expect_true(all(dir.exists(out)))
  expect_setequal(basename(out), c("appauth", "appauth-secure-shiny"))
  expect_true(all(file.exists(file.path(out, "SKILL.md"))))
})

test_that("aa_install_skills() по умолчанию выбирает каталог по агенту", {
  skip_if(!nzchar(system.file("skills", package = "appauth")), "нет inst/skills")

  dir <- withr::local_tempdir()
  withr::local_dir(dir)

  suppressMessages(aa_install_skills())
  expect_true(file.exists(".claude/skills/appauth/SKILL.md"))

  suppressMessages(aa_install_skills(agent = "agents"))
  expect_true(file.exists(".agents/skills/appauth-secure-shiny/SKILL.md"))
})

test_that("aa_install_skills() не затирает установленное без overwrite", {
  skip_if(!nzchar(system.file("skills", package = "appauth")), "нет inst/skills")

  dir <- withr::local_tempdir()
  suppressMessages(aa_install_skills(path = dir))

  expect_error(
    suppressMessages(aa_install_skills(path = dir)),
    class = "appauth_error_settings"
  )

  marker <- file.path(dir, "appauth", "marker.txt")
  writeLines("x", marker)
  suppressMessages(aa_install_skills(path = dir, overwrite = TRUE))
  expect_false(file.exists(marker))
})

test_that("aa_install_skills() проверяет аргументы", {
  expect_error(aa_install_skills(path = c("a", "b")), class = "appauth_error_settings")
  expect_error(aa_install_skills(agent = "unknown"))
})
