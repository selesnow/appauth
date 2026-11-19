# Passwords: hashing, verification, rules, migration from plain text.
#
# Passwords are stored only as a scrypt hash (sodium package). The hash contains
# the salt and parameters and starts with the "$7$" prefix. A value in the
# password column that is not a hash never passes verification: plain-text
# passwords are not compared.

#' Hash a password
#'
#' Returns a scrypt hash (`sodium` package) for storing in the database. The
#' hash contains the salt and parameters, so two calls with the same password
#' give different strings, and verification is done by [aa_verify_password()].
#' The hash is irreversible: the password cannot be recovered from it.
#'
#' The function does not check password length rules, use
#' [aa_validate_password()] for that.
#'
#' @param password The password, a non-empty string.
#'
#' @returns A string with the hash, starting with `$7$`.
#' @export
#'
#' @examples
#' hash <- aa_hash_password("secret-password")
#' substr(hash, 1, 3)
#' aa_verify_password("secret-password", hash)
aa_hash_password <- function(password) {
  if (!aa_is_string(password)) {
    rlang::abort(
      "The password must be a non-empty string.",
      class = "appauth_error_password"
    )
  }

  sodium::password_store(password)
}

#' Is the value a password hash
#'
#' Distinguishes a hash created by [aa_hash_password()] from a plain-text
#' password. The function is vectorized; `NA` is not considered a hash.
#'
#' @param x A character vector, for example the `password` column of the
#'   `users` table.
#'
#' @returns A logical vector of the same length.
#' @export
#'
#' @examples
#' aa_is_password_hash(c(aa_hash_password("secret"), "root", NA))
aa_is_password_hash <- function(x) {
  !is.na(x) & grepl("^\\$7\\$", x)
}

#' Verify a password against a hash
#'
#' Compares the entered password with the stored hash. If the stored value is
#' not a hash (for example, a plain-text password), the result is always
#' `FALSE`: plain-text passwords are not compared. A corrupted hash and invalid
#' arguments also give `FALSE`; the function does not throw errors.
#'
#' @param password The entered password.
#' @param stored The value from the `password` column of the `users` table.
#'
#' @returns `TRUE` or `FALSE`.
#' @export
#'
#' @examples
#' hash <- aa_hash_password("secret")
#' aa_verify_password("secret", hash)
#' aa_verify_password("other", hash)
#'
#' # a plain-text password does not pass verification, even if it matches
#' aa_verify_password("root", "root")
aa_verify_password <- function(password, stored) {
  if (!aa_is_string(password)) {
    return(FALSE)
  }

  if (!(is.character(stored) && length(stored) == 1 && aa_is_password_hash(stored))) {
    return(FALSE)
  }

  isTRUE(tryCatch(sodium::password_verify(stored, password), error = function(e) FALSE))
}

# Dummy hash that equalizes verification time when the user does not exist:
# verifying against it takes as long as against a real hash, so the response
# time does not reveal whether such a login exists. Created once per R
# session.
.aa_dummy <- new.env(parent = emptyenv())

#' Dummy hash for equalizing verification time
#'
#' @returns A string with the hash (the same during an R session).
#' @noRd
aa_dummy_hash <- function() {
  if (is.null(.aa_dummy$hash)) {
    .aa_dummy$hash <- aa_hash_password("dummy-password-for-timing")
  }

  .aa_dummy$hash
}

#' Find a weakness in a password
#'
#' Checks a password that has already passed the length rules: whether it is in
#' the list of common weak passwords, whether it equals the login
#' (case-insensitive) and whether it consists of one repeated character.
#'
#' @param password The password to check.
#' @param login User login or `NULL` if unknown.
#'
#' @returns A text key (`password_common`, `password_equals_login`,
#'   `password_repeated`) or `NULL` if no weaknesses were found.
#' @noRd
aa_password_weakness <- function(password, login = NULL) {
  if (!aa_is_string(password)) {
    return(NULL)
  }

  lower <- tolower(password)

  if (aa_is_string(login) && identical(lower, tolower(login))) {
    return("password_equals_login")
  }

  if (lower %in% aa_common_passwords()) {
    return("password_common")
  }

  chars <- strsplit(password, "", fixed = TRUE)[[1]]
  if (length(chars) >= 2 && length(unique(chars)) == 1) {
    return("password_repeated")
  }

  NULL
}

#' Find a problem in a new password
#'
#' @param password The password to check.
#' @param settings Settings, the result of [aa_settings()].
#' @param login User login for checking whether the password equals the login
#'   (optional). Weak passwords are rejected only if
#'   `settings$password_policy` is `"reject"`.
#'
#' @returns `NULL` if the password is fine, otherwise a list with `reason` (a
#'   text key) and `args` (values to substitute into the text).
#' @noRd
aa_password_problem <- function(password, settings, login = NULL) {
  if (!aa_is_string(password)) {
    return(list(reason = "password_empty", args = list()))
  }

  n <- nchar(password, type = "chars")

  if (n < settings$password_min) {
    return(list(reason = "password_too_short", args = list(as.integer(settings$password_min))))
  }

  if (n > settings$password_max) {
    return(list(reason = "password_too_long", args = list(as.integer(settings$password_max))))
  }

  if (identical(settings$password_policy, "reject")) {
    weakness <- aa_password_weakness(password, login)
    if (!is.null(weakness)) {
      return(list(reason = weakness, args = list()))
    }
  }

  NULL
}

#' Weak password warning (`password_policy = "warn"` mode)
#'
#' @param password The password that was just accepted.
#' @param settings Settings, the result of [aa_settings()].
#' @param login User login or `NULL`.
#'
#' @returns A list with `reason` (the reason key) and `text` (the ready
#'   message), or `NULL` if the mode is not `"warn"` or there are no
#'   weaknesses.
#' @noRd
aa_password_warning <- function(password, settings, login = NULL) {
  if (!identical(settings$password_policy, "warn")) {
    return(NULL)
  }

  weakness <- aa_password_weakness(password, login)
  if (is.null(weakness)) {
    return(NULL)
  }

  list(
    reason = weakness,
    text   = aa_text(settings, "weak_password_notice", aa_text(settings, weakness))
  )
}

#' Find a problem in a new user's login
#'
#' @param login The login to check.
#' @param settings Settings, the result of [aa_settings()].
#'
#' @returns `NULL` if the login is fine, otherwise a list with `reason` and
#'   `args`.
#' @noRd
aa_login_problem <- function(login, settings) {
  if (!(is.character(login) && length(login) == 1 && !is.na(login) && nzchar(trimws(login)))) {
    return(list(reason = "login_empty", args = list()))
  }

  # login compares the login exactly, so edge whitespace would cause confusion
  if (!identical(login, trimws(login))) {
    return(list(reason = "login_whitespace", args = list()))
  }

  if (nchar(login, type = "chars") > settings$login_max) {
    return(list(reason = "login_too_long", args = list(as.integer(settings$login_max))))
  }

  NULL
}

#' Problem text in the settings language
#'
#' @param settings Settings, the result of [aa_settings()].
#' @param problem The result of `aa_password_problem()` or `aa_login_problem()`.
#'
#' @returns A string, or `NULL` if there is no problem.
#' @noRd
aa_problem_text <- function(settings, problem) {
  if (is.null(problem)) {
    return(NULL)
  }

  do.call(aa_text, c(list(settings, problem$reason), problem$args))
}

#' Validate a new password against the rules
#'
#' Checks a password being set for a user (on creation or reset). The rules come
#' from the settings: minimum and maximum length are counted in characters, not
#' bytes. The limits apply only to new passwords; existing passwords are not
#' affected.
#'
#' If the settings have `password_policy = "reject"`, weak passwords (from the
#' [aa_common_passwords()] list, equal to the login, one repeated character)
#' are also an error. The `"warn"` mode does not reject the password: a weak
#' password is reported by [aa_weak_password_warning()].
#'
#' @param password The password to check.
#' @param settings Settings, the result of [aa_settings()].
#' @param login User login, needed to check whether the password equals the
#'   login (optional).
#'
#' @returns `NULL` if the password is fine, otherwise the error text (in the
#'   settings language).
#' @export
#'
#' @examples
#' aa_validate_password("abc")
#' aa_validate_password("long-enough-password")
#' aa_validate_password("long-enough-password", aa_settings(password_min = 30))
aa_validate_password <- function(password, settings = aa_settings(), login = NULL) {
  aa_problem_text(settings, aa_password_problem(password, settings, login))
}

#' Weak password warning
#'
#' In the `password_policy = "warn"` mode (the default) a weak password is
#' accepted, but the user should be told to choose a stronger one: the built-in
#' modules show this as a notification after a successful password change. The
#' function is for apps with their own interface. A password is weak if it is
#' in the [aa_common_passwords()] list, equals the login (case-insensitive) or
#' consists of one repeated character.
#'
#' @param password The accepted password.
#' @param settings Settings, the result of [aa_settings()].
#' @param login User login (optional).
#'
#' @returns The warning text (in the settings language), or `NULL` if the mode
#'   is not `"warn"` or there are no weaknesses.
#' @export
#'
#' @examples
#' aa_weak_password_warning("123456")
#' aa_weak_password_warning("boss", login = "Boss")
#' aa_weak_password_warning("long-and-unusual-phrase")
aa_weak_password_warning <- function(password, settings = aa_settings(), login = NULL) {
  aa_password_warning(password, settings, login)$text
}

#' Validate a new user's login
#'
#' The login must not be empty, must not start or end with whitespace (login
#' compares the login exactly, so such logins would cause confusion; the input
#' field in the package UI trims edge whitespace itself) and must not be longer
#' than `login_max` characters from the settings.
#'
#' @param login The login to check.
#' @param settings Settings, the result of [aa_settings()].
#'
#' @returns `NULL` if the login is fine, otherwise the error text (in the
#'   settings language).
#' @export
#'
#' @examples
#' aa_validate_login("alsey")
#' aa_validate_login("   ")
#' aa_validate_login(" alsey")
aa_validate_login <- function(login, settings = aa_settings()) {
  aa_problem_text(settings, aa_login_problem(login, settings))
}

#' Migrate passwords from plain text to hashes
#'
#' A one-time migration for apps with legacy home-grown authentication, where
#' passwords in the `users` table are stored in plain text. All values of the
#' `password` column that are not hashes are replaced with scrypt hashes.
#' Already hashed passwords are skipped, so the function can be run repeatedly.
#'
#' How it works: before any change a backup copy of the database file is made
#' (if there is something to change and `backup` is not `FALSE`), all changes
#' run in a single transaction, and every new hash is verified against the
#' original password before being written. On any error the changes are rolled
#' back. The function never prints passwords.
#'
#' **Run the function while the app is stopped.** The backup contains plain-text
#' passwords: delete it after checking (and make sure it is not in synchronized
#' folders or in git). After the migration, logging in with the old passwords
#' still works, because the entered password is verified against the new hash.
#'
#' @param db_path Path to the SQLite database file.
#' @param backup `TRUE` (default) - a copy next to the database named
#'   `<database>.bak_<date>`, a string - your own path for the copy, `FALSE` -
#'   no copy (not recommended).
#' @param dry_run If `TRUE`, change nothing and only show whose passwords would
#'   be migrated.
#'
#' @returns A list (invisibly): `migrated` (logins whose passwords were or would
#'   be migrated), `skipped` (logins whose password is already a hash),
#'   `backup` (path to the copy or `NA`), `dry_run`.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   db <- tempfile(fileext = ".db")
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), db)
#'   DBI::dbExecute(conn, "CREATE TABLE users (login TEXT, password TEXT, role TEXT)")
#'   DBI::dbExecute(conn, "INSERT INTO users VALUES ('alsey', 'plain-secret', 'admin')")
#'   DBI::dbDisconnect(conn)
#'
#'   # what would be migrated
#'   aa_migrate_plaintext_passwords(db, dry_run = TRUE)
#'
#'   # run without a backup (in this example only; keep the backup in real use)
#'   aa_migrate_plaintext_passwords(db, backup = FALSE)
#' }
aa_migrate_plaintext_passwords <- function(db_path, backup = TRUE, dry_run = FALSE) {
  rlang::check_installed("RSQLite", reason = "to migrate passwords to hashes.")

  if (!(aa_is_string(db_path) && file.exists(db_path))) {
    rlang::abort(
      paste0("Database file not found: ", paste(db_path, collapse = ", ")),
      class = "appauth_error_migration"
    )
  }

  aa_check_flag(dry_run, "dry_run")

  if (!(is.logical(backup) && length(backup) == 1 && !is.na(backup)) && !aa_is_string(backup)) {
    rlang::abort(
      "`backup` must be TRUE, FALSE or a path to the backup file.",
      class = "appauth_error_migration"
    )
  }

  conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  if (!DBI::dbExistsTable(conn, "users")) {
    rlang::abort(
      "The database has no `users` table, nothing to migrate.",
      class = "appauth_error_migration"
    )
  }

  # the row key is login (it is unique); old databases may have no id column
  users <- aa_query(conn, "SELECT login, password FROM users")
  is_hash <- aa_is_password_hash(users$password)
  to_migrate <- users[!is_hash, , drop = FALSE]

  result <- list(
    migrated = to_migrate$login,
    skipped  = users$login[is_hash],
    backup   = NA_character_,
    dry_run  = dry_run
  )

  if (dry_run || nrow(to_migrate) == 0) {
    return(invisible(result))
  }

  # backup copy of the database file before any changes
  if (!identical(backup, FALSE)) {
    backup_path <- if (isTRUE(backup)) {
      paste0(db_path, ".bak_", format(Sys.time(), "%Y%m%d_%H%M%S"))
    } else {
      backup
    }

    if (!file.copy(db_path, backup_path)) {
      rlang::abort(
        paste0("Could not create a backup copy: ", backup_path),
        class = "appauth_error_migration"
      )
    }

    result$backup <- backup_path
  }

  tryCatch(
    DBI::dbWithTransaction(conn, {
      for (i in seq_len(nrow(to_migrate))) {
        plain <- to_migrate$password[i]
        login <- to_migrate$login[i]

        if (!aa_is_string(plain)) {
          rlang::abort(paste0("User ", login, " has an empty password."))
        }

        new_hash <- aa_hash_password(plain)

        # make sure the hash matches the original password before writing
        if (!aa_verify_password(plain, new_hash)) {
          rlang::abort(paste0("The hash failed verification for ", login, "."))
        }

        aa_execute(
          conn,
          "UPDATE users SET password = ? WHERE login = ?",
          params = list(new_hash, login)
        )
      }
    }),
    error = function(e) {
      rlang::abort(
        paste0("Migration cancelled, no changes were applied: ", conditionMessage(e)),
        class = "appauth_error_migration",
        parent = e
      )
    }
  )

  if (!is.na(result$backup)) {
    rlang::inform(paste0(
      "The database backup contains plain-text passwords: ", result$backup,
      ". Delete it after checking."
    ))
  }

  invisible(result)
}

#' List of common weak passwords
#'
#' Used by [aa_check_default_accounts()] by default.
#'
#' @returns A character vector.
#' @export
#'
#' @examples
#' head(aa_common_passwords())
aa_common_passwords <- function() {
  c(
    "root", "admin", "administrator", "password", "passw0rd", "pass", "test",
    "tester", "user", "guest", "demo", "changeme", "welcome", "letmein",
    "qwerty", "qwerty123", "1234", "12345", "123456", "1234567", "12345678",
    "123456789", "1234567890", "111111", "000000", "abc123", "iloveyou"
  )
}

#' Find accounts with weak passwords
#'
#' A hygiene check of the `users` table: finds users whose password is stored in
#' plain text, equals the login (lower and upper case too) or is in the list of
#' common weak passwords. The check works on hashes; the function does not show
#' plain-text passwords. The check can take a few seconds per user because of
#' strong hashing.
#'
#' A single user can have several result rows, for example for the plain-text
#' password `root` of the login `root`.
#'
#' @param conn A connection to the SQLite database that already has the `users`
#'   table.
#' @param common List of weak passwords to check, by default
#'   [aa_common_passwords()].
#'
#' @returns A table with `login`, `role` and `reason` columns: `plaintext` (the
#'   password is stored in plain text), `login_as_password` (the password equals
#'   the login) or `common_password` (a password from the weak list). If there
#'   are no such users, the table is empty.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   DBI::dbExecute(
#'     conn, "INSERT INTO users (login, password, role) VALUES (?, ?, 'user')",
#'     params = list("tester", aa_hash_password("tester"))
#'   )
#'   aa_check_default_accounts(conn)
#'   DBI::dbDisconnect(conn)
#' }
aa_check_default_accounts <- function(conn, common = aa_common_passwords()) {
  aa_check_conn(conn)

  if (!(is.character(common) && !anyNA(common))) {
    rlang::abort(
      "`common` must be a character vector.",
      class = "appauth_error_password"
    )
  }

  users <- aa_query(conn, paste0("SELECT login, role, password FROM users ORDER BY ", aa_users_order(conn)))

  found <- list()
  add <- function(i, reason) {
    found[[length(found) + 1]] <<- data.frame(
      login = users$login[i], role = users$role[i], reason = reason,
      stringsAsFactors = FALSE
    )
  }

  for (i in seq_len(nrow(users))) {
    stored <- users$password[i]
    login  <- users$login[i]
    login_variants <- unique(c(login, tolower(login), toupper(login)))

    if (!aa_is_password_hash(stored)) {
      # plain-text password: this is already a problem, and also check whether it is weak
      add(i, "plaintext")

      if (!is.na(stored) && stored %in% login_variants) {
        add(i, "login_as_password")
      } else if (!is.na(stored) && stored %in% common) {
        add(i, "common_password")
      }

      next
    }

    if (any(vapply(login_variants, aa_verify_password, logical(1), stored = stored))) {
      add(i, "login_as_password")
    } else if (any(vapply(common, aa_verify_password, logical(1), stored = stored))) {
      add(i, "common_password")
    }
  }

  if (length(found) == 0) {
    return(data.frame(login = character(), role = character(), reason = character(),
                      stringsAsFactors = FALSE))
  }

  do.call(rbind, found)
}
