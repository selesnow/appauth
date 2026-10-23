# ---- ключ логина --------------------------------------------------------------------

test_that("ключ логина это точный логин: регистр и пробелы сохраняются", {
  s <- aa_settings()

  expect_identical(aa_login_key("Alsey", s), "Alsey")
  expect_identical(aa_login_key("alsey", s), "alsey")
  expect_identical(aa_login_key(" alsey", s), " alsey")
  expect_identical(aa_login_key("Иван", s), "Иван")
})

test_that("пустые логины и не строки не имеют ключа", {
  s <- aa_settings()

  for (bad in list("", "   ", "\t", NA_character_, NULL, 5, c("a", "b"))) {
    expect_identical(aa_login_key(bad, s), "")
  }
})

test_that("слишком длинный логин усекается до login_max символов", {
  expect_identical(nchar(aa_login_key(strrep("a", 500), aa_settings())), 64L)
  expect_identical(nchar(aa_login_key(strrep("я", 500), aa_settings(login_max = 10))), 10L)
})

# ---- запись попыток -----------------------------------------------------------------

test_that("aa_record_attempt записывает точный логин и результат", {
  con <- users_db()

  expect_true(aa_record_attempt(con, "Alsey", FALSE))
  expect_true(aa_record_attempt(con, "Alsey", TRUE))

  rows <- DBI::dbGetQuery(con, "SELECT login, success FROM login_attempts ORDER BY id")

  expect_identical(rows$login, c("Alsey", "Alsey"))
  expect_identical(rows$success, c(0L, 1L))
})

test_that("попытки с пустым логином не записываются", {
  con <- users_db()

  for (bad in list("", "   ", NA_character_, NULL, 5)) {
    expect_false(withVisible(aa_record_attempt(con, bad, FALSE))$value)
  }

  expect_identical(count_attempts(con), 0L)
  expect_false(withVisible(aa_record_attempt(con, "a", FALSE))$visible)
})

test_that("aa_record_attempt проверяет аргументы", {
  con <- users_db()

  expect_error(aa_record_attempt(con, "a", NA), class = "appauth_error_settings")
  expect_error(aa_record_attempt(con, "a", "yes"), class = "appauth_error_settings")
  expect_error(aa_record_attempt(list(), "a", FALSE), class = "appauth_error_connection")
})

# ---- блокировка логина --------------------------------------------------------------

test_that("до лимита вход разрешён, после лимита логин блокируется примерно на lockout_minutes", {
  con <- users_db()

  for (i in 1:4) aa_record_attempt(con, "alsey", FALSE)
  expect_identical(aa_login_lock_remaining(con, "alsey"), 0L)

  aa_record_attempt(con, "alsey", FALSE)
  remaining <- aa_login_lock_remaining(con, "alsey")

  expect_type(remaining, "integer")
  expect_gt(remaining, 14 * 60)
  expect_lte(remaining, 15 * 60)
})

test_that("другой логин не блокируется", {
  con <- users_db()
  for (i in 1:5) aa_record_attempt(con, "alsey", FALSE)

  expect_gt(aa_login_lock_remaining(con, "alsey"), 0)
  expect_identical(aa_login_lock_remaining(con, "ida"), 0L)
})

test_that("логин считается ТОЧНО: другой регистр и пробелы это другие логины с отдельными счётчиками", {
  con <- users_db()
  for (i in 1:5) aa_record_attempt(con, "alsey", FALSE)

  expect_gt(aa_login_lock_remaining(con, "alsey"), 0)
  expect_identical(aa_login_lock_remaining(con, "Alsey"), 0L)
  expect_identical(aa_login_lock_remaining(con, "ALSEY"), 0L)
  expect_identical(aa_login_lock_remaining(con, " alsey"), 0L)
  expect_identical(aa_login_lock_remaining(con, "alsey "), 0L)

  # неудачи по несуществующему "Alsey" не блокируют настоящего "alsey"
  con2 <- users_db()
  for (i in 1:10) aa_record_attempt(con2, "Alsey", FALSE)

  expect_identical(aa_login_lock_remaining(con2, "alsey"), 0L)
  expect_gt(aa_login_lock_remaining(con2, "Alsey"), 0)
})

test_that("пары логинов, различающихся регистром (как kiruka и Kiruka в рекрутинге), не мешают друг другу", {
  con <- users_db()

  for (i in 1:5) aa_record_attempt(con, "Kiruka", FALSE)
  for (i in 1:2) aa_record_attempt(con, "kiruka", FALSE)

  expect_gt(aa_login_lock_remaining(con, "Kiruka"), 0)
  expect_identical(aa_login_lock_remaining(con, "kiruka"), 0L)

  # успех одного не сбрасывает счётчик другого
  aa_record_attempt(con, "kiruka", TRUE)
  expect_gt(aa_login_lock_remaining(con, "Kiruka"), 0)
})

test_that("кириллические логины считаются точно", {
  con <- users_db()
  for (i in 1:5) aa_record_attempt(con, "Иван", FALSE)

  expect_gt(aa_login_lock_remaining(con, "Иван"), 0)
  expect_identical(aa_login_lock_remaining(con, "иван"), 0L)
})

test_that("несуществующий логин блокируется так же, пустой логин никогда", {
  con <- users_db()
  for (i in 1:5) aa_record_attempt(con, "no_such_user", FALSE)

  expect_gt(aa_login_lock_remaining(con, "no_such_user"), 0)

  for (bad in list("", "   ", NA_character_, NULL)) {
    expect_identical(aa_login_lock_remaining(con, bad), 0L)
  }
})

test_that("успешный вход обнуляет счётчик, даже если все записи сделаны в одну секунду", {
  con <- users_db()

  for (i in 1:3) aa_record_attempt(con, "ida", FALSE)
  aa_record_attempt(con, "ida", TRUE)
  for (i in 1:4) aa_record_attempt(con, "ida", FALSE)

  expect_identical(aa_login_lock_remaining(con, "ida"), 0L)

  aa_record_attempt(con, "ida", FALSE)

  expect_gt(aa_login_lock_remaining(con, "ida"), 0)
})

test_that("успех другого логина счётчик не обнуляет", {
  con <- users_db()

  for (i in 1:5) aa_record_attempt(con, "alsey", FALSE)
  aa_record_attempt(con, "ida", TRUE)

  expect_gt(aa_login_lock_remaining(con, "alsey"), 0)
})

test_that("окно: старые неудачи не считаются, блокировка отсчитывается от последней неудачи", {
  con <- users_db()

  for (i in 1:5) add_attempt(con, "old20", FALSE, minutes_ago = 20)
  expect_identical(aa_login_lock_remaining(con, "old20"), 0L)

  for (i in 1:5) add_attempt(con, "old16", FALSE, minutes_ago = 16)
  expect_identical(aa_login_lock_remaining(con, "old16"), 0L)

  for (i in 1:4) add_attempt(con, "mid", FALSE, minutes_ago = 14)
  add_attempt(con, "mid", FALSE, minutes_ago = 10)
  remaining <- aa_login_lock_remaining(con, "mid")

  expect_gt(remaining, 4 * 60)
  expect_lte(remaining, 5 * 60 + 5)
})

test_that("пороги берутся из настроек", {
  con <- users_db()
  s <- aa_settings(max_failed_logins = 3, lockout_minutes = 5)

  for (i in 1:2) aa_record_attempt(con, "u", FALSE, s)
  expect_identical(aa_login_lock_remaining(con, "u", s), 0L)

  aa_record_attempt(con, "u", FALSE, s)
  remaining <- aa_login_lock_remaining(con, "u", s)

  expect_gt(remaining, 4 * 60)
  expect_lte(remaining, 5 * 60)

  # по настройкам по умолчанию тех же 3 попыток недостаточно
  expect_identical(aa_login_lock_remaining(con, "u"), 0L)
})

test_that("логины с общим началом длиннее login_max делят один ключ (документированное поведение)", {
  con <- users_db()
  s <- aa_settings(login_max = 10)

  for (i in 1:5) aa_record_attempt(con, paste0(strrep("a", 10), "x"), FALSE, s)

  expect_gt(aa_login_lock_remaining(con, paste0(strrep("a", 10), "y"), s), 0)
})

# ---- снятие блокировки --------------------------------------------------------------

test_that("aa_clear_attempts снимает блокировку, успешные попытки и чужие логины остаются", {
  con <- users_db()
  for (i in 1:5) aa_record_attempt(con, "alsey", FALSE)
  for (i in 1:5) aa_record_attempt(con, "ida", FALSE)
  aa_record_attempt(con, "alsey", TRUE)   # успех идёт ПОСЛЕ неудач: счётчик и так обнулился бы
  DBI::dbExecute(con, "DELETE FROM login_attempts WHERE login = 'alsey' AND success = 1")

  expect_gt(aa_login_lock_remaining(con, "alsey"), 0)

  removed <- withVisible(aa_clear_attempts(con, "alsey"))

  expect_false(removed$visible)
  expect_equal(removed$value, 5)
  expect_identical(aa_login_lock_remaining(con, "alsey"), 0L)
  expect_gt(aa_login_lock_remaining(con, "ida"), 0)
})

test_that("aa_clear_attempts сохраняет успешные попытки и не трогает другой регистр", {
  con <- users_db()
  aa_record_attempt(con, "alsey", TRUE)
  for (i in 1:3) aa_record_attempt(con, "alsey", FALSE)
  for (i in 1:3) aa_record_attempt(con, "Alsey", FALSE)

  aa_clear_attempts(con, "alsey")

  expect_identical(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM login_attempts WHERE login = 'alsey'")$n, 1L)
  expect_identical(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM login_attempts WHERE login = 'Alsey'")$n, 3L)
  expect_equal(aa_clear_attempts(con, ""), 0)
  expect_equal(aa_clear_attempts(con, NA_character_), 0)
})

# ---- общий лимит --------------------------------------------------------------------

test_that("общий лимит: 29 неудач за минуту по разным логинам ещё не лимит, 30 лимит", {
  con <- users_db()

  for (i in 1:29) add_attempt(con, paste0("spray", i), FALSE, seconds_ago = 5)
  expect_false(aa_global_throttled(con))

  add_attempt(con, "spray30", FALSE, seconds_ago = 5)
  expect_true(aa_global_throttled(con))
})

test_that("общий лимит не считает старые неудачи и успешные входы", {
  con <- users_db()

  for (i in 1:40) add_attempt(con, paste0("old", i), FALSE, seconds_ago = 120)
  for (i in 1:40) add_attempt(con, paste0("ok", i), TRUE, seconds_ago = 5)

  expect_false(aa_global_throttled(con))
})

test_that("общий лимит берётся из настроек", {
  con <- users_db()
  s <- aa_settings(max_failed_logins_per_minute = 2)

  add_attempt(con, "a", FALSE, seconds_ago = 5)
  expect_false(aa_global_throttled(con, s))

  add_attempt(con, "b", FALSE, seconds_ago = 5)
  expect_true(aa_global_throttled(con, s))
  expect_false(aa_global_throttled(con))
})

# ---- шлюз входа ---------------------------------------------------------------------

test_that("шлюз пропускает вход, пока нет блокировок", {
  con <- users_db()

  gate <- aa_login_gate(con, "alsey")

  expect_true(gate$allowed)
  expect_true(is.na(gate$reason))
  expect_identical(gate$seconds, 0L)
  expect_true(is.na(gate$message))
  expect_identical(names(gate), c("allowed", "reason", "seconds", "message"))
})

test_that("шлюз сообщает о блокировке логина с минутами на нужном языке", {
  con <- users_db()
  for (i in 1:5) aa_record_attempt(con, "alsey", FALSE)

  gate <- aa_login_gate(con, "alsey")

  expect_false(gate$allowed)
  expect_identical(gate$reason, "locked")
  expect_gt(gate$seconds, 14 * 60)
  expect_identical(gate$message, "Слишком много неудачных попыток входа. Повторите через 15 мин.")

  en <- aa_login_gate(con, "alsey", aa_settings(texts = aa_texts("en")))
  expect_identical(en$message, "Too many failed sign-in attempts. Try again in 15 min.")

  # другой логин при этом входит
  expect_true(aa_login_gate(con, "ida")$allowed)
})

test_that("минуты в сообщении округляются вверх и не бывают нулевыми", {
  con <- users_db()
  for (i in 1:4) add_attempt(con, "u", FALSE, minutes_ago = 14)
  add_attempt(con, "u", FALSE, seconds_ago = 14 * 60 + 40)   # блокировка заканчивается меньше чем через минуту

  gate <- aa_login_gate(con, "u")

  expect_false(gate$allowed)
  expect_lte(gate$seconds, 60)
  expect_identical(gate$message, "Слишком много неудачных попыток входа. Повторите через 1 мин.")
})

test_that("при общем лимите вход закрыт для всех и это приоритетнее блокировки логина", {
  con <- users_db()
  for (i in 1:30) add_attempt(con, paste0("spray", i), FALSE, seconds_ago = 5)

  gate <- aa_login_gate(con, "innocent")

  expect_false(gate$allowed)
  expect_identical(gate$reason, "throttled")
  expect_identical(gate$message, "Слишком много попыток входа. Повторите через минуту.")

  for (i in 1:5) aa_record_attempt(con, "alsey", FALSE)
  expect_identical(aa_login_gate(con, "alsey")$reason, "throttled")
})

test_that("шлюз не запирает вход, если таблицы попыток нет (fail-open) и пишет причину в лог", {
  con <- users_db()
  DBI::dbExecute(con, "DROP TABLE login_attempts")

  expect_message(gate <- aa_login_gate(con, "alsey"), "проверка блокировки входа недоступна")

  expect_true(gate$allowed)
})

test_that("шлюз отклоняет не SQLite подключение", {
  expect_error(aa_login_gate(list(), "a"), class = "appauth_error_connection")
})

# ---- пользователи со статусами ----------------------------------------------------

test_that("обзор пользователей: состояния, статусы и секунды блокировки", {
  con <- users_db()
  raw_user(con, "boss", "admin")
  raw_user(con, "worker", "user", blocked = 1)
  raw_user(con, "viewer1", "viewer")
  raw_user(con, "both", "user", blocked = 1)
  for (i in 1:5) aa_record_attempt(con, "viewer1", FALSE)
  for (i in 1:5) aa_record_attempt(con, "both", FALSE)

  ov <- aa_users_overview(con)

  expect_identical(names(ov), c("login", "role", "blocked", "state", "lock_seconds", "status", "created_at", "last_login_at", "created", "last_login"))
  expect_identical(ov$login, c("boss", "worker", "viewer1", "both"))
  expect_identical(ov$state, c("ok", "blocked", "locked", "blocked"))
  expect_identical(ov$status[1], "")
  expect_identical(ov$status[2], "Заблокирован администратором")
  expect_identical(ov$status[3], "Вход заблокирован после неудачных попыток (ещё 15 мин.)")
  # блокировка администратором приоритетнее, но секунды блокировки по попыткам тоже видны
  expect_identical(ov$status[4], "Заблокирован администратором")
  expect_gt(ov$lock_seconds[3], 14 * 60)
  expect_identical(ov$lock_seconds[1], 0L)
})

test_that("обзор пользователей на английском и с пустой таблицей", {
  con <- users_db()

  empty <- aa_users_overview(con)
  expect_identical(nrow(empty), 0L)
  expect_identical(names(empty), c("login", "role", "blocked", "state", "lock_seconds", "status", "created_at", "last_login_at", "created", "last_login"))

  raw_user(con, "worker", "user", blocked = 1)
  en <- aa_users_overview(con, aa_settings(texts = aa_texts("en")))
  expect_identical(en$status, "Blocked by an administrator")
})

test_that("обзор пользователей не падает, если таблицы попыток нет", {
  con <- users_db()
  raw_user(con, "boss", "admin"); raw_user(con, "worker", "user", blocked = 1)
  DBI::dbExecute(con, "DROP TABLE login_attempts")

  ov <- aa_users_overview(con)

  expect_identical(ov$state, c("ok", "blocked"))
  expect_identical(ov$lock_seconds, c(0L, 0L))
})

test_that("обзор пользователей не раскрывает пароли и отклоняет не SQLite подключение", {
  con <- users_db()
  raw_user(con, "boss", "admin", password = "secret-hash")

  expect_false("password" %in% names(aa_users_overview(con)))
  expect_error(aa_users_overview(list()), class = "appauth_error_connection")
})
