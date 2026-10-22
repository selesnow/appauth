# Модуль пользователей через testServer. Модальные окна в mock-сессии не
# отображаются, поэтому проверяем действия, их результат в базе и события.
# Помощники в helper-modules.R, содержимое карточки в test-mod-card.R.

test_that("администратор видит таблицу, другие роли ничего не видят", {
  con <- users_fixture()

  run_users(con, {
    session$flushReact()
    expect_false(is.null(output$main$html))
    expect_match(paste(as.character(output$main$html), collapse = ""), "table", fixed = TRUE)
  })

  run_users(con, auth = fake_auth("ivan", "user"), {
    session$flushReact()
    expect_true(is.null(output$main$html) || !nzchar(paste(as.character(output$main$html), collapse = "")))
  })
})

test_that("таблица содержит пользователей и подсветку блокировок", {
  con <- users_fixture()
  aa_set_blocked(con, "ivan", TRUE, acting_login = "alsey")

  run_users(con, {
    session$flushReact()
    # данные таблицы серверные (serverSide), поэтому смотрим на реактивные данные модуля
    data <- overview()
    expect_setequal(data$login, c("alsey", "boss", "ivan"))
    expect_equal(data$state[data$login == "ivan"], "blocked")
    expect_equal(data$status[data$login == "ivan"], "Заблокирован администратором")
    expect_false("password" %in% names(data))

    json <- paste(as.character(output$table), collapse = "")
    expect_match(json, "aa-row-blocked", fixed = TRUE)
    expect_match(json, "aa-row-locked", fixed = TRUE)
    expect_match(json, "dblclick", fixed = TRUE)
  })
})

test_that("добавление: несовпадение паролей, слабый пароль, дубликат, успех", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(add = 1)

    session$setInputs(new_login = "olga", new_user_password = "secret123", new_user_confirm = "other", new_user_role = "user", add_confirm = 1)
    expect_equal(output$add_message, "Пароли не совпадают")
    expect_equal(count_users(con), 3)

    session$setInputs(new_login = "olga", new_user_password = "123", new_user_confirm = "123", add_confirm = 2)
    expect_match(output$add_message, "минимум")
    expect_equal(count_users(con), 3)

    session$setInputs(new_login = "IVAN", new_user_password = "secret123", new_user_confirm = "secret123", add_confirm = 3)
    expect_match(output$add_message, "уже существует")
    expect_equal(count_users(con), 3)

    session$setInputs(new_login = "olga", new_user_password = "secret123", new_user_confirm = "secret123", new_user_role = "viewer", add_confirm = 4)
    expect_equal(count_users(con), 4)
  })

  expect_equal(role_of(con, "olga"), "viewer")
  expect_true(aa_is_password_hash(stored_password(con, "olga")))
  expect_equal(log$names(), "user_added")
  expect_equal(log$events[[1]]$user, "alsey")
  expect_equal(log$events[[1]]$value, "olga (viewer)")
})

test_that("недопустимая роль при добавлении отвергается", {
  con <- users_fixture()

  run_users(con, {
    session$setInputs(add = 1)
    session$setInputs(new_login = "olga", new_user_password = "secret123", new_user_confirm = "secret123", new_user_role = "superuser", add_confirm = 1)
    expect_match(output$add_message, "роль", ignore.case = TRUE)
  })

  expect_equal(count_users(con), 3)
})

test_that("блокировка и разблокировка: токены отзываются, события и таблица обновляются", {
  con <- users_fixture()
  token <- aa_issue_token(con, "ivan")

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(block = 1)
    expect_equal(blocked_of(con, "ivan"), 1)
    expect_null(aa_find_session_user(con, token))

    session$flushReact()
    expect_equal(overview()$state[overview()$login == "ivan"], "blocked")

    session$setInputs(unblock = 1)
    expect_equal(blocked_of(con, "ivan"), 0)
  })

  expect_equal(log$names(), c("user_blocked", "user_unblocked"))
  expect_equal(log$events[[1]]$value, "ivan")
})

test_that("себя заблокировать и удалить нельзя, правила работают на сервере", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(open = "alsey")
    session$setInputs(block = 1)
    session$setInputs(delete = 1)
  })

  expect_equal(blocked_of(con, "alsey"), 0)
  expect_equal(count_users(con), 3)
  expect_length(log$events, 0)
})

test_that("последнего активного администратора нельзя заблокировать, удалить и понизить", {
  con <- users_fixture()
  aa_set_blocked(con, "boss", TRUE, acting_login = "alsey")

  log <- run_users(con, {
    session$setInputs(open = "alsey")
    session$setInputs(change_role = 1, role = "user")
    session$setInputs(block = 1)
    session$setInputs(delete = 2)
  })

  expect_equal(role_of(con, "alsey"), "admin")
  expect_equal(blocked_of(con, "alsey"), 0)
  expect_length(log$events, 0)
})

test_that("снятие блокировки входа очищает неудачные попытки", {
  con <- users_fixture()
  settings <- aa_settings(max_failed_logins = 3)
  for (i in 1:3) add_attempt(con, "ivan", FALSE)
  expect_gt(aa_login_lock_remaining(con, "ivan", settings), 0)

  log <- run_users(con, settings = settings, {
    session$setInputs(open = "ivan")
    session$setInputs(unlock = 1)
  })

  expect_equal(aa_login_lock_remaining(con, "ivan", settings), 0)
  expect_equal(log$names(), "login_unlocked")
})

test_that("смена роли, в том числе обычным пользователем в админы и обратно", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(change_role = 1, role = "viewer")
    expect_equal(role_of(con, "ivan"), "viewer")

    session$setInputs(change_role = 2, role = "root")
    expect_equal(role_of(con, "ivan"), "viewer")
  })

  expect_equal(log$names(), "user_role_changed")
  expect_equal(log$events[[1]]$value, "ivan: viewer")
})

test_that("сброс пароля: несовпадение отвергается, успех меняет пароль и отзывает токены", {
  con <- users_fixture()
  token <- aa_issue_token(con, "ivan")

  log <- run_users(con, {
    session$setInputs(open = "ivan")

    session$setInputs(new_password = "newpass123", new_password_confirm = "different", reset_password = 1)
    expect_false(is.null(aa_authenticate(con, "ivan", "secret123")))

    session$setInputs(new_password = "123", new_password_confirm = "123", reset_password = 2)
    expect_false(is.null(aa_authenticate(con, "ivan", "secret123")))

    session$setInputs(new_password = "newpass123", new_password_confirm = "newpass123", reset_password = 3)
  })

  expect_null(aa_authenticate(con, "ivan", "secret123"))
  expect_false(is.null(aa_authenticate(con, "ivan", "newpass123")))
  expect_null(aa_find_session_user(con, token))
  expect_equal(log$names(), "password_reset")
})

test_that("удаление пользователя: запись и токены удалены, событие отправлено", {
  con <- users_fixture()
  aa_issue_token(con, "ivan")

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(delete = 1)
  })

  expect_null(aa_get_user(con, "ivan"))
  expect_equal(nrow(rows_of(con, "auth_sessions")), 0)
  expect_equal(log$names(), "user_removed")
})

test_that("действие без открытой карточки ничего не делает: цель берётся не из браузера", {
  con <- users_fixture()

  log <- run_users(con, {
    session$setInputs(delete = 1, block = 1, role = "viewer", change_role = 1, unlock = 1)
  })

  expect_equal(count_users(con), 3)
  expect_equal(blocked_of(con, "ivan"), 0)
  expect_equal(role_of(con, "ivan"), "user")
  expect_length(log$events, 0)
})

test_that("после закрытия карточки (удаление, сброс пароля) цель сбрасывается", {
  con <- users_fixture()

  run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(delete = 1)
    session$setInputs(open = "boss") # другая карточка
    session$setInputs(delete = 2)
    expect_null(aa_get_user(con, "boss"))
  })
})

test_that("не администратор не может выполнять действия, отказ уходит в события", {
  con <- users_fixture()

  log <- run_users(con, auth = fake_auth("ivan", "user"), {
    session$setInputs(open = "boss")
    session$setInputs(block = 1)
    session$setInputs(add = 1)
    session$setInputs(new_login = "x1", new_user_password = "secret123", new_user_confirm = "secret123", add_confirm = 1)
  })

  expect_equal(blocked_of(con, "boss"), 0)
  expect_equal(count_users(con), 3)
  expect_true(all(log$names() == "access_denied"))
  expect_gte(length(log$events), 1)
})

test_that("администратор, которого понизили в базе, теряет доступ несмотря на старую роль в сессии", {
  con <- users_fixture()
  DBI::dbExecute(con, "UPDATE users SET role = 'user' WHERE login = 'alsey'")

  log <- run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(block = 1)
  })

  expect_equal(blocked_of(con, "ivan"), 0)
  expect_true("access_denied" %in% log$names())
})

test_that("администратор, которого заблокировали, теряет доступ", {
  con <- users_fixture()
  DBI::dbExecute(con, "UPDATE users SET blocked = 1 WHERE login = 'alsey'")

  run_users(con, {
    session$setInputs(open = "ivan")
    session$setInputs(block = 1)
  })

  expect_equal(blocked_of(con, "ivan"), 0)
})

test_that("слот: серверная часть вызывается один раз и видит логин открытой карточки", {
  con <- users_fixture()
  seen <- new.env()
  seen$calls <- 0
  slot_server <- function(input, output, session, login) {
    seen$calls <- seen$calls + 1
    seen$login <- login
  }

  run_users(con, extra_card_server = slot_server, extra_card_ui = function(login, ns) NULL, {
    expect_equal(seen$calls, 1)
    session$setInputs(open = "ivan")
    expect_equal(seen$login(), "ivan")
    session$setInputs(open = "boss")
    expect_equal(seen$login(), "boss")
    expect_equal(seen$calls, 1)
  })
})

test_that("слот интерфейса получает логин и функцию пространства имён", {
  con <- users_fixture()
  seen <- new.env()
  slot_ui <- function(login, ns) {
    seen$login <- login
    seen$id <- ns("extra")
    NULL
  }

  run_users(con, extra_card_ui = slot_ui, {
    session$setInputs(open = "ivan")
  })

  expect_equal(seen$login, "ivan")
  expect_match(seen$id, "extra$")
})

test_that("карточка несуществующего пользователя не открывается и не ломает модуль", {
  con <- users_fixture()

  run_users(con, {
    session$setInputs(open = "ghost")
    session$setInputs(delete = 1)
  })

  expect_equal(count_users(con), 3)
})

test_that("refresh перерисовывает таблицу после внешних изменений", {
  con <- users_fixture()

  run_users(con, {
    session$flushReact()
    expect_false("olga" %in% overview()$login)

    aa_create_user(con, "olga", "secret123", "user")
    session$returned$refresh()
    session$flushReact()
    expect_true("olga" %in% overview()$login)
  })
})

test_that("после выхода (пользователя нет) таблица не записывает отказ в доступе", {
  con <- users_fixture()
  auth <- fake_auth()

  log <- run_users(con, auth = auth, {
    session$flushReact()
    auth$user(NULL)
    session$flushReact()
  })

  expect_length(log$events, 0)
})
