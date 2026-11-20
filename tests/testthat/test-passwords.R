# ---- hashing and verification ---------------------------------------------------

test_that("the hash starts with $7$ and does not contain the password", {
  hash <- aa_hash_password("secret-password")

  expect_type(hash, "character")
  expect_length(hash, 1)
  expect_match(hash, "^\\$7\\$")
  expect_false(grepl("secret-password", hash, fixed = TRUE))
})

test_that("two hashes of one password differ (salt), both pass verification", {
  h1 <- aa_hash_password("same-password")
  h2 <- aa_hash_password("same-password")

  expect_false(identical(h1, h2))
  expect_true(aa_verify_password("same-password", h1))
  expect_true(aa_verify_password("same-password", h2))
})

test_that("verification tells right from wrong, respects case and whitespace", {
  hash <- aa_hash_password("Secret Pass")

  expect_true(aa_verify_password("Secret Pass", hash))
  expect_false(aa_verify_password("secret pass", hash))
  expect_false(aa_verify_password("Secret Pass ", hash))
  expect_false(aa_verify_password("wrong", hash))
})

test_that("non-ASCII, special characters and long passwords work", {
  for (pw in c(
    "\u043f\u0430\u0440\u043e\u043b\u044c-\u0440\u0443\u0441",
    "p'a\"ss;--%d",
    strrep("a", 128),
    "  spaces  "
  )) {
    hash <- aa_hash_password(pw)
    expect_true(aa_verify_password(pw, hash), info = pw)
  }
})

test_that("aa_hash_password rejects non-strings and empty values", {
  for (bad in list(
    "",
    NA_character_,
    NULL,
    123,
    c("a", "b"),
    TRUE,
    list("a")
  )) {
    expect_error(aa_hash_password(bad), class = "appauth_error_password")
  }
})

test_that("aa_is_password_hash tells hashes from plain-text passwords", {
  hash <- aa_hash_password("x")

  expect_identical(
    aa_is_password_hash(c(hash, "root", NA, "", "$2y$10$abc", "$7")),
    c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE)
  )
  expect_identical(aa_is_password_hash(character()), logical())
})

test_that("a plain-text password never passes verification", {
  expect_false(aa_verify_password("root", "root"))
  expect_false(aa_verify_password("secret", "secret"))
  # a value that looks like a hash but is not one is not accepted either
  expect_false(aa_verify_password("$7$abc", "$7$abc"))
})

test_that("the hash itself does not work as a password (pass-the-hash)", {
  hash <- aa_hash_password("secret")

  expect_false(aa_verify_password(hash, hash))
})

test_that("invalid arguments and a corrupted hash give FALSE without errors", {
  hash <- aa_hash_password("secret")

  expect_false(aa_verify_password(NULL, hash))
  expect_false(aa_verify_password(NA_character_, hash))
  expect_false(aa_verify_password("", hash))
  expect_false(aa_verify_password(c("secret", "secret"), hash))
  expect_false(aa_verify_password(123, hash))
  expect_false(aa_verify_password("secret", NULL))
  expect_false(aa_verify_password("secret", NA_character_))
  expect_false(aa_verify_password("secret", c(hash, hash)))
  expect_false(aa_verify_password("secret", "$7$corrupted-hash"))
  expect_false(aa_verify_password("secret", substr(hash, 1, 20)))
})

test_that("the dummy hash is a hash, does not change during the session and rejects typical passwords", {
  dummy <- aa_dummy_hash()

  expect_true(aa_is_password_hash(dummy))
  expect_identical(aa_dummy_hash(), dummy)
  expect_false(aa_verify_password("password", dummy))
  expect_false(aa_verify_password("", dummy))
})

# ---- rules for a new password and login -------------------------------------------

test_that("a password of the right length is fine", {
  expect_null(aa_validate_password("123456"))
  expect_null(aa_validate_password(strrep("a", 128)))
  expect_null(aa_validate_password(
    "\u043f\u0430\u0440\u043e\u043b\u044c-\u0440\u0443\u0441"
  ))
})

test_that("a too short and a too long password are rejected with a clear text", {
  expect_identical(
    aa_validate_password("12345"),
    aa_text(aa_settings(), "password_too_short", 6L)
  )
  expect_identical(
    aa_validate_password(strrep("a", 129)),
    aa_text(aa_settings(), "password_too_long", 128L)
  )
})

test_that("password length is counted in characters, not bytes", {
  # six Cyrillic characters are 12 bytes but 6 characters
  expect_null(aa_validate_password("\u0430\u0431\u0432\u0433\u0434\u0435"))
  expect_false(is.null(aa_validate_password("\u0430\u0431\u0432\u0433\u0434")))
})

test_that("empty and invalid passwords are rejected", {
  for (bad in list("", NA_character_, NULL, 123, c("abcdef", "abcdef"))) {
    expect_identical(
      aa_validate_password(bad),
      aa_text(aa_settings(), "password_empty")
    )
  }
})

test_that("password rules come from the settings and texts are in the settings language", {
  s <- aa_settings(password_min = 10, password_max = 12)

  expect_identical(
    aa_validate_password("123456789", s),
    "Password must be at least 10 characters long"
  )
  expect_identical(
    aa_validate_password(strrep("a", 13), s),
    "Password must be at most 12 characters long"
  )
  expect_null(aa_validate_password("1234567890", s))
  expect_identical(aa_validate_password("", s), "Password cannot be empty")
})

test_that("the login is validated", {
  expect_null(aa_validate_login("alsey"))
  expect_null(aa_validate_login("al sey"))
  expect_null(aa_validate_login(strrep("a", 64)))

  # edge whitespace is forbidden: login compares the login exactly
  for (bad in c("  alsey  ", " alsey", "alsey ", "alsey\t")) {
    expect_identical(
      aa_validate_login(bad),
      aa_text(aa_settings(), "login_whitespace")
    )
  }
  expect_identical(
    aa_validate_login(" alsey", aa_settings(texts = aa_texts("en"))),
    "Login must not start or end with a space"
  )

  expect_identical(
    aa_validate_login(strrep("a", 65)),
    aa_text(aa_settings(), "login_too_long", 64L)
  )

  for (bad in list("", "   ", NA_character_, NULL, 5, c("a", "b"))) {
    expect_identical(
      aa_validate_login(bad),
      aa_text(aa_settings(), "login_empty")
    )
  }
})

test_that("login rules come from the settings", {
  s <- aa_settings(login_max = 5)

  expect_null(aa_validate_login("abcde", s))
  expect_identical(
    aa_validate_login("abcdef", s),
    "Login must be at most 5 characters long"
  )
  expect_identical(aa_validate_login(" ", s), "Login cannot be empty")
})

# ---- migration of passwords from plain text ---------------------------------------

# file database with a fixture, the path is removed at the end of the test
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

test_that("legacy app: plain-text passwords are migrated to hashes, login with old passwords works", {
  db <- file_db(fixture_legacy_plain)
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
    expect_true(
      aa_verify_password(before$password[i], after$password[i]),
      info = before$login[i]
    )
  }
})

test_that("a backup copy with the old passwords is created before changes", {
  db <- file_db(fixture_legacy_plain)
  before <- read_users(db)

  res <- suppressMessages(aa_migrate_plaintext_passwords(db))
  on.exit(unlink(res$backup), add = TRUE)

  expect_true(file.exists(res$backup))
  expect_match(basename(res$backup), "\\.db\\.bak_[0-9]{8}_[0-9]{6}$")
  expect_identical(read_users(res$backup), before)
})

test_that("after the migration a reminder to delete the backup is shown", {
  db <- file_db(fixture_legacy_plain)

  expect_message(
    res <- aa_migrate_plaintext_passwords(db),
    "Delete it after checking"
  )
  unlink(res$backup)
})

test_that("a repeated run changes nothing and creates no extra copies", {
  db <- file_db(fixture_legacy_plain)
  first <- suppressMessages(aa_migrate_plaintext_passwords(db))
  on.exit(unlink(first$backup), add = TRUE)

  hashes <- read_users(db)
  files_before <- list.files(
    dirname(db),
    pattern = basename(db),
    full.names = TRUE
  )

  res <- aa_migrate_plaintext_passwords(db)

  expect_identical(res$migrated, character())
  expect_setequal(res$skipped, c("root", "hr_one", "viewer"))
  expect_true(is.na(res$backup))
  expect_identical(read_users(db), hashes)
  expect_identical(
    list.files(dirname(db), pattern = basename(db), full.names = TRUE),
    files_before
  )
})

test_that("dry_run shows what would be migrated and changes nothing", {
  db <- file_db(fixture_legacy_plain)
  before <- read_users(db)

  res <- aa_migrate_plaintext_passwords(db, dry_run = TRUE)

  expect_true(res$dry_run)
  expect_setequal(res$migrated, c("root", "hr_one", "viewer"))
  expect_true(is.na(res$backup))
  expect_identical(read_users(db), before)
  expect_identical(
    list.files(
      dirname(db),
      pattern = paste0(basename(db), ".bak"),
      full.names = TRUE
    ),
    character()
  )
})

test_that("already hashed passwords are skipped and unchanged", {
  db <- file_db(function(con) {
    fixture_legacy_old(con) # alsey: hash, tester: plain-text password
  })
  before <- read_users(db)

  res <- suppressMessages(aa_migrate_plaintext_passwords(db, backup = FALSE))
  after <- read_users(db)

  expect_identical(res$migrated, "tester")
  expect_identical(res$skipped, "alsey")
  expect_identical(
    after$password[after$login == "alsey"],
    before$password[before$login == "alsey"]
  )
  expect_true(aa_verify_password(
    "tester",
    after$password[after$login == "tester"]
  ))
})

test_that("a users table without an id column is migrated too", {
  db <- file_db(fixture_legacy_old)

  expect_false("id" %in% names(read_users(db)))

  res <- suppressMessages(aa_migrate_plaintext_passwords(db, backup = FALSE))

  expect_identical(res$migrated, "tester")
})

test_that("special characters in password and login do not break the migration (parameters, not SQL concatenation)", {
  db <- file_db(function(con) {
    texec(
      con,
      "CREATE TABLE users (login TEXT PRIMARY KEY, password TEXT, role TEXT)"
    )
    DBI::dbExecute(
      con,
      "INSERT INTO users VALUES (?, ?, 'user')",
      params = list("o'neil\"; DROP TABLE users;--", "p'a\"ss;--%d")
    )
  })

  suppressMessages(aa_migrate_plaintext_passwords(db, backup = FALSE))
  after <- read_users(db)

  expect_identical(nrow(after), 1L)
  expect_true(aa_verify_password("p'a\"ss;--%d", after$password))
})

test_that("an empty password for one user rolls back the whole migration", {
  db <- file_db(function(con) {
    fixture_legacy_plain(con)
    texec(
      con,
      "INSERT INTO users (login, password, role) VALUES ('empty', '', 'user')"
    )
  })
  before <- read_users(db)

  expect_error(
    suppressMessages(aa_migrate_plaintext_passwords(db, backup = FALSE)),
    "Migration cancelled, no changes were applied",
    class = "appauth_error_migration"
  )
  expect_identical(read_users(db), before)
})

test_that("the backup can be saved to a custom path or disabled", {
  db <- file_db(fixture_legacy_plain)
  copy <- withr::local_tempfile(fileext = ".bak")

  res <- suppressMessages(aa_migrate_plaintext_passwords(db, backup = copy))

  expect_identical(res$backup, copy)
  expect_true(file.exists(copy))

  db2 <- file_db(fixture_legacy_plain)
  res2 <- aa_migrate_plaintext_passwords(db2, backup = FALSE)

  expect_true(is.na(res2$backup))
  expect_identical(
    list.files(
      dirname(db2),
      pattern = paste0(basename(db2), ".bak"),
      full.names = TRUE
    ),
    character()
  )
})

test_that("a database with no users and with no users table is handled", {
  db <- file_db(function(con) {
    texec(con, "CREATE TABLE users (login TEXT, password TEXT, role TEXT)")
  })
  res <- aa_migrate_plaintext_passwords(db)

  expect_identical(res$migrated, character())
  expect_identical(res$skipped, character())

  db2 <- file_db(function(con) texec(con, "CREATE TABLE other (x INTEGER)"))
  expect_error(
    aa_migrate_plaintext_passwords(db2),
    "no `users` table",
    class = "appauth_error_migration"
  )
})

test_that("invalid migration arguments are rejected", {
  expect_error(
    aa_migrate_plaintext_passwords("no-such-file.db"),
    "not found",
    class = "appauth_error_migration"
  )
  expect_error(
    aa_migrate_plaintext_passwords(NA_character_),
    class = "appauth_error_migration"
  )
  expect_error(
    aa_migrate_plaintext_passwords(c("a", "b")),
    class = "appauth_error_migration"
  )

  db <- file_db(fixture_legacy_plain)

  expect_error(
    aa_migrate_plaintext_passwords(db, backup = NA),
    class = "appauth_error_migration"
  )
  expect_error(
    aa_migrate_plaintext_passwords(db, backup = 5),
    class = "appauth_error_migration"
  )
  expect_error(
    aa_migrate_plaintext_passwords(db, dry_run = "yes"),
    class = "appauth_error_settings"
  )
})

# ---- weak accounts ------------------------------------------------------

add_user <- function(con, login, password, role = "user", hash = TRUE) {
  aa_execute(
    con,
    "INSERT INTO users (login, password, role) VALUES (?, ?, ?)",
    params = list(
      login,
      if (hash) aa_hash_password(password) else password,
      role
    )
  )
}

test_that("password = login and common passwords are found, strong passwords are left alone", {
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

test_that("plain-text passwords are found, root/root gives two reasons", {
  con <- new_db()
  aa_init_db(con)

  add_user(con, "root", "root", "admin", hash = FALSE)
  add_user(con, "hr_one", "secret12", hash = FALSE)

  res <- aa_check_default_accounts(con)

  expect_setequal(
    res$reason[res$login == "root"],
    c("plaintext", "login_as_password")
  )
  expect_identical(res$reason[res$login == "hr_one"], "plaintext")
})

test_that("legacy app after migration: weak passwords stay weak and are found", {
  db <- file_db(fixture_legacy_plain)
  suppressMessages(aa_migrate_plaintext_passwords(db, backup = FALSE))

  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  withr::defer(DBI::dbDisconnect(con))

  res <- aa_check_default_accounts(con)

  expect_identical(res$login, "root")
  expect_identical(res$reason, "login_as_password")
})

test_that("if there are no weak passwords, the result is an empty table of the right shape", {
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

test_that("the list of weak passwords can be replaced", {
  con <- new_db()
  aa_init_db(con)
  add_user(con, "u1", "company2026")

  expect_identical(nrow(aa_check_default_accounts(con)), 0L)
  expect_identical(
    aa_check_default_accounts(con, common = "company2026")$reason,
    "common_password"
  )
})

test_that("aa_check_default_accounts validates its arguments", {
  expect_error(
    aa_check_default_accounts(list()),
    class = "appauth_error_connection"
  )

  con <- new_db()
  aa_init_db(con)

  expect_error(
    aa_check_default_accounts(con, common = 1:3),
    class = "appauth_error_password"
  )
  expect_error(
    aa_check_default_accounts(con, common = c("a", NA)),
    class = "appauth_error_password"
  )
})

test_that("aa_common_passwords returns a character vector with obvious passwords", {
  common <- aa_common_passwords()

  expect_type(common, "character")
  expect_true(all(c("root", "admin", "123456", "password") %in% common))
  expect_false(anyNA(common))
})
