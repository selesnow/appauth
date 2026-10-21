test_that("токен выдаётся, в базе только sha256-хеш, срок равен session_days", {
  con <- users_db()
  raw_user(con, "ivan", "user")

  token <- aa_issue_token(con, "ivan")

  expect_type(token, "character")
  expect_gte(nchar(token), 40)

  row <- rows_of(con, "auth_sessions")
  expect_equal(nrow(row), 1)
  expect_equal(row$token_hash, as.character(openssl::sha256(token)))
  expect_false(identical(row$token_hash, token))
  expect_equal(nchar(row$token_hash), 64)
  expect_equal(row$revoked, 0)

  days <- DBI::dbGetQuery(
    con, "SELECT julianday(expires_at) - julianday('now') AS d FROM auth_sessions"
  )$d
  expect_equal(days, 30, tolerance = 0.01)
})

test_that("токены уникальны", {
  con <- users_db()
  raw_user(con, "ivan")

  expect_false(identical(aa_issue_token(con, "ivan"), aa_issue_token(con, "ivan")))
})

test_that("срок токена берётся из настроек", {
  con <- users_db()
  raw_user(con, "ivan")

  aa_issue_token(con, "ivan", aa_settings(session_days = 1))
  days <- DBI::dbGetQuery(
    con, "SELECT julianday(expires_at) - julianday('now') AS d FROM auth_sessions"
  )$d
  expect_equal(days, 1, tolerance = 0.01)
})

test_that("токен не выдаётся: автовход выключен, нет пользователя, блокировка, пустой логин", {
  con <- users_db()
  raw_user(con, "ivan")
  raw_user(con, "bad", blocked = 1)

  expect_null(aa_issue_token(con, "ivan", aa_settings(autologin = FALSE)))
  expect_null(aa_issue_token(con, "ghost"))
  expect_null(aa_issue_token(con, "bad"))
  expect_null(aa_issue_token(con, ""))
  expect_null(aa_issue_token(con, NA_character_))
  expect_equal(nrow(rows_of(con, "auth_sessions")), 0)
})

test_that("токен выдаётся строго для точного логина (регистр различается)", {
  con <- users_db()
  raw_user(con, "kiruka")

  expect_null(aa_issue_token(con, "Kiruka"))
})

test_that("по токену находится пользователь с актуальной ролью", {
  con <- users_db()
  raw_user(con, "ivan", "user")
  token <- aa_issue_token(con, "ivan")

  expect_equal(aa_find_session_user(con, token), list(login = "ivan", role = "user"))

  aa_set_role(con, "ivan", "admin")
  expect_equal(aa_find_session_user(con, token)$role, "admin")
})

test_that("чужой, пустой и повреждённый токен никого не пускает", {
  con <- users_db()
  raw_user(con, "ivan")
  token <- aa_issue_token(con, "ivan")

  expect_null(aa_find_session_user(con, paste0(token, "x")))
  expect_null(aa_find_session_user(con, ""))
  expect_null(aa_find_session_user(con, NA_character_))
  expect_null(aa_find_session_user(con, NULL))
  expect_null(aa_find_session_user(con, c(token, token)))
  # хеш из базы в качестве токена не работает
  expect_null(aa_find_session_user(con, rows_of(con, "auth_sessions")$token_hash))
})

test_that("истёкший и отозванный токены не работают", {
  con <- users_db()
  raw_user(con, "ivan")
  token <- aa_issue_token(con, "ivan")

  DBI::dbExecute(con, "UPDATE auth_sessions SET expires_at = datetime('now', '-1 seconds')")
  expect_null(aa_find_session_user(con, token))

  DBI::dbExecute(con, "UPDATE auth_sessions SET expires_at = datetime('now', '+1 days')")
  expect_false(is.null(aa_find_session_user(con, token)))

  expect_equal(aa_revoke_token(con, token), 1)
  expect_null(aa_find_session_user(con, token))
})

test_that("отзыв токена не трогает остальные и безопасен на мусоре", {
  con <- users_db()
  raw_user(con, "ivan")
  t1 <- aa_issue_token(con, "ivan")
  t2 <- aa_issue_token(con, "ivan")

  aa_revoke_token(con, t1)

  expect_null(aa_find_session_user(con, t1))
  expect_false(is.null(aa_find_session_user(con, t2)))
  expect_equal(aa_revoke_token(con, "no-such-token"), 0)
  expect_equal(aa_revoke_token(con, NULL), 0)
  expect_equal(aa_revoke_token(con, ""), 0)
})

test_that("блокировка, удаление и смена пароля лишают токены силы", {
  con <- users_db()
  raw_user(con, "admin", "admin")
  aa_set_password(con, "admin", "adminpass1")
  raw_user(con, "ivan")
  raw_user(con, "petr")
  raw_user(con, "olga")
  t_ivan <- aa_issue_token(con, "ivan")
  t_petr <- aa_issue_token(con, "petr")
  t_olga <- aa_issue_token(con, "olga")

  aa_set_blocked(con, "ivan", TRUE, acting_login = "admin")
  aa_delete_user(con, "petr", acting_login = "admin")
  aa_set_password(con, "olga", "newpass123")

  expect_null(aa_find_session_user(con, t_ivan))
  expect_null(aa_find_session_user(con, t_petr))
  expect_null(aa_find_session_user(con, t_olga))
})

test_that("после разблокировки старый токен остаётся отозванным", {
  con <- users_db()
  raw_user(con, "admin", "admin")
  raw_user(con, "ivan")
  token <- aa_issue_token(con, "ivan")

  aa_set_blocked(con, "ivan", TRUE, acting_login = "admin")
  aa_set_blocked(con, "ivan", FALSE, acting_login = "admin")

  expect_null(aa_find_session_user(con, token))
})

test_that("токен удалённого пользователя не переходит к новому владельцу логина", {
  con <- users_db()
  raw_user(con, "admin", "admin")
  raw_user(con, "ivan")
  token <- aa_issue_token(con, "ivan")

  aa_delete_user(con, "ivan", acting_login = "admin")
  raw_user(con, "ivan")

  expect_null(aa_find_session_user(con, token))
})

test_that("токен другого регистра логина не подходит", {
  con <- users_db()
  raw_user(con, "kiruka")
  raw_user(con, "Kiruka")
  token <- aa_issue_token(con, "kiruka")

  expect_equal(aa_find_session_user(con, token)$login, "kiruka")
})

test_that("старые токены Server Manager (sha256 как текст) продолжают работать", {
  con <- new_db()
  fixture_server_manager_prod(con)
  aa_init_db(con)
  DBI::dbExecute(con, "UPDATE auth_sessions SET token_hash = ? WHERE token_hash = 'tok1'",
                 params = list(as.character(openssl::sha256("raw-cookie"))))

  expect_equal(aa_find_session_user(con, "raw-cookie")$login, "alsey")
})

test_that("проверка живой сессии: действует, пока всё совпадает", {
  con <- users_db()
  raw_user(con, "ivan", "user")

  res <- aa_user_session_valid(con, "ivan", "user")

  expect_true(res$valid)
  expect_equal(res$reason, "ok")
  expect_equal(res$role, "user")
})

test_that("проверка живой сессии видит блокировку, удаление и смену роли", {
  con <- users_db()
  raw_user(con, "admin", "admin")
  raw_user(con, "ivan", "user")
  raw_user(con, "petr", "admin")
  raw_user(con, "olga", "user")

  aa_set_blocked(con, "ivan", TRUE, acting_login = "admin")
  aa_delete_user(con, "petr", acting_login = "admin")
  aa_set_role(con, "olga", "viewer")

  blocked <- aa_user_session_valid(con, "ivan", "user")
  deleted <- aa_user_session_valid(con, "petr", "admin")
  changed <- aa_user_session_valid(con, "olga", "user")

  expect_false(blocked$valid)
  expect_equal(blocked$reason, "blocked")
  expect_false(deleted$valid)
  expect_equal(deleted$reason, "deleted")
  expect_null(deleted$role)
  expect_false(changed$valid)
  expect_equal(changed$reason, "role_changed")
  expect_equal(changed$role, "viewer")
})

test_that("понижение роли вступает в силу и для повышения", {
  con <- users_db()
  raw_user(con, "admin", "admin")
  raw_user(con, "ivan", "user")
  aa_set_role(con, "ivan", "admin")

  expect_equal(aa_user_session_valid(con, "ivan", "user")$reason, "role_changed")
})

test_that("проверка живой сессии при сбое базы не выбрасывает пользователя", {
  con <- users_db()
  raw_user(con, "ivan", "user")
  DBI::dbExecute(con, "DROP TABLE users")

  res <- aa_user_session_valid(con, "ivan", "user")

  expect_true(res$valid)
  expect_equal(res$reason, "check_failed")
})

test_that("логин другого регистра не считается тем же пользователем", {
  con <- users_db()
  raw_user(con, "kiruka", "user")

  expect_equal(aa_user_session_valid(con, "Kiruka", "user")$reason, "deleted")
})
