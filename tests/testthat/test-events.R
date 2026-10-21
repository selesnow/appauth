test_that("каталог событий: уникальные ключи, все поля заполнены, нужные события есть", {
  ev <- aa_events()

  expect_named(ev, c("event", "description", "value"))
  expect_false(anyDuplicated(ev$event) > 0)
  expect_true(all(grepl("^[a-z_]+$", ev$event)))
  expect_true(all(nzchar(ev$description)))
  expect_true(all(c(
    "login_success", "login_failed", "login_locked", "login_blocked_user", "logout",
    "session_forced_logout", "user_added", "user_removed", "user_role_changed",
    "password_reset", "user_blocked", "user_unblocked", "login_unlocked",
    "access_denied", "first_admin_created"
  ) %in% ev$event))
})

test_that("все события, которые отправляет код пакета, описаны в каталоге", {
  files <- list.files(testthat::test_path("..", "..", "R"), pattern = "\\.R$", full.names = TRUE)
  skip_if(length(files) == 0, "исходники недоступны (установленный пакет)")

  code <- unlist(lapply(files, readLines, encoding = "UTF-8"))
  used <- unique(unlist(regmatches(
    code, gregexpr("aa_emit\\([^,]+,\\s*\"[a-z_]+\"", code)
  )))
  used <- sub(".*\"([a-z_]+)\"$", "\\1", used)

  expect_gt(length(used), 0)
  expect_true(all(used %in% aa_events()$event), info = paste(setdiff(used, aa_events()$event), collapse = ", "))
})

test_that("aa_emit передаёт хуку все поля и подставляет значения по умолчанию", {
  got <- NULL
  hook <- function(event, user, session_id, value) got <<- list(event, user, session_id, value)

  expect_true(aa_emit(hook, "user_added", "root", "s1", "ivan"))
  expect_equal(got, list("user_added", "root", "s1", "ivan"))

  aa_emit(hook, "logout")
  expect_equal(got, list("logout", "anonymous", "", ""))

  aa_emit(hook, "logout", NA_character_, NULL, 5)
  expect_equal(got, list("logout", "anonymous", "", "5"))
})

test_that("aa_emit без хука ничего не делает, ошибка хука не пробрасывается", {
  expect_false(aa_emit(NULL, "logout"))
  expect_false(aa_emit("не функция", "logout"))
  expect_message(
    res <- aa_emit(function(event, user, session_id, value) stop("лог недоступен"), "logout"),
    "лог недоступен"
  )
  expect_false(res)
})
