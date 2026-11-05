must_change_of <- function(con, login) {
  tquery(con, "SELECT must_change FROM users WHERE login = ?", params = list(login))$must_change
}

test_that("создание с must_change и вход возвращают признак", {
  con <- users_db()
  aa_create_user(con, "ann", "secret123", "user", must_change = TRUE)
  aa_create_user(con, "bob", "secret123", "user")

  expect_equal(must_change_of(con, "ann"), 1)
  expect_equal(must_change_of(con, "bob"), 0)
  expect_equal(aa_authenticate(con, "ann", "secret123")$must_change, 1)
  expect_equal(aa_authenticate(con, "bob", "secret123")$must_change, 0)
  expect_named(aa_authenticate(con, "bob", "secret123"), c("login", "role", "blocked", "must_change"))
})

test_that("сброс пароля может потребовать смену, обычная установка снимает требование", {
  con <- users_db()
  aa_create_user(con, "ann", "secret123", "user")

  aa_set_password(con, "ann", "another123", must_change = TRUE)
  expect_equal(must_change_of(con, "ann"), 1)

  aa_set_password(con, "ann", "third12345")
  expect_equal(must_change_of(con, "ann"), 0)
})

test_that("keep_token оставляет текущий токен и отзывает остальные", {
  con <- users_db()
  raw_user(con, "ann")
  keep <- aa_issue_token(con, "ann")
  other <- aa_issue_token(con, "ann")

  aa_set_password(con, "ann", "another123", keep_token = keep)

  expect_false(is.null(aa_find_session_user(con, keep)))
  expect_null(aa_find_session_user(con, other))
})

test_that("токен пользователя, обязанного сменить пароль, в приложение не пускает", {
  con <- users_db()
  raw_user(con, "ann")
  token <- aa_issue_token(con, "ann")
  texec(con, "UPDATE users SET must_change = 1 WHERE login = 'ann'")

  expect_null(aa_find_session_user(con, token))
})

test_that("смена своего пароля: успех, проверка нового, снятие требования, токены", {
  con <- users_db()
  aa_create_user(con, "ann", "secret123", "user", must_change = TRUE)
  raw_keep <- NULL
  texec(con, "UPDATE users SET must_change = 0")
  keep <- aa_issue_token(con, "ann")
  other <- aa_issue_token(con, "ann")
  texec(con, "UPDATE users SET must_change = 1")

  expect_true(aa_change_own_password(con, "ann", "secret123", "brand-new-1", keep_token = keep))

  expect_equal(must_change_of(con, "ann"), 0)
  expect_null(aa_authenticate(con, "ann", "secret123"))
  expect_false(is.null(aa_authenticate(con, "ann", "brand-new-1")))
  expect_false(is.null(aa_find_session_user(con, keep)))
  expect_null(aa_find_session_user(con, other))
})

test_that("смена своего пароля: неверный текущий, тот же, слабый, заблокированный, чужой логин", {
  con <- users_db()
  aa_create_user(con, "ann", "secret123", "user")
  hash_before <- stored_password(con, "ann")

  err <- function(...) tryCatch(aa_change_own_password(con, ...), appauth_error_user = function(e) e)

  e1 <- err("ann", "wrong-pass", "brand-new-1")
  expect_s3_class(e1, "appauth_error_user")
  expect_equal(e1$reason, "password_wrong")
  expect_equal(err("ann", "secret123", "secret123")$reason, "password_same")
  expect_equal(err("ann", "secret123", "123")$reason, "password_too_short")
  expect_equal(err("ghost", "secret123", "brand-new-1")$reason, "password_wrong")
  expect_equal(err("ann", "", "brand-new-1")$reason, "password_wrong")

  texec(con, "UPDATE users SET blocked = 1 WHERE login = 'ann'")
  expect_equal(err("ann", "secret123", "brand-new-1")$reason, "password_wrong")

  expect_equal(stored_password(con, "ann"), hash_before)
})

test_that("сообщения смены пароля на языке настроек", {
  con <- users_db()
  aa_create_user(con, "ann", "secret123", "user")
  settings <- aa_settings(texts = aa_texts("en"))

  e <- tryCatch(aa_change_own_password(con, "ann", "bad", "brand-new-1", settings), appauth_error_user = function(e) e)

  expect_equal(conditionMessage(e), "The current password is incorrect")
})

test_that("завершение сессий отзывает все токены пользователя и только его", {
  con <- users_db()
  raw_user(con, "ann")
  raw_user(con, "bob")
  t1 <- aa_issue_token(con, "ann")
  t2 <- aa_issue_token(con, "ann")
  tb <- aa_issue_token(con, "bob")

  expect_equal(aa_revoke_sessions(con, "ann"), 2)

  expect_null(aa_find_session_user(con, t1))
  expect_null(aa_find_session_user(con, t2))
  expect_false(is.null(aa_find_session_user(con, tb)))
  expect_equal(aa_revoke_sessions(con, ""), 0)
  expect_equal(aa_revoke_sessions(con, NULL), 0)
})

test_that("проверка сессии видит отозванный токен, без токена не проверяет его", {
  con <- users_db()
  raw_user(con, "ann", "user")
  token <- aa_issue_token(con, "ann")

  expect_true(aa_user_session_valid(con, "ann", "user", token)$valid)

  aa_revoke_sessions(con, "ann")
  res <- aa_user_session_valid(con, "ann", "user", token)
  expect_false(res$valid)
  expect_equal(res$reason, "token_revoked")

  expect_true(aa_user_session_valid(con, "ann", "user")$valid)
  expect_true(aa_user_session_valid(con, "ann", "user", NULL)$valid)
  expect_true(aa_user_session_valid(con, "ann", "user", "")$valid)
})

test_that("истёкший токен сессии тоже недействителен", {
  con <- users_db()
  raw_user(con, "ann", "user")
  token <- aa_issue_token(con, "ann")
  texec(con, "UPDATE auth_sessions SET expires_at = datetime('now', '-1 seconds')")

  expect_equal(aa_user_session_valid(con, "ann", "user", token)$reason, "token_revoked")
})

test_that("сторож завершает сессию при отозванном токене и чистит устаревшее", {
  con <- users_db()
  raw_user(con, "ann", "user")
  token <- aa_issue_token(con, "ann")
  add_attempt(con, "old", FALSE, minutes_ago = 60 * 24 * 3)
  expect_equal(count_attempts(con), 1)

  auth <- fake_auth_obj("ann", "user")
  auth$token <- function() token

  with_guard(con, auth, cleanup_minutes = 0, {
    session$flushReact()
    session$elapse(35000)
    expect_length(auth$calls$logout, 0)
    expect_equal(count_attempts(con), 0)

    aa_revoke_sessions(con, "ann")
    session$elapse(35000)
  })

  expect_equal(auth$calls$logout[[1]]$reason, "token_revoked")
})

test_that("модуль входа: пароль от администратора требует смены, в приложение не пускает", {
  con <- users_db()
  aa_create_user(con, "ann", "secret123", "user", must_change = TRUE)

  log <- run_auth(con, {
    session$setInputs(login = "ann", password = "secret123", login_btn = 1)
    expect_false(session$returned$logged_in())
    expect_match(form_html(output), "change_btn", fixed = TRUE)
    expect_match(form_html(output), "Смените пароль", fixed = TRUE)
    expect_equal(nrow(rows_of(con, "auth_sessions")), 0)

    session$setInputs(change_password = "brand-new-1", change_confirm = "other", change_btn = 1)
    expect_equal(output$message, "Пароли не совпадают")
    expect_false(session$returned$logged_in())

    session$setInputs(change_password = "123", change_confirm = "123", change_btn = 2)
    expect_match(output$message, "минимум")
    expect_false(session$returned$logged_in())

    session$setInputs(change_password = "secret123", change_confirm = "secret123", change_btn = 3)
    expect_match(output$message, "отличаться")
    expect_false(session$returned$logged_in())

    session$setInputs(change_password = "brand-new-1", change_confirm = "brand-new-1", change_btn = 4)
    expect_true(session$returned$logged_in())
    expect_equal(session$returned$user(), list(login = "ann", role = "user"))
    expect_true(nzchar(session$returned$token()))
  })

  expect_equal(log$names(), c("password_changed", "login_success"))
  expect_equal(must_change_of(con, "ann"), 0)
  expect_false(is.null(aa_authenticate(con, "ann", "brand-new-1")))
  expect_null(aa_authenticate(con, "ann", "secret123"))
  expect_equal(nrow(rows_of(con, "auth_sessions")), 1)
})

test_that("модуль входа: перезагрузка во время смены пароля начинает заново с пароля", {
  con <- users_db()
  aa_create_user(con, "ann", "secret123", "user", must_change = TRUE)

  run_auth(con, {
    session$setInputs(login = "ann", password = "secret123", login_btn = 1)
    expect_false(session$returned$logged_in())
  })

  # новая сессия: без пароля пользователь не вошёл
  run_auth(con, {
    session$flushReact()
    expect_match(form_html(output), "login_btn", fixed = TRUE)
    expect_false(session$returned$logged_in())
  })
})

test_that("модуль входа отдаёт токен сессии для сторожа", {
  con <- users_db()
  aa_create_user(con, "ann", "secret123", "user")

  run_auth(con, {
    expect_null(session$returned$token())
    session$setInputs(login = "ann", password = "secret123", login_btn = 1)
    expect_equal(aa_find_session_user(con, session$returned$token())$login, "ann")
  })
})

test_that("модуль смены пароля: успех меняет пароль, событие, токен текущей сессии остаётся", {
  con <- users_db()
  aa_create_user(con, "ann", "secret123", "user")
  keep <- aa_issue_token(con, "ann")
  other <- aa_issue_token(con, "ann")
  auth <- fake_auth("ann", "user")
  auth$token <- function() keep

  log <- password_run(con, auth, {
    session$flushReact()
    expect_match(paste(as.character(output$form$html), collapse = ""), "change", fixed = TRUE)

    session$setInputs(old = "secret123", new = "brand-new-1", confirm = "brand-new-1", change = 1)
    expect_equal(session$returned$changed(), 1)
  })

  expect_equal(log$names(), "password_changed")
  expect_false(is.null(aa_authenticate(con, "ann", "brand-new-1")))
  expect_false(is.null(aa_find_session_user(con, keep)))
  expect_null(aa_find_session_user(con, other))
})

test_that("модуль смены пароля: ошибки показываются, пароль не меняется", {
  con <- users_db()
  aa_create_user(con, "ann", "secret123", "user")
  auth <- fake_auth("ann", "user")

  log <- password_run(con, auth, {
    session$setInputs(old = "secret123", new = "brand-new-1", confirm = "different", change = 1)
    expect_equal(output$message, "Пароли не совпадают")

    session$setInputs(old = "wrong", new = "brand-new-1", confirm = "brand-new-1", change = 2)
    expect_equal(output$message, "Неверный текущий пароль")

    session$setInputs(old = "secret123", new = "123", confirm = "123", change = 3)
    expect_match(output$message, "минимум")

    session$setInputs(old = "secret123", new = "secret123", confirm = "secret123", change = 4)
    expect_match(output$message, "отличаться")

    expect_equal(session$returned$changed(), 0)
  })

  expect_length(log$events, 0)
  expect_false(is.null(aa_authenticate(con, "ann", "secret123")))
})

test_that("модуль смены пароля ничего не показывает без пользователя", {
  con <- users_db()

  password_run(con, list(user = shiny::reactiveVal(NULL)), {
    session$flushReact()
    # без пользователя форма не строится (тихая остановка renderUI)
    expect_error(output$form, class = "shiny.silent.error")
  })
})

test_that("модуль пользователей: сброс пароля требует смену по умолчанию, галочку можно снять", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(new_password = "newpass123", new_password_confirm = "newpass123", reset_must_change = TRUE, reset_password = 1)
    expect_equal(must_change_of(con, "ivan"), 1)

    session$setInputs(open = "ivan")
    session$setInputs(new_password = "newpass456", new_password_confirm = "newpass456", reset_must_change = FALSE, reset_password = 2)
    expect_equal(must_change_of(con, "ivan"), 0)
  })

  expect_equal(log$names(), c("password_reset", "password_reset"))
})

test_that("модуль пользователей: новый пользователь с обязательной сменой пароля", {
  con <- users_fixture()

  run_users(con, {
    session$setInputs(add = 1)
    session$setInputs(new_login = "olga", new_user_password = "secret123", new_user_confirm = "secret123",
                      new_user_role = "viewer", new_user_must_change = TRUE, add_confirm = 1)
    session$setInputs(new_login = "petr", new_user_password = "secret123", new_user_confirm = "secret123",
                      new_user_role = "viewer", new_user_must_change = FALSE, add_confirm = 2)
  })

  expect_equal(must_change_of(con, "olga"), 1)
  expect_equal(must_change_of(con, "petr"), 0)
})

test_that("модуль пользователей: завершение всех сессий отзывает токены и шлёт событие", {
  con <- users_fixture()
  t1 <- aa_issue_token(con, "ivan")
  t2 <- aa_issue_token(con, "ivan")

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(revoke = 1)
  })

  expect_null(aa_find_session_user(con, t1))
  expect_null(aa_find_session_user(con, t2))
  expect_equal(log$names(), "sessions_revoked")
  expect_equal(log$events[[1]]$value, "ivan")
})

test_that("завершение сессий без открытой карточки или не администратором ничего не делает", {
  con <- users_fixture()
  token <- aa_issue_token(con, "ivan")

  run_users(con, { session$setInputs(revoke = 1) })
  run_users(con, auth = fake_auth("ivan", "user"), {
    session$setInputs(open = "ivan")
    session$setInputs(revoke = 1)
  })

  expect_false(is.null(aa_find_session_user(con, token)))
})
