# ---- хеширование и проверка ---------------------------------------------------

test_that("хеш начинается с $7$ и не содержит пароль", {
  hash <- aa_hash_password("secret-password")

  expect_type(hash, "character")
  expect_length(hash, 1)
  expect_match(hash, "^\\$7\\$")
  expect_false(grepl("secret-password", hash, fixed = TRUE))
})

test_that("два хеша одного пароля различаются (соль), оба проходят проверку", {
  h1 <- aa_hash_password("same-password")
  h2 <- aa_hash_password("same-password")

  expect_false(identical(h1, h2))
  expect_true(aa_verify_password("same-password", h1))
  expect_true(aa_verify_password("same-password", h2))
})

test_that("проверка пароля различает верный и неверный, учитывает регистр и пробелы", {
  hash <- aa_hash_password("Secret Pass")

  expect_true(aa_verify_password("Secret Pass", hash))
  expect_false(aa_verify_password("secret pass", hash))
  expect_false(aa_verify_password("Secret Pass ", hash))
  expect_false(aa_verify_password("wrong", hash))
})

test_that("кириллица, спецсимволы и длинные пароли работают", {
  for (pw in c("пароль-на-русском", "p'a\"ss;--%d", strrep("a", 128), "  пробелы  ")) {
    hash <- aa_hash_password(pw)
    expect_true(aa_verify_password(pw, hash), info = pw)
  }
})

test_that("aa_hash_password отклоняет не строки и пустые значения", {
  for (bad in list("", NA_character_, NULL, 123, c("a", "b"), TRUE, list("a"))) {
    expect_error(aa_hash_password(bad), class = "appauth_error_password")
  }
})

test_that("aa_is_password_hash отличает хеши от паролей в открытом виде", {
  hash <- aa_hash_password("x")

  expect_identical(
    aa_is_password_hash(c(hash, "root", NA, "", "$2y$10$abc", "$7")),
    c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE)
  )
  expect_identical(aa_is_password_hash(character()), logical())
})

test_that("пароль в открытом виде никогда не проходит проверку", {
  expect_false(aa_verify_password("root", "root"))
  expect_false(aa_verify_password("secret", "secret"))
  # значение, похожее на хеш, но не являющееся им, тоже не принимается
  expect_false(aa_verify_password("$7$abc", "$7$abc"))
})

test_that("сам хеш в качестве пароля не подходит (pass-the-hash)", {
  hash <- aa_hash_password("secret")

  expect_false(aa_verify_password(hash, hash))
})

test_that("некорректные аргументы и повреждённый хеш дают FALSE без ошибок", {
  hash <- aa_hash_password("secret")

  expect_false(aa_verify_password(NULL, hash))
  expect_false(aa_verify_password(NA_character_, hash))
  expect_false(aa_verify_password("", hash))
  expect_false(aa_verify_password(c("secret", "secret"), hash))
  expect_false(aa_verify_password(123, hash))
  expect_false(aa_verify_password("secret", NULL))
  expect_false(aa_verify_password("secret", NA_character_))
  expect_false(aa_verify_password("secret", c(hash, hash)))
  expect_false(aa_verify_password("secret", "$7$повреждённый-хеш"))
  expect_false(aa_verify_password("secret", substr(hash, 1, 20)))
})

test_that("хеш-заглушка это хеш, не меняется в течение сессии и не принимает типичные пароли", {
  dummy <- aa_dummy_hash()

  expect_true(aa_is_password_hash(dummy))
  expect_identical(aa_dummy_hash(), dummy)
  expect_false(aa_verify_password("password", dummy))
  expect_false(aa_verify_password("", dummy))
})

# ---- правила нового пароля и логина -------------------------------------------

test_that("пароль нужной длины подходит", {
  expect_null(aa_validate_password("123456"))
  expect_null(aa_validate_password(strrep("a", 128)))
  expect_null(aa_validate_password("пароль-русский"))
})

test_that("слишком короткий и слишком длинный пароль отклоняются с понятным текстом", {
  expect_identical(
    aa_validate_password("12345"),
    "Пароль должен содержать минимум 6 символов"
  )
  expect_identical(
    aa_validate_password(strrep("a", 129)),
    "Пароль должен содержать максимум 128 символов"
  )
})

test_that("длина пароля считается в символах, а не в байтах", {
  # шесть кириллических символов это 12 байт, но 6 символов
  expect_null(aa_validate_password("абвгде"))
  expect_false(is.null(aa_validate_password("абвгд")))
})

test_that("пустые и некорректные пароли отклоняются", {
  for (bad in list("", NA_character_, NULL, 123, c("abcdef", "abcdef"))) {
    expect_identical(aa_validate_password(bad), "Пароль не может быть пустым")
  }
})

test_that("правила пароля берутся из настроек и тексты на языке настроек", {
  s <- aa_settings(password_min = 10, password_max = 12, texts = aa_texts("en"))

  expect_identical(aa_validate_password("123456789", s), "Password must be at least 10 characters long")
  expect_identical(aa_validate_password(strrep("a", 13), s), "Password must be at most 12 characters long")
  expect_null(aa_validate_password("1234567890", s))
  expect_identical(aa_validate_password("", s), "Password cannot be empty")
})

test_that("логин проверяется", {
  expect_null(aa_validate_login("alsey"))
  expect_null(aa_validate_login("al sey"))
  expect_null(aa_validate_login(strrep("a", 64)))

  # пробелы по краям запрещены: вход сравнивает логин точно
  for (bad in c("  alsey  ", " alsey", "alsey ", "alsey\t")) {
    expect_identical(aa_validate_login(bad), "Логин не должен начинаться или заканчиваться пробелом")
  }
  expect_identical(aa_validate_login(" alsey", aa_settings(texts = aa_texts("en"))), "Login must not start or end with a space")

  expect_identical(aa_validate_login(strrep("a", 65)), "Логин должен содержать максимум 64 символов")

  for (bad in list("", "   ", NA_character_, NULL, 5, c("a", "b"))) {
    expect_identical(aa_validate_login(bad), "Логин не может быть пустым")
  }
})

test_that("правила логина берутся из настроек", {
  s <- aa_settings(login_max = 5, texts = aa_texts("en"))

  expect_null(aa_validate_login("abcde", s))
  expect_identical(aa_validate_login("abcdef", s), "Login must be at most 5 characters long")
  expect_identical(aa_validate_login(" ", s), "Login cannot be empty")
})

# ---- перенос паролей из открытого вида ---------------------------------------

# файловая база с фикстурой, путь удаляется в конце теста
file_db <- function(fixture, env = parent.frame()) {
  skip_if_not_sqlite()
  testthat::skip_if_not_installed("RSQLite")

  path <- withr::local_tempfile(fileext = ".db", .local_envir = env)
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  fixture(con)
  DBI::dbDisconnect(con)

  path
}

read_users <- function(path) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con))
  tquery(con, "SELECT login, password, role FROM users ORDER BY rowid")
}

test_that("рекрутинг: пароли в открытом виде переносятся в хеши, вход по старым паролям работает", {
  db <- file_db(fixture_recruitment)
  before <- read_users(db)

  res <- suppressMessages(aa_migrate_plaintext_passwords(db))
  after <- read_users(db)

  expect_setequal(res$migrated, c("root", "hr_one", "viewer"))
  expect_identical(res$skipped, character())
  expect_false(res$dry_run)
  expect_true(all(aa_is_password_hash(after$password)))
  expect_identical(after$login, before$login)
  expect_identical(after$role, before$role)

  for (i in seq_len(nrow(before))) {
    expect_true(aa_verify_password(before$password[i], after$password[i]), info = before$login[i])
  }
})

test_that("перед изменениями создаётся резервная копия со старыми паролями", {
  db <- file_db(fixture_recruitment)
  before <- read_users(db)

  res <- suppressMessages(aa_migrate_plaintext_passwords(db))
  on.exit(unlink(res$backup), add = TRUE)

  expect_true(file.exists(res$backup))
  expect_match(basename(res$backup), "\\.db\\.bak_[0-9]{8}_[0-9]{6}$")
  expect_identical(read_users(res$backup), before)
})

test_that("после переноса выводится напоминание удалить резервную копию", {
  db <- file_db(fixture_recruitment)

  expect_message(res <- aa_migrate_plaintext_passwords(db), "Удалите её после проверки")
  unlink(res$backup)
})

test_that("повторный запуск ничего не меняет и не создаёт лишних копий", {
  db <- file_db(fixture_recruitment)
  first <- suppressMessages(aa_migrate_plaintext_passwords(db))
  on.exit(unlink(first$backup), add = TRUE)

  hashes <- read_users(db)
  files_before <- list.files(dirname(db), pattern = basename(db), full.names = TRUE)

  res <- aa_migrate_plaintext_passwords(db)

  expect_identical(res$migrated, character())
  expect_setequal(res$skipped, c("root", "hr_one", "viewer"))
  expect_true(is.na(res$backup))
  expect_identical(read_users(db), hashes)
  expect_identical(list.files(dirname(db), pattern = basename(db), full.names = TRUE), files_before)
})

test_that("dry_run показывает, что будет перенесено, и ничего не меняет", {
  db <- file_db(fixture_recruitment)
  before <- read_users(db)

  res <- aa_migrate_plaintext_passwords(db, dry_run = TRUE)

  expect_true(res$dry_run)
  expect_setequal(res$migrated, c("root", "hr_one", "viewer"))
  expect_true(is.na(res$backup))
  expect_identical(read_users(db), before)
  expect_identical(list.files(dirname(db), pattern = paste0(basename(db), ".bak"), full.names = TRUE), character())
})

test_that("уже хешированные пароли пропускаются и не меняются", {
  db <- file_db(function(con) {
    fixture_server_manager_dev_old(con)   # alsey: хеш, tester: открытый пароль
  })
  before <- read_users(db)

  res <- suppressMessages(aa_migrate_plaintext_passwords(db, backup = FALSE))
  after <- read_users(db)

  expect_identical(res$migrated, "tester")
  expect_identical(res$skipped, "alsey")
  expect_identical(after$password[after$login == "alsey"], before$password[before$login == "alsey"])
  expect_true(aa_verify_password("tester", after$password[after$login == "tester"]))
})

test_that("таблица users без колонки id тоже переносится", {
  db <- file_db(fixture_server_manager_dev_old)

  expect_false("id" %in% names(read_users(db)))

  res <- suppressMessages(aa_migrate_plaintext_passwords(db, backup = FALSE))

  expect_identical(res$migrated, "tester")
})

test_that("спецсимволы в пароле и логине не ломают перенос (параметры, а не склейка SQL)", {
  db <- file_db(function(con) {
    texec(con, "CREATE TABLE users (login TEXT PRIMARY KEY, password TEXT, role TEXT)")
    DBI::dbExecute(
      con, "INSERT INTO users VALUES (?, ?, 'user')",
      params = list("o'neil\"; DROP TABLE users;--", "p'a\"ss;--%d")
    )
  })

  suppressMessages(aa_migrate_plaintext_passwords(db, backup = FALSE))
  after <- read_users(db)

  expect_identical(nrow(after), 1L)
  expect_true(aa_verify_password("p'a\"ss;--%d", after$password))
})

test_that("при пустом пароле у одного пользователя вся миграция откатывается", {
  db <- file_db(function(con) {
    fixture_recruitment(con)
    texec(con, "INSERT INTO users (login, password, role) VALUES ('empty', '', 'user')")
  })
  before <- read_users(db)

  expect_error(
    suppressMessages(aa_migrate_plaintext_passwords(db, backup = FALSE)),
    "Миграция отменена, изменения не применены",
    class = "appauth_error_migration"
  )
  expect_identical(read_users(db), before)
})

test_that("резервную копию можно сохранить по своему пути или отключить", {
  db <- file_db(fixture_recruitment)
  copy <- withr::local_tempfile(fileext = ".bak")

  res <- suppressMessages(aa_migrate_plaintext_passwords(db, backup = copy))

  expect_identical(res$backup, copy)
  expect_true(file.exists(copy))

  db2 <- file_db(fixture_recruitment)
  res2 <- aa_migrate_plaintext_passwords(db2, backup = FALSE)

  expect_true(is.na(res2$backup))
  expect_identical(list.files(dirname(db2), pattern = paste0(basename(db2), ".bak"), full.names = TRUE), character())
})

test_that("база без пользователей и без таблицы users обрабатывается", {
  db <- file_db(function(con) texec(con, "CREATE TABLE users (login TEXT, password TEXT, role TEXT)"))
  res <- aa_migrate_plaintext_passwords(db)

  expect_identical(res$migrated, character())
  expect_identical(res$skipped, character())

  db2 <- file_db(function(con) texec(con, "CREATE TABLE other (x INTEGER)"))
  expect_error(aa_migrate_plaintext_passwords(db2), "нет таблицы `users`", class = "appauth_error_migration")
})

test_that("некорректные аргументы миграции отклоняются", {
  expect_error(aa_migrate_plaintext_passwords("нет-такого-файла.db"), "не найден", class = "appauth_error_migration")
  expect_error(aa_migrate_plaintext_passwords(NA_character_), class = "appauth_error_migration")
  expect_error(aa_migrate_plaintext_passwords(c("a", "b")), class = "appauth_error_migration")

  db <- file_db(fixture_recruitment)

  expect_error(aa_migrate_plaintext_passwords(db, backup = NA), class = "appauth_error_migration")
  expect_error(aa_migrate_plaintext_passwords(db, backup = 5), class = "appauth_error_migration")
  expect_error(aa_migrate_plaintext_passwords(db, dry_run = "yes"), class = "appauth_error_settings")
})

# ---- слабые учётные записи ------------------------------------------------------

add_user <- function(con, login, password, role = "user", hash = TRUE) {
  aa_execute(
    con, "INSERT INTO users (login, password, role) VALUES (?, ?, ?)",
    params = list(login, if (hash) aa_hash_password(password) else password, role)
  )
}

test_that("находятся пароль = логин и распространённые пароли, сильные пароли не трогаются", {
  con <- new_db()
  aa_init_db(con)

  add_user(con, "alsey", "very-strong-pass-92!", "admin")
  add_user(con, "tester", "tester")
  add_user(con, "admin2", "admin", "admin")
  add_user(con, "Ida", "ida")
  add_user(con, "kate", "KATE")

  res <- aa_check_default_accounts(con)

  expect_identical(names(res), c("login", "role", "reason"))
  expect_setequal(res$login, c("tester", "admin2", "Ida", "kate"))
  expect_identical(res$reason[res$login == "tester"], "login_as_password")
  expect_identical(res$reason[res$login == "admin2"], "common_password")
  expect_identical(res$reason[res$login == "Ida"], "login_as_password")
  expect_identical(res$reason[res$login == "kate"], "login_as_password")
  expect_false("alsey" %in% res$login)
})

test_that("пароли в открытом виде находятся, root/root даёт две причины", {
  con <- new_db()
  aa_init_db(con)

  add_user(con, "root", "root", "admin", hash = FALSE)
  add_user(con, "hr_one", "secret12", hash = FALSE)

  res <- aa_check_default_accounts(con)

  expect_setequal(res$reason[res$login == "root"], c("plaintext", "login_as_password"))
  expect_identical(res$reason[res$login == "hr_one"], "plaintext")
})

test_that("рекрутинг после миграции: слабые пароли остаются слабыми и находятся", {
  db <- file_db(fixture_recruitment)
  suppressMessages(aa_migrate_plaintext_passwords(db, backup = FALSE))

  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  withr::defer(DBI::dbDisconnect(con))

  res <- aa_check_default_accounts(con)

  expect_identical(res$login, "root")
  expect_identical(res$reason, "login_as_password")
})

test_that("если слабых паролей нет, результат пустая таблица нужной формы", {
  con <- new_db()
  aa_init_db(con)
  add_user(con, "alsey", "very-strong-pass-92!", "admin")

  res <- aa_check_default_accounts(con)

  expect_identical(nrow(res), 0L)
  expect_identical(names(res), c("login", "role", "reason"))

  empty <- new_db()
  aa_init_db(empty)
  expect_identical(nrow(aa_check_default_accounts(empty)), 0L)
})

test_that("список слабых паролей можно заменить", {
  con <- new_db()
  aa_init_db(con)
  add_user(con, "u1", "company2026")

  expect_identical(nrow(aa_check_default_accounts(con)), 0L)
  expect_identical(aa_check_default_accounts(con, common = "company2026")$reason, "common_password")
})

test_that("aa_check_default_accounts проверяет аргументы", {
  expect_error(aa_check_default_accounts(list()), class = "appauth_error_connection")

  con <- new_db()
  aa_init_db(con)

  expect_error(aa_check_default_accounts(con, common = 1:3), class = "appauth_error_password")
  expect_error(aa_check_default_accounts(con, common = c("a", NA)), class = "appauth_error_password")
})

test_that("aa_common_passwords возвращает вектор строк с очевидными паролями", {
  common <- aa_common_passwords()

  expect_type(common, "character")
  expect_true(all(c("root", "admin", "123456", "password") %in% common))
  expect_false(anyNA(common))
})
