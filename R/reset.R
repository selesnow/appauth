# Password recovery by email and user emails.
#
# Rules these functions uphold:
#  - only the sha256 of the recovery token is stored in the database, as with auto-login tokens;
#    the token itself exists only in the email;
#  - the token is one-time and lives `reset_ttl_minutes` minutes; a new request consumes the
#    user's previous unused tokens;
#  - a recovery request never reveals whether a login or email exists:
#    the result of aa_request_password_reset() is meant for the journal, not for
#    showing to the user;
#  - emails are limited per user per hour and in total per minute;
#  - after a password change by link all auto-login tokens are revoked, all recovery
#    tokens are consumed and the lock for failed login attempts is cleared.

# Normalize an email to the stored form
#
# @param email A string or `NULL`.
#
# @returns The address without surrounding spaces in lower case, `""` for an
# empty
#   value (`NULL`, `NA`, an empty string).
# @noRd
aa_normalize_email <- function(email) {
  if (is.null(email) || length(email) != 1 || is.na(email)) {
    return("")
  }

  tolower(trimws(as.character(email)))
}

# Whether the email format is acceptable
#
# @param email A normalized address.
#
# @returns `TRUE` or `FALSE`.
# @noRd
aa_email_is_valid <- function(email) {
  is.character(email) &&
    length(email) == 1 &&
    nchar(email) <= 254 &&
    grepl(
      "^[^@[:space:]]+@[^@[:space:].][^@[:space:]]*\\.[^@[:space:].]+$",
      email
    )
}

# Find a problem in a user's email
#
# @param conn Database connection.
# @param email A normalized address (not empty).
# @param login The login the address belongs to (its own address is not
#   considered taken), or `NULL`.
#
# @returns `NULL` or a list with `reason` and `args`.
# @noRd
aa_email_problem <- function(conn, email, login = NULL) {
  if (!aa_email_is_valid(email)) {
    return(list(reason = "email_invalid", args = list()))
  }

  owner <- aa_query(
    conn,
    "SELECT login FROM users WHERE email = ?",
    params = list(email)
  )$login

  if (length(owner) > 0 && !identical(owner[1], login)) {
    return(list(reason = "email_exists", args = list()))
  }

  NULL
}

#' User email
#'
#' @inheritParams aa_get_user
#'
#' @returns The address in lower case or `NA_character_` if no address is set or
#'   the user does not exist. If the schema is not upgraded to version 7, also
#'   `NA_character_`.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_set_email(conn, "boss", "Boss@Example.com")
#'   aa_get_email(conn, "boss")
#'   DBI::dbDisconnect(conn)
#' }
aa_get_email <- function(conn, login) {
  aa_check_conn(conn)

  if (!aa_is_string(login)) {
    return(NA_character_)
  }

  email <- tryCatch(
    aa_query(
      conn,
      "SELECT email FROM users WHERE login = ?",
      params = list(login)
    )$email,
    error = function(e) character()
  )

  if (length(email) == 0) NA_character_ else as.character(email[1])
}

#' Set, change or remove a user's email
#'
#' The address is needed for password recovery ([aa_request_password_reset()]).
#' It is stored in lower case, and two users cannot have the same address.
#' An empty value (`NULL`, `NA` or `""`) removes the address. Errors (invalid
#' format,
#' address taken, no such user) have the class `appauth_error_user` and a text
#' in the
#' settings language.
#'
#' @inheritParams aa_get_user
#' @param email An address or an empty value to remove it.
#' @param settings Settings, the result of [aa_settings()].
#'
#' @returns `TRUE` if the address was saved and `FALSE` if it was removed
#' (invisibly).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_set_email(conn, "boss", "boss@example.com")
#'   aa_set_email(conn, "boss", NULL)
#'   DBI::dbDisconnect(conn)
#' }
aa_set_email <- function(conn, login, email, settings = aa_settings()) {
  aa_check_conn(conn)

  if (is.null(aa_get_user(conn, login))) {
    aa_abort_user(settings, "user_not_found")
  }

  email <- aa_normalize_email(email)

  if (!nzchar(email)) {
    aa_execute(
      conn,
      "UPDATE users SET email = NULL WHERE login = ?",
      params = list(login)
    )
    return(invisible(FALSE))
  }

  problem <- aa_email_problem(conn, email, login)
  if (!is.null(problem)) {
    aa_abort_problem(settings, problem)
  }

  tryCatch(
    aa_execute(
      conn,
      "UPDATE users SET email = ? WHERE login = ?",
      params = list(email, login)
    ),
    error = function(e) {
      # on a simultaneous write the address uniqueness constraint fires
      if (aa_is_unique_violation(e)) {
        aa_abort_user(settings, "email_exists")
      }

      stop(e)
    }
  )

  invisible(TRUE)
}

# Consume a user's password recovery tokens
#
# The table may be missing (schema not upgraded); this must not get in the
# caller's way.
#
# @param conn Database connection.
# @param login User login.
#
# @returns The number of consumed tokens (invisibly).
# @noRd
aa_invalidate_resets <- function(conn, login) {
  n <- tryCatch(
    aa_execute(
      conn,
      "UPDATE password_resets SET used = 1 WHERE user_login = ? AND used = 0",
      params = list(login)
    ),
    error = function(e) 0L
  )

  invisible(n)
}

# Delete a user's password recovery tokens
#
# @inheritParams aa_invalidate_resets
#
# @returns The number of deleted tokens (invisibly).
# @noRd
aa_delete_user_resets <- function(conn, login) {
  n <- tryCatch(
    aa_execute(
      conn,
      "DELETE FROM password_resets WHERE user_login = ?",
      params = list(login)
    ),
    error = function(e) 0L
  )

  invisible(n)
}

# Password change link
#
# @param settings Settings, the result of [aa_settings()].
# @param token Recovery token.
#
# @returns A string with the link.
# @noRd
aa_reset_link <- function(settings, token) {
  base <- sub("/+$", "", settings$reset_base_url)
  paste0(
    base,
    if (grepl("?", base, fixed = TRUE)) "&" else "/?",
    "reset=",
    token
  )
}

#' Request password recovery
#'
#' Finds a user by login or email, creates a one-time token and calls
#' `settings$send_reset(email, link, login)` to send an email with the link.
#' Only the token hash stays in the database. The user's previous unused links
#' stop working.
#'
#' No email is sent if the user does not exist, has no email, is
#' blocked by an administrator, or a limit is exceeded (`reset_max_per_hour` per
#' user, `reset_max_per_minute` overall). The function result is meant
#' for the journal: the user should be shown the same answer in every
#' case, so that it is impossible to find out which logins and addresses exist.
#'
#' An error in `send_reset` does not abort the function but is returned as
#' `send_failed`:
#' the token is consumed in that case.
#'
#' @inheritParams aa_get_user
#' @param identifier The login or email the user entered.
#' @param settings Settings, the result of [aa_settings()] with `reset_enabled =
#' TRUE`.
#'
#' @returns A list (invisibly): `sent` (`TRUE` if the email was sent), `reason`
#'   (`"sent"`, `"disabled"`, `"no_user"`, `"no_email"`, `"blocked"`,
#'   `"throttled"` or `"send_failed"`) and `login` (the found login or `NA`).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_set_email(conn, "boss", "boss@example.com")
#'
#'   settings <- aa_settings(
#'     reset_enabled  = TRUE,
#'     reset_base_url = "https://apps.example.com/my_app",
#'     send_reset = function(email, link, login) message("Link for ", login, ":
#'     ", link)
#'   )
#'   aa_request_password_reset(conn, "boss", settings)$reason
#'   aa_request_password_reset(conn, "nobody", settings)$reason
#'   DBI::dbDisconnect(conn)
#' }
aa_request_password_reset <- function(
  conn,
  identifier,
  settings = aa_settings()
) {
  aa_check_conn(conn)

  result <- function(reason, login = NA_character_) {
    invisible(list(
      sent = identical(reason, "sent"),
      reason = reason,
      login = login
    ))
  }

  if (!isTRUE(settings$reset_enabled)) {
    return(result("disabled"))
  }

  identifier <- if (aa_is_string(identifier)) trimws(identifier) else ""
  if (!nzchar(identifier)) {
    return(result("no_user"))
  }

  # the login is compared exactly, the address case-insensitively; both queries always run
  by_login <- aa_query(
    conn,
    "SELECT login, blocked, email FROM users WHERE login = ?",
    params = list(identifier)
  )
  by_email <- aa_query(
    conn,
    "SELECT login, blocked, email FROM users WHERE email = ?",
    params = list(aa_normalize_email(identifier))
  )
  user <- if (nrow(by_login) == 1) {
    by_login
  } else if (nrow(by_email) == 1) {
    by_email
  } else {
    NULL
  }

  if (is.null(user)) {
    return(result("no_user"))
  }

  login <- user$login[1]

  if (isTRUE(as.logical(user$blocked[1]))) {
    return(result("blocked", login))
  }

  email <- user$email[1]
  if (is.na(email) || !nzchar(email)) {
    return(result("no_email", login))
  }

  per_user <- aa_query(
    conn,
    "SELECT COUNT(*) AS n FROM password_resets
     WHERE user_login = ? AND created_at > ?",
    params = list(login, aa_utc(-3600))
  )$n
  overall <- aa_query(
    conn,
    "SELECT COUNT(*) AS n FROM password_resets WHERE created_at > ?",
    params = list(aa_utc(-60))
  )$n

  if (
    per_user >= settings$reset_max_per_hour ||
      overall >= settings$reset_max_per_minute
  ) {
    return(result("throttled", login))
  }

  token <- paste(as.character(openssl::rand_bytes(32)), collapse = "")
  ttl <- as.integer(round(settings$reset_ttl_minutes * 60))

  aa_invalidate_resets(conn, login)

  aa_execute(
    conn,
    "INSERT INTO password_resets (user_login, token_hash, created_at, expires_at)
     VALUES (?, ?, ?, ?)",
    params = list(login, aa_token_hash(token), aa_utc(), aa_utc(ttl))
  )

  sent <- tryCatch(
    {
      settings$send_reset(
        email = email,
        link = aa_reset_link(settings, token),
        login = login
      )
      TRUE
    },
    error = function(e) {
      message(
        "appauth: could not send the password recovery email: ",
        conditionMessage(e)
      )
      FALSE
    }
  )

  if (!sent) {
    aa_invalidate_resets(conn, login)
    return(result("send_failed", login))
  }

  result("sent", login)
}

#' User who owns a recovery link
#'
#' Checks the token from the link without changing anything: it must exist, be
#' unused and not expired, and the user must not be blocked
#' or deleted. Needed to show the new password form only for a working link.
#'
#' @inheritParams aa_get_user
#' @param token Token from the link (the `reset` parameter of the address bar).
#'
#' @returns The user login or `NULL`.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_reset_token_login(conn, "not-a-token")
#'   DBI::dbDisconnect(conn)
#' }
aa_reset_token_login <- function(conn, token) {
  aa_check_conn(conn)

  if (!aa_is_string(token)) {
    return(NULL)
  }

  res <- aa_query(
    conn,
    "SELECT r.user_login AS login
     FROM password_resets r
     JOIN users u ON u.login = r.user_login
     WHERE r.token_hash = ?
       AND r.used = 0
       AND r.expires_at > ?
       AND u.blocked = 0",
    params = list(aa_token_hash(token), aa_utc())
  )

  if (nrow(res) != 1) NULL else res$login[1]
}

#' Set a new password by the link from the email
#'
#' Checks the token ([aa_reset_token_login()]), checks the new password against
#' the rules
#' from the settings and writes it. The token is one-time: a weak password is
#' rejected
#' with an error and does not spend the token, and after a successful change the
#' link stops
#' working. Along with the password, all of the user's auto-login tokens are
#' revoked, the
#' other recovery links are consumed, and the password change requirement and
#' the
#' lock for failed login attempts are cleared.
#'
#' A wrong, expired or used link raises an error of class
#' `appauth_error_user` with `reason = "reset_link_invalid"`, a weak password an
#' error
#' of the same class with a password reason.
#'
#' @inheritParams aa_reset_token_login
#' @param password New password.
#' @param settings Settings, the result of [aa_settings()].
#'
#' @returns The login of the user whose password was changed (invisibly).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   tryCatch(
#'     aa_reset_password_with_token(conn, "not-a-token", "new-password"),
#'     appauth_error_user = function(e) conditionMessage(e)
#'   )
#'   DBI::dbDisconnect(conn)
#' }
aa_reset_password_with_token <- function(
  conn,
  token,
  password,
  settings = aa_settings()
) {
  aa_check_conn(conn)

  login <- aa_reset_token_login(conn, token)

  if (is.null(login)) {
    aa_abort_user(settings, "reset_link_invalid")
  }

  problem <- aa_password_problem(password, settings, login)
  if (!is.null(problem)) {
    aa_abort_problem(settings, problem)
  }

  # the token is taken by whoever is first: of two simultaneous requests only one works
  claimed <- aa_execute(
    conn,
    "UPDATE password_resets SET used = 1
     WHERE token_hash = ? AND used = 0 AND expires_at > ?",
    params = list(aa_token_hash(token), aa_utc())
  )

  if (claimed != 1) {
    aa_abort_user(settings, "reset_link_invalid")
  }

  aa_set_password(conn, login, password, settings, must_change = FALSE)
  aa_invalidate_resets(conn, login)
  tryCatch(aa_clear_attempts(conn, login, settings), error = function(e) NULL)

  invisible(login)
}
