# Помощники этого файла ---------------------------------------------------------

# База со схемой авторизации, закрывается в конце теста
users_db <- function(env = parent.frame()) {
  con <- new_db(env)
  aa_init_db(con)
  con
}

# Создаёт пользователей без проверок и без медленного хеширования
# (для тестов, где важна только структура данных, а не пароль)
raw_user <- function(con, login, role = "user", blocked = 0, password = "x") {
  DBI::dbExecute(
    con, "INSERT INTO users (login, password, role, blocked) VALUES (?, ?, ?, ?)",
    params = list(login, password, role, blocked)
  )
}

raw_token <- function(con, login, hash, revoked = 0) {
  DBI::dbExecute(
    con,
    "INSERT INTO auth_sessions (user_login, token_hash, expires_at, revoked)
     VALUES (?, ?, datetime('now', '+30 days'), ?)",
    params = list(login, hash, revoked)
  )
}

revoked_of <- function(con, hash) {
  DBI::dbGetQuery(con, "SELECT revoked FROM auth_sessions WHERE token_hash = ?", params = list(hash))$revoked
}

count_users <- function(con) DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM users")$n

stored_password <- function(con, login) {
  DBI::dbGetQuery(con, "SELECT password FROM users WHERE login = ?", params = list(login))$password
}

# ---- чтение ---------------------------------------------------------------------

test_that("aa_get_user и aa_list_users не возвращают пароль, логин сравнивается точно", {
  con <- users_db()
  raw_user(con, "alsey", "admin")
  raw_user(con, "Ida", "viewer", blocked = 1)

  expect_identical(names(aa_get_user(con, "alsey")), c("login", "role", "blocked"))
  expect_identical(aa_get_user(con, "alsey")$role, "admin")
  expect_identical(aa_get_user(con, "Ida")$blocked, 1L)
  expect_null(aa_get_user(con, "ida"))
  expect_null(aa_get_user(con, "Alsey"))
  expect_null(aa_get_user(con, " alsey"))

  for (bad in list(NULL, NA_character_, "", 5, c("alsey", "Ida"))) {
    expect_null(aa_get_user(con, bad))
  }

  users <- aa_list_users(con)
  expect_identical(names(users), c("login", "role", "blocked"))
  expect_identical(users$login, c("alsey", "Ida"))
})

test_that("aa_users_exist", {
  con <- users_db()

  expect_false(aa_users_exist(con))
  raw_user(con, "a")
  expect_true(aa_users_exist(con))
})

test_that("функции пользователей отклоняют не SQLite подключение", {
  expect_error(aa_get_user(list(), "a"), class = "appauth_error_connection")
  expect_error(aa_list_users(list()), class = "appauth_error_connection")
  expect_error(aa_create_user(list(), "a", "password1", "user"), class = "appauth_error_connection")
  expect_error(aa_authenticate(list(), "a", "b"), class = "appauth_error_connection")
})

# ---- создание ---------------------------------------------------------------------

test_that("aa_create_user создаёт пользователя с хешем пароля и без блокировки", {
  con <- users_db()

  res <- withVisible(aa_create_user(con, "worker", "worker-password", "user"))

  expect_false(res$visible)
  expect_true(res$value)

  user <- aa_get_user(con, "worker")
  expect_identical(user$role, "user")
  expect_identical(user$blocked, 0L)
  expect_true(aa_is_password_hash(stored_password(con, "worker")))
  expect_true(aa_verify_password("worker-password", stored_password(con, "worker")))
})

test_that("aa_create_user отклоняет некорректные данные с причиной и текстом, ничего не создавая", {
  con <- users_db()

  cases <- list(
    list(args = list("", "worker-password", "user"),       reason = "login_empty"),
    list(args = list(" worker", "worker-password", "user"), reason = "login_whitespace"),
    list(args = list(strrep("a", 65), "worker-password", "user"), reason = "login_too_long"),
    list(args = list("worker", "short", "user"),           reason = "password_too_short"),
    list(args = list("worker", "", "user"),                reason = "password_empty"),
    list(args = list("worker", "worker-password", "boss"), reason = "invalid_role"),
    list(args = list("worker", "worker-password", NULL),   reason = "invalid_role"),
    list(args = list("worker", "worker-password", NA_character_), reason = "invalid_role")
  )

  for (case in cases) {
    err <- expect_error(do.call(aa_create_user, c(list(con), case$args)), class = "appauth_error_user", info = case$reason)
    expect_identical(err$reason, case$reason, info = case$reason)
  }

  expect_identical(count_users(con), 0L)

  err <- expect_error(aa_create_user(con, "worker", "short", "user"), class = "appauth_error_user")
  expect_identical(conditionMessage(err), "Пароль должен содержать минимум 6 символов")
})

test_that("тексты ошибок создания на английском", {
  con <- users_db()
  s <- aa_settings(texts = aa_texts("en"))

  err <- expect_error(aa_create_user(con, "worker", "x", "user", s), class = "appauth_error_user")
  expect_identical(conditionMessage(err), "Password must be at least 6 characters long")

  err <- expect_error(aa_create_user(con, "worker", "worker-password", "boss", s), class = "appauth_error_user")
  expect_identical(conditionMessage(err), "Invalid role")
})

test_that("роль проверяется по списку из настроек", {
  con <- users_db()
  s <- aa_settings(roles = c("boss", "editor"), admin_role = "boss")

  expect_error(aa_create_user(con, "a", "password1", "user", s), class = "appauth_error_user")
  expect_no_error(aa_create_user(con, "a", "password1", "editor", s))
  expect_identical(aa_get_user(con, "a")$role, "editor")
})

test_that("занятый логин отклоняется: точное совпадение и отличие только регистром (в том числе кириллица)", {
  con <- users_db()
  aa_create_user(con, "Worker", "worker-password", "user")
  aa_create_user(con, "Иван", "ivan-password", "user")

  expect_identical(
    expect_error(aa_create_user(con, "Worker", "other-password", "user"), class = "appauth_error_user")$reason,
    "user_exists"
  )

  for (login in c("worker", "WORKER", "wOrKeR", "иван", "ИВАН")) {
    err <- expect_error(aa_create_user(con, login, "other-password", "user"), class = "appauth_error_user", info = login)
    expect_identical(err$reason, "user_exists_case", info = login)
  }

  expect_identical(count_users(con), 2L)

  expect_identical(
    conditionMessage(expect_error(aa_create_user(con, "worker", "other-password", "user"), class = "appauth_error_user")),
    "Пользователь с таким логином уже существует (логины различаются только регистром)"
  )
})

test_that("существующие пары логинов, различающиеся регистром, сохраняются и работают как разные пользователи", {
  con <- users_db()

  DBI::dbExecute(con, "INSERT INTO users (login, password, role) VALUES (?, ?, 'user')",
                 params = list("kiruka", aa_hash_password("password-one")))
  DBI::dbExecute(con, "INSERT INTO users (login, password, role) VALUES (?, ?, 'user')",
                 params = list("Kiruka", aa_hash_password("password-two")))

  expect_identical(aa_list_users(con)$login, c("kiruka", "Kiruka"))
  expect_identical(aa_authenticate(con, "kiruka", "password-one")$login, "kiruka")
  expect_identical(aa_authenticate(con, "Kiruka", "password-two")$login, "Kiruka")
  expect_null(aa_authenticate(con, "kiruka", "password-two"))
  expect_null(aa_authenticate(con, "KIRUKA", "password-one"))

  # третий вариант написания создать нельзя
  expect_error(aa_create_user(con, "KIRUKA", "password-three", "user"), class = "appauth_error_user")
})

test_that("aa_validate_new_user возвращает текст проблемы и ничего не создаёт", {
  con <- users_db()
  aa_create_user(con, "worker", "worker-password", "user")

  expect_null(aa_validate_new_user(con, "other", "other-password", "user"))
  expect_identical(aa_validate_new_user(con, "Worker", "other-password", "user"),
                   "Пользователь с таким логином уже существует (логины различаются только регистром)")
  expect_identical(aa_validate_new_user(con, "other", "x", "user"), "Пароль должен содержать минимум 6 символов")
  expect_identical(aa_validate_new_user(con, "other", "other-password", "boss"), "Недопустимая роль")
  expect_identical(count_users(con), 1L)
})

# ---- первый администратор -------------------------------------------------------

test_that("первый администратор создаётся с ролью администратора только на пустой таблице", {
  con <- users_db()

  expect_true(aa_create_first_admin(con, "boss", "boss-password"))

  boss <- aa_get_user(con, "boss")
  expect_identical(boss$role, "admin")
  expect_identical(boss$blocked, 0L)
  expect_true(aa_verify_password("boss-password", stored_password(con, "boss")))

  expect_false(aa_create_first_admin(con, "second", "second-password"))
  expect_identical(count_users(con), 1L)
  expect_null(aa_get_user(con, "second"))
})

test_that("первый администратор не создаётся, если пользователи уже есть (в том числе созданные иначе)", {
  con <- users_db()
  raw_user(con, "existing")

  expect_false(aa_create_first_admin(con, "boss", "boss-password"))
  expect_identical(count_users(con), 1L)
})

test_that("для первого администратора роль берётся из настроек, данные проверяются", {
  con <- users_db()
  s <- aa_settings(roles = c("owner", "user"), admin_role = "owner")

  expect_error(aa_create_first_admin(con, "", "boss-password", s), class = "appauth_error_user")
  expect_error(aa_create_first_admin(con, " boss", "boss-password", s), class = "appauth_error_user")
  expect_error(aa_create_first_admin(con, "boss", "short", s), class = "appauth_error_user")
  expect_identical(count_users(con), 0L)

  expect_true(aa_create_first_admin(con, "boss", "boss-password", s))
  expect_identical(aa_get_user(con, "boss")$role, "owner")
})

# ---- вход ------------------------------------------------------------------------

test_that("aa_authenticate: верный пароль даёт login, role и blocked без пароля", {
  con <- users_db()
  aa_create_user(con, "worker", "worker-password", "user")

  res <- aa_authenticate(con, "worker", "worker-password")

  expect_identical(names(res), c("login", "role", "blocked"))
  expect_identical(res$login, "worker")
  expect_identical(res$role, "user")
  expect_identical(res$blocked, 0L)
  expect_identical(nrow(res), 1L)
})

test_that("aa_authenticate: неверные данные дают NULL, логин сравнивается точно", {
  con <- users_db()
  aa_create_user(con, "worker", "worker-password", "user")

  expect_null(aa_authenticate(con, "worker", "wrong"))
  expect_null(aa_authenticate(con, "nobody", "worker-password"))
  expect_null(aa_authenticate(con, "Worker", "worker-password"))
  expect_null(aa_authenticate(con, " worker", "worker-password"))

  for (bad in list(NULL, NA_character_, "", 5, c("a", "b"))) {
    expect_null(aa_authenticate(con, bad, "worker-password"))
    expect_null(aa_authenticate(con, "worker", bad))
  }
})

test_that("aa_authenticate: SQL-инъекции не работают", {
  con <- users_db()
  aa_create_user(con, "worker", "worker-password", "user")

  for (login in c("worker' --", "' OR '1'='1", "worker'; DROP TABLE users;--", "\" OR \"\"=\"")) {
    expect_null(aa_authenticate(con, login, "x"), info = login)
    expect_null(aa_authenticate(con, login, "' OR '1'='1"), info = login)
  }

  expect_null(aa_authenticate(con, "worker", "' OR '1'='1"))
  expect_identical(count_users(con), 1L)
  expect_true("users" %in% DBI::dbListTables(con))
})

test_that("aa_authenticate: заблокированный пользователь с верным паролем возвращается с blocked = 1, с неверным NULL", {
  con <- users_db()
  aa_create_user(con, "worker", "worker-password", "user")
  DBI::dbExecute(con, "UPDATE users SET blocked = 1 WHERE login = 'worker'")

  res <- aa_authenticate(con, "worker", "worker-password")

  expect_identical(res$blocked, 1L)
  expect_null(aa_authenticate(con, "worker", "wrong"))
})

test_that("aa_authenticate: пароль в открытом виде в базе никогда не принимается", {
  con <- users_db()
  raw_user(con, "legacy", password = "secret12")

  expect_null(aa_authenticate(con, "legacy", "secret12"))

  # и хеш в качестве пароля не принимается
  aa_create_user(con, "worker", "worker-password", "user")
  expect_null(aa_authenticate(con, "worker", stored_password(con, "worker")))
})

test_that("aa_authenticate: проверка выполняется и для несуществующего логина (на фиктивном хеше)", {
  con <- users_db()
  aa_create_user(con, "worker", "worker-password", "user")

  dummy <- aa_dummy_hash()
  worker_hash <- stored_password(con, "worker")
  calls <- character()

  testthat::local_mocked_bindings(
    aa_verify_password = function(password, stored) {
      calls <<- c(calls, stored)
      FALSE
    }
  )

  aa_authenticate(con, "nobody", "any-password")
  expect_identical(calls, dummy)

  calls <- character()
  aa_authenticate(con, "worker", "wrong")
  expect_identical(calls, worker_hash)
})

test_that("aa_authenticate работает и без колонки blocked (старая схема)", {
  testthat::skip_if_not_installed("RSQLite")
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(con))

  DBI::dbExecute(con, "CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, login TEXT UNIQUE NOT NULL, password TEXT NOT NULL, role TEXT NOT NULL)")
  DBI::dbExecute(con, "INSERT INTO users (login, password, role) VALUES (?, ?, 'user')",
                 params = list("old", aa_hash_password("old-password")))

  res <- aa_authenticate(con, "old", "old-password")

  expect_identical(res$login, "old")
  expect_identical(res$blocked, 0L)
  expect_null(aa_authenticate(con, "old", "wrong"))
})

# ---- смена пароля --------------------------------------------------------------

test_that("aa_set_password меняет пароль и отзывает токены только этого пользователя", {
  con <- users_db()
  aa_create_user(con, "worker", "old-password", "user")
  aa_create_user(con, "other", "other-password", "user")
  raw_token(con, "worker", "t1"); raw_token(con, "worker", "t2"); raw_token(con, "other", "t3")

  expect_identical(aa_set_password(con, "worker", "new-password"), 1L)

  expect_null(aa_authenticate(con, "worker", "old-password"))
  expect_identical(aa_authenticate(con, "worker", "new-password")$login, "worker")
  expect_identical(revoked_of(con, "t1"), 1L)
  expect_identical(revoked_of(con, "t2"), 1L)
  expect_identical(revoked_of(con, "t3"), 0L)
  expect_identical(aa_authenticate(con, "other", "other-password")$login, "other")
})

test_that("aa_set_password: слабый пароль отклоняется, ничего не меняется", {
  con <- users_db()
  aa_create_user(con, "worker", "old-password", "user")
  raw_token(con, "worker", "t1")
  before <- stored_password(con, "worker")

  err <- expect_error(aa_set_password(con, "worker", "short"), class = "appauth_error_user")

  expect_identical(err$reason, "password_too_short")
  expect_identical(stored_password(con, "worker"), before)
  expect_identical(revoked_of(con, "t1"), 0L)
})

test_that("aa_set_password для несуществующего логина возвращает 0 и ничего не делает", {
  con <- users_db()
  raw_token(con, "ghost", "t1")

  expect_identical(aa_set_password(con, "ghost", "new-password"), 0L)
  expect_identical(aa_set_password(con, NA_character_, "new-password"), 0L)
  expect_identical(revoked_of(con, "t1"), 0L)
})

# ---- смена роли -----------------------------------------------------------------

test_that("aa_set_role меняет роль на допустимую", {
  con <- users_db()
  raw_user(con, "boss", "admin"); raw_user(con, "worker", "user")

  expect_identical(aa_set_role(con, "worker", "viewer"), 1L)
  expect_identical(aa_get_user(con, "worker")$role, "viewer")
  expect_null(aa_check_can_change_role(con, "worker", "admin"))
})

test_that("aa_set_role: недопустимая роль, неизвестный и пустой пользователь отклоняются", {
  con <- users_db()
  raw_user(con, "worker", "user")

  expect_identical(expect_error(aa_set_role(con, "worker", "boss"), class = "appauth_error_user")$reason, "invalid_role")
  expect_identical(expect_error(aa_set_role(con, "ghost", "viewer"), class = "appauth_error_user")$reason, "user_not_found")
  expect_identical(expect_error(aa_set_role(con, NA_character_, "viewer"), class = "appauth_error_user")$reason, "user_not_specified")
  expect_identical(aa_get_user(con, "worker")$role, "user")
})

test_that("нельзя снять роль администратора у последнего активного администратора", {
  con <- users_db()
  raw_user(con, "boss", "admin")
  raw_user(con, "second", "admin", blocked = 1)
  raw_user(con, "worker", "user")

  err <- expect_error(aa_set_role(con, "boss", "user"), class = "appauth_error_user")

  expect_identical(err$reason, "cannot_change_last_admin_role")
  expect_identical(conditionMessage(err), "Нельзя снять роль администратора у последнего активного администратора")
  expect_identical(aa_get_user(con, "boss")$role, "admin")

  # если есть другой активный администратор, роль снять можно
  raw_user(con, "third", "admin")
  expect_identical(aa_set_role(con, "boss", "user"), 1L)
  expect_identical(aa_get_user(con, "boss")$role, "user")

  # а того, кто остался единственным, снова нельзя
  expect_error(aa_set_role(con, "third", "viewer"), class = "appauth_error_user")
})

test_that("смена роли администратора на администратора и обычного пользователя на любую допустима", {
  con <- users_db()
  raw_user(con, "boss", "admin")

  expect_identical(aa_set_role(con, "boss", "admin"), 1L)
  expect_null(aa_check_can_change_role(con, "boss", "admin"))
  expect_identical(
    aa_check_can_change_role(con, "boss", "user"),
    "Нельзя снять роль администратора у последнего активного администратора"
  )
})

# ---- блокировка -----------------------------------------------------------------

test_that("aa_set_blocked блокирует, отзывает токены и разблокирует", {
  con <- users_db()
  raw_user(con, "boss", "admin"); raw_user(con, "worker", "user"); raw_user(con, "other", "user")
  raw_token(con, "worker", "t1"); raw_token(con, "other", "t2")

  expect_identical(aa_set_blocked(con, "worker", TRUE, acting_login = "boss"), 1L)

  expect_identical(aa_get_user(con, "worker")$blocked, 1L)
  expect_identical(revoked_of(con, "t1"), 1L)
  expect_identical(revoked_of(con, "t2"), 0L)

  expect_identical(aa_set_blocked(con, "worker", FALSE), 1L)
  expect_identical(aa_get_user(con, "worker")$blocked, 0L)
  # отозванные при блокировке токены не восстанавливаются
  expect_identical(revoked_of(con, "t1"), 1L)
})

test_that("нельзя заблокировать себя и последнего активного администратора", {
  con <- users_db()
  raw_user(con, "boss", "admin"); raw_user(con, "second", "admin"); raw_user(con, "worker", "user")

  expect_identical(
    expect_error(aa_set_blocked(con, "boss", TRUE, acting_login = "boss"), class = "appauth_error_user")$reason,
    "cannot_block_self"
  )

  expect_identical(aa_set_blocked(con, "second", TRUE, acting_login = "boss"), 1L)

  err <- expect_error(aa_set_blocked(con, "boss", TRUE, acting_login = "worker"), class = "appauth_error_user")
  expect_identical(err$reason, "cannot_block_last_admin")
  expect_identical(aa_get_user(con, "boss")$blocked, 0L)

  # без acting_login (вызов из скрипта) правило последнего администратора всё равно действует
  expect_error(aa_set_blocked(con, "boss", TRUE), class = "appauth_error_user")
})

test_that("aa_set_blocked: неизвестный пользователь при блокировке ошибка, при разблокировке 0", {
  con <- users_db()
  raw_user(con, "boss", "admin")

  expect_identical(
    expect_error(aa_set_blocked(con, "ghost", TRUE), class = "appauth_error_user")$reason,
    "user_not_found"
  )
  expect_identical(aa_set_blocked(con, "ghost", FALSE), 0L)
  expect_error(aa_set_blocked(con, "boss", NA), class = "appauth_error_settings")
})

test_that("aa_check_can_block и aa_check_can_delete возвращают понятные тексты", {
  con <- users_db()
  raw_user(con, "boss", "admin"); raw_user(con, "worker", "user")

  expect_null(aa_check_can_block(con, "worker", "boss"))
  expect_null(aa_check_can_delete(con, "worker", "boss"))
  expect_identical(aa_check_can_block(con, "boss", "boss"), "Нельзя заблокировать самого себя")
  expect_identical(aa_check_can_delete(con, "boss", "boss"), "Нельзя удалить самого себя")
  expect_identical(aa_check_can_block(con, "boss", "worker"), "Нельзя заблокировать последнего активного администратора")
  expect_identical(aa_check_can_delete(con, "boss", "worker"), "Нельзя удалить последнего активного администратора")
  expect_identical(aa_check_can_block(con, "ghost", "boss"), "Пользователь не найден")
  expect_identical(aa_check_can_delete(con, "", "boss"), "Пользователь не указан")
  expect_identical(aa_check_can_delete(con, NULL, "boss"), "Пользователь не указан")

  en <- aa_settings(texts = aa_texts("en"))
  expect_identical(aa_check_can_block(con, "boss", "boss", en), "You cannot block yourself")
  expect_identical(aa_check_can_delete(con, "boss", "worker", en), "You cannot delete the last active administrator")
})

test_that("заблокированный администратор не считается активным", {
  con <- users_db()
  raw_user(con, "boss", "admin")
  raw_user(con, "blocked_admin", "admin", blocked = 1)

  expect_identical(aa_check_can_block(con, "boss", "x"), "Нельзя заблокировать последнего активного администратора")
  # заблокированного администратора удалить можно, пока есть активный
  expect_null(aa_check_can_delete(con, "blocked_admin", "boss"))
})

# ---- удаление -------------------------------------------------------------------

test_that("aa_delete_user удаляет пользователя, его токены и неудачные попытки входа", {
  con <- users_db()
  raw_user(con, "boss", "admin"); raw_user(con, "worker", "user"); raw_user(con, "other", "user")
  raw_token(con, "worker", "t1"); raw_token(con, "worker", "t2", revoked = 1); raw_token(con, "other", "t3")
  DBI::dbExecute(con, "INSERT INTO login_attempts (login, success) VALUES ('worker', 0), ('worker', 0), ('other', 0)")

  expect_identical(aa_delete_user(con, "worker", acting_login = "boss"), 1L)

  expect_null(aa_get_user(con, "worker"))
  expect_identical(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM auth_sessions WHERE user_login = 'worker'")$n, 0L)
  expect_identical(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM login_attempts WHERE login = 'worker'")$n, 0L)
  # данные других пользователей не затронуты
  expect_identical(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM auth_sessions WHERE user_login = 'other'")$n, 1L)
  expect_identical(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM login_attempts WHERE login = 'other'")$n, 1L)
  expect_identical(count_users(con), 2L)
})

test_that("нельзя удалить себя и последнего активного администратора", {
  con <- users_db()
  raw_user(con, "boss", "admin"); raw_user(con, "worker", "user")

  expect_identical(
    expect_error(aa_delete_user(con, "boss", acting_login = "boss"), class = "appauth_error_user")$reason,
    "cannot_delete_self"
  )
  expect_identical(
    expect_error(aa_delete_user(con, "boss", acting_login = "worker"), class = "appauth_error_user")$reason,
    "cannot_delete_last_admin"
  )
  expect_error(aa_delete_user(con, "boss"), class = "appauth_error_user")
  expect_identical(count_users(con), 2L)
})

test_that("удаление администратора допустимо, если остаётся другой активный", {
  con <- users_db()
  raw_user(con, "boss", "admin"); raw_user(con, "second", "admin")

  expect_identical(aa_delete_user(con, "second", acting_login = "boss"), 1L)
  expect_identical(aa_list_users(con)$login, "boss")
})

test_that("aa_delete_user: неизвестный и пустой пользователь отклоняются", {
  con <- users_db()
  raw_user(con, "boss", "admin")

  expect_identical(expect_error(aa_delete_user(con, "ghost"), class = "appauth_error_user")$reason, "user_not_found")
  expect_identical(expect_error(aa_delete_user(con, NA_character_), class = "appauth_error_user")$reason, "user_not_specified")
})

test_that("удаление работает, даже если таблицы попыток входа нет", {
  con <- users_db()
  raw_user(con, "boss", "admin"); raw_user(con, "worker", "user")
  DBI::dbExecute(con, "DROP TABLE login_attempts")

  expect_identical(aa_delete_user(con, "worker", acting_login = "boss"), 1L)
  expect_null(aa_get_user(con, "worker"))
})
