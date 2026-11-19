# Users: creation, the first administrator, password login, password and role
# changes, blocking, deletion and checks of whether actions are allowed.
#
# Rules these functions uphold:
#  - logins are compared EXACTLY (case-sensitive), as in SQLite; for NEW users a
#    login that matches an existing one case-insensitively is forbidden, and
#    existing pairs are left alone;
#  - you cannot block or delete yourself and cannot be left without an active
#    (not blocked) administrator, including by changing a role;
#  - a password reset and blocking revoke autologin tokens, and deletion removes
#    the tokens and the login's failed login attempts.
#
# The action functions (aa_create_user, aa_set_password, aa_set_role,
# aa_set_blocked, aa_delete_user) abort with an error of class
# `appauth_error_user` when the rules are violated, with text in the settings
# language; the `reason` field holds the reason key from aa_text_keys(). The
# aa_check_* and aa_validate_* functions do nothing; they return the problem
# text or NULL, which is convenient to use in the interface.

#' Abort an action with the problem text
#'
#' @param settings Settings, the result of [aa_settings()].
#' @param problem The result of `aa_*_problem()`: a list with `reason` and `args`.
#' @param call The environment for the error message.
#'
#' @noRd
aa_abort_problem <- function(settings, problem, call = rlang::caller_env()) {
  rlang::abort(
    aa_problem_text(settings, problem),
    class = "appauth_error_user",
    reason = problem$reason,
    call = call
  )
}

#' User columns for a query
#'
#' The creation and last login dates appeared in the schema later than the other
#' columns: if they are not in the table yet (the schema is not fully migrated),
#' `NULL` is returned in their place.
#'
#' @param conn Database connection.
#'
#' @returns A string with the column list for `SELECT`.
#' @noRd
aa_user_columns <- function(conn) {
  cols <- aa_table_columns(conn, "users")

  paste0(
    "login, role, blocked, ",
    if ("created_at" %in% cols) "created_at" else "NULL AS created_at", ", ",
    if ("last_login_at" %in% cols) "last_login_at" else "NULL AS last_login_at"
  )
}

#' Remember the time of a successful password login
#'
#' @param conn Database connection.
#' @param login Login.
#'
#' @returns Invisibly `TRUE` if the date was recorded. An error does not
#'   interrupt login.
#' @noRd
aa_touch_last_login <- function(conn, login) {
  ok <- tryCatch(
    {
      aa_execute(
        conn,
        "UPDATE users SET last_login_at = ? WHERE login = ?",
        params = list(aa_utc(), login)
      )
      TRUE
    },
    error = function(e) {
      message("appauth: could not record the login time: ", conditionMessage(e))
      FALSE
    }
  )

  invisible(ok)
}

#' User by login
#'
#' The login is matched exactly, case-sensitive. The password is not included in
#' the result.
#'
#' @param conn A connection to the SQLite database
#'   (`DBI::dbConnect(RSQLite::SQLite(), ...)`).
#' @param login Login.
#'
#' @returns A one-row table with `login`, `role`, `blocked`, `created_at` and
#'   `last_login_at` columns, or `NULL` if there is no such user. Dates are
#'   stored as text `"YYYY-MM-DD HH:MM:SS"` in UTC; for users created before
#'   version 0.3.0 `created_at` is empty (`NA`), and `last_login_at` is empty
#'   until the user logs in with a password.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_get_user(conn, "boss")
#'   aa_get_user(conn, "nobody")
#'   DBI::dbDisconnect(conn)
#' }
aa_get_user <- function(conn, login) {
  aa_check_conn(conn)

  if (!aa_is_string(login)) {
    return(NULL)
  }

  user <- aa_query(
    conn,
    paste0("SELECT ", aa_user_columns(conn), " FROM users WHERE login = ?"),
    params = list(login)
  )

  if (nrow(user) == 0) NULL else user[1, , drop = FALSE]
}

#' List of users
#'
#' @inheritParams aa_get_user
#'
#' @returns A table with `login`, `role`, `blocked`, `created_at` and
#'   `last_login_at` columns in creation order (for the dates see
#'   [aa_get_user()]). Password hashes are not included in the result.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_list_users(conn)
#'   DBI::dbDisconnect(conn)
#' }
aa_list_users <- function(conn) {
  aa_check_conn(conn)

  aa_query(conn, paste0("SELECT ", aa_user_columns(conn), " FROM users ORDER BY ", aa_users_order(conn)))
}

#' Does the database have at least one user
#'
#' If there are no users, the app needs to show the form for creating the first
#' administrator; the package login module does this.
#'
#' @inheritParams aa_get_user
#'
#' @returns `TRUE` or `FALSE`.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_users_exist(conn)
#'   DBI::dbDisconnect(conn)
#' }
aa_users_exist <- function(conn) {
  aa_check_conn(conn)

  aa_query(conn, "SELECT COUNT(*) AS n FROM users")$n > 0
}

#' Find a problem in a new user's data
#'
#' @inheritParams aa_create_user
#' @param check_password Whether to check the password.
#'
#' @returns `NULL` or a list with `reason` and `args`.
#' @noRd
aa_new_user_problem <- function(conn, login, password, role, settings, check_password = TRUE) {
  problem <- aa_login_problem(login, settings)
  if (!is.null(problem)) return(problem)

  if (check_password) {
    problem <- aa_password_problem(password, settings, login)
    if (!is.null(problem)) return(problem)
  }

  if (!(aa_is_string(role) && role %in% settings$roles)) {
    return(list(reason = "invalid_role", args = list()))
  }

  existing <- aa_query(conn, "SELECT login FROM users")$login

  if (login %in% existing) {
    return(list(reason = "user_exists", args = list()))
  }

  # compare case in R, because SQLite lower() does not handle non-ASCII letters
  if (any(tolower(existing) == tolower(login))) {
    return(list(reason = "user_exists_case", args = list()))
  }

  NULL
}

#' Validate a new user's data
#'
#' Checks the login, password, role and login uniqueness without creating
#' anything. Suitable for showing an error in a form before the user is created.
#'
#' A login is considered taken if it matches an existing one exactly or
#' case-insensitively (so new users do not create pairs like `Kiruka` and
#' `kiruka`).
#'
#' @inheritParams aa_create_user
#'
#' @returns `NULL` if the data is fine, otherwise the problem text (in the
#'   settings language).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_validate_new_user(conn, "Boss", "another-password", "user")
#'   aa_validate_new_user(conn, "worker", "another-password", "user")
#'   DBI::dbDisconnect(conn)
#' }
aa_validate_new_user <- function(conn, login, password, role, settings = aa_settings()) {
  aa_check_conn(conn)

  aa_problem_text(settings, aa_new_user_problem(conn, login, password, role, settings))
}

#' Create a user
#'
#' Creates a user with a password hash. Before creation the login, password,
#' role (must be in `roles` from the settings) and login uniqueness are
#' checked. On a rule violation the function aborts with an error of class
#' `appauth_error_user` with text in the settings language (the `reason` field
#' holds the reason key) that can be shown to the user.
#'
#' @inheritParams aa_get_user
#' @param password The password in plain text (only the hash goes to the
#'   database).
#' @param role A role from the `roles` list of the settings.
#' @param settings Settings, the result of [aa_settings()].
#' @param must_change Require a password change at the first login (sensible if
#'   the password was set by an administrator).
#' @param email Address for password recovery or `NULL` (the address can be set
#'   later with [aa_set_email()]). The format and uniqueness are checked.
#'
#' @returns `TRUE` (invisibly).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_user(conn, "worker", "worker-password", "user")
#'   aa_list_users(conn)
#'
#'   # the error can be shown to the user
#'   tryCatch(
#'     aa_create_user(conn, "worker", "another-password", "user"),
#'     appauth_error_user = function(e) conditionMessage(e)
#'   )
#'   DBI::dbDisconnect(conn)
#' }
aa_create_user <- function(conn, login, password, role, settings = aa_settings(),
                           must_change = FALSE, email = NULL) {
  aa_check_conn(conn)

  problem <- aa_new_user_problem(conn, login, password, role, settings)
  if (!is.null(problem)) aa_abort_problem(settings, problem)

  email <- aa_normalize_email(email)
  if (nzchar(email)) {
    problem <- aa_email_problem(conn, email)
    if (!is.null(problem)) aa_abort_problem(settings, problem)
  }

  tryCatch(
    aa_execute(
      conn,
      "INSERT INTO users (login, password, role, must_change, created_at) VALUES (?, ?, ?, ?, ?)",
      params = list(login, aa_hash_password(password), role, as.integer(isTRUE(must_change)), aa_utc())
    ),
    error = function(e) {
      # on simultaneous creation the login uniqueness constraint fires
      if (aa_is_unique_violation(e)) {
        aa_abort_user(settings, "user_exists")
      }

      stop(e)
    }
  )

  if (nzchar(email)) {
    aa_set_email(conn, login, email, settings)
  }

  invisible(TRUE)
}

#' Create the first user (administrator)
#'
#' Creates a user with the `admin_role` role from the settings **only if the
#' `users` table is empty**. The check and the insert run in one SQL statement,
#' so of two simultaneous requests (two browser tabs, two sessions) only one
#' succeeds.
#'
#' The login and password are checked by the same rules as in
#' [aa_create_user()] (on a violation, an error of class `appauth_error_user`).
#'
#' @inheritParams aa_create_user
#'
#' @returns `TRUE` if the administrator was created, `FALSE` if users already
#'   exist.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_create_first_admin(conn, "second", "second-password")
#'   DBI::dbDisconnect(conn)
#' }
aa_create_first_admin <- function(conn, login, password, settings = aa_settings()) {
  aa_check_conn(conn)

  problem <- aa_login_problem(login, settings)
  if (is.null(problem)) problem <- aa_password_problem(password, settings, login)
  if (!is.null(problem)) aa_abort_problem(settings, problem)

  # PostgreSQL infers parameter types in a SELECT list only from an explicit cast
  p <- aa_text_param(conn)

  n <- aa_execute(
    conn,
    paste0(
      "INSERT INTO users (login, password, role, created_at)
       SELECT ", p, ", ", p, ", ", p, ", ", p, "
       FROM (SELECT 1 AS one) AS only_row
       WHERE NOT EXISTS (SELECT 1 FROM users)"
    ),
    params = list(login, aa_hash_password(password), settings$admin_role, aa_utc())
  )

  n == 1
}

#' Verify login and password (login)
#'
#' Looks up the user by login (exact, case-sensitive) and verifies the password
#' against the hash. If the user does not exist, verification is still run
#' against a dummy hash so the response time does not reveal whether the login
#' exists. A plain-text password in the database is never accepted.
#'
#' For a user blocked by an administrator, with a correct password a row with
#' `blocked = 1` is returned: what to do next is up to the calling code (the
#' login module reports the block only to someone who knows the password). With
#' a wrong password the result is always `NULL`.
#'
#' @inheritParams aa_get_user
#' @param password The entered password.
#'
#' @returns A one-row table with `login`, `role`, `blocked` and `must_change`
#'   columns (the password is not included in the result), or `NULL` if the
#'   login or password is wrong.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_authenticate(conn, "boss", "boss-password")
#'   aa_authenticate(conn, "boss", "wrong")
#'   DBI::dbDisconnect(conn)
#' }
aa_authenticate <- function(conn, login, password) {
  aa_check_conn(conn)

  if (!aa_is_string(login) || !aa_is_string(password)) {
    return(NULL)
  }

  # the blocked and must_change columns come from migrations; if for some
  # reason they are missing, login keeps working by password
  user <- tryCatch(
    aa_query(
      conn,
      "SELECT login, role, password, blocked, must_change FROM users WHERE login = ?",
      params = list(login)
    ),
    error = function(e) {
      u <- aa_query(
        conn,
        "SELECT login, role, password FROM users WHERE login = ?",
        params = list(login)
      )
      u$blocked <- 0L
      u$must_change <- 0L
      u
    }
  )

  if (nrow(user) != 1) {
    # no such user: verify against a dummy hash so the response time is the same
    aa_verify_password(password, aa_dummy_hash())
    return(NULL)
  }

  if (!aa_verify_password(password, user$password[1])) {
    return(NULL)
  }

  user[, c("login", "role", "blocked", "must_change"), drop = FALSE]
}

#' Set a new password for a user
#'
#' Stores the hash of the new password and **revokes all autologin tokens** of
#' the user, so that after a password reset old browser sessions stop working
#' (open sessions are ended by [aa_session_guard()]). Unused password recovery
#' links sent by email also stop working. The password is checked against the
#' rules from the settings; on a violation, an error of class
#' `appauth_error_user`.
#'
#' @inheritParams aa_create_user
#' @param must_change Require the user to change this password at the next login
#'   (sensible if the password was set by an administrator).
#' @param keep_token An autologin token that must not be revoked (the current
#'   session of the person changing their own password), or `NULL`.
#'
#' @returns The number of changed users (invisibly): 1, or 0 if there is no such
#'   login.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_set_password(conn, "boss", "new-boss-password")
#'   aa_authenticate(conn, "boss", "new-boss-password")
#'   DBI::dbDisconnect(conn)
#' }
aa_set_password <- function(conn, login, password, settings = aa_settings(),
                            must_change = FALSE, keep_token = NULL) {
  aa_check_conn(conn)

  problem <- aa_password_problem(password, settings, login)
  if (!is.null(problem)) aa_abort_problem(settings, problem)

  if (!aa_is_string(login)) {
    return(invisible(0L))
  }

  n <- aa_execute(
    conn,
    "UPDATE users SET password = ?, must_change = ? WHERE login = ?",
    params = list(aa_hash_password(password), as.integer(isTRUE(must_change)), login)
  )

  if (n > 0) {
    aa_revoke_user_tokens(
      conn, login,
      keep_hash = if (aa_is_string(keep_token)) aa_token_hash(keep_token) else NULL
    )
    # recovery links issued before the password change are no longer needed
    aa_invalidate_resets(conn, login)
  }

  invisible(n)
}

#' Can a user's role be changed
#'
#' The role must be in the `roles` list of the settings, and the administrator
#' role cannot be taken from the **last active (not blocked) administrator**,
#' otherwise nobody in the app could manage users.
#'
#' @inheritParams aa_create_user
#'
#' @returns `NULL` if allowed, otherwise the reason for refusal (in the
#'   settings language).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_check_can_change_role(conn, "boss", "user")
#'   DBI::dbDisconnect(conn)
#' }
aa_check_can_change_role <- function(conn, login, role, settings = aa_settings()) {
  aa_check_conn(conn)

  aa_problem_text(settings, aa_role_change_problem(conn, login, role, settings))
}

#' Find a problem with a role change
#'
#' @inheritParams aa_check_can_change_role
#'
#' @returns `NULL` or a list with `reason` and `args`.
#' @noRd
aa_role_change_problem <- function(conn, login, role, settings) {
  if (!aa_is_string(login)) {
    return(list(reason = "user_not_specified", args = list()))
  }

  if (!(aa_is_string(role) && role %in% settings$roles)) {
    return(list(reason = "invalid_role", args = list()))
  }

  user <- aa_get_user(conn, login)

  if (is.null(user)) {
    return(list(reason = "user_not_found", args = list()))
  }

  if (identical(user$role, settings$admin_role) && !identical(role, settings$admin_role) &&
      aa_active_admin_count(conn, settings, excluding = login) == 0) {
    return(list(reason = "cannot_change_last_admin_role", args = list()))
  }

  NULL
}

#' Change a user's role
#'
#' The role must be in the `roles` list of the settings; the administrator role
#' cannot be taken from the last active administrator (see
#' [aa_check_can_change_role()]). On a violation, an error of class
#' `appauth_error_user`.
#'
#' The user's open session keeps working with the old role until the login
#' module's next live-session check, and at the next login the role is taken
#' from the database.
#'
#' @inheritParams aa_create_user
#'
#' @returns The number of changed users (invisibly).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_create_user(conn, "worker", "worker-password", "user")
#'   aa_set_role(conn, "worker", "viewer")
#'   aa_get_user(conn, "worker")
#'   DBI::dbDisconnect(conn)
#' }
aa_set_role <- function(conn, login, role, settings = aa_settings()) {
  aa_check_conn(conn)

  problem <- aa_role_change_problem(conn, login, role, settings)
  if (!is.null(problem)) aa_abort_problem(settings, problem)

  n <- aa_execute(
    conn,
    "UPDATE users SET role = ? WHERE login = ?",
    params = list(role, login)
  )
  n <- aa_rows_matched(conn, n, login)

  invisible(n)
}

#' Find a problem with blocking or deletion
#'
#' @param action `"block"` or `"delete"`.
#' @inheritParams aa_check_can_block
#'
#' @returns `NULL` or a list with `reason` and `args`.
#' @noRd
aa_user_removal_problem <- function(conn, login, acting_login, settings, action) {
  if (!aa_is_string(login)) {
    return(list(reason = "user_not_specified", args = list()))
  }

  user <- aa_get_user(conn, login)

  if (is.null(user)) {
    return(list(reason = "user_not_found", args = list()))
  }

  if (!is.null(acting_login) && identical(login, acting_login)) {
    return(list(reason = paste0("cannot_", action, "_self"), args = list()))
  }

  # you cannot be left without active administrators
  if (identical(user$role, settings$admin_role) &&
      aa_active_admin_count(conn, settings, excluding = login) == 0) {
    return(list(reason = paste0("cannot_", action, "_last_admin"), args = list()))
  }

  NULL
}

#' Can a user be blocked
#'
#' You cannot block yourself or the last active administrator.
#'
#' @inheritParams aa_get_user
#' @param acting_login Login of the person blocking (the current administrator),
#'   or `NULL` (for example, when called from a script).
#' @param settings Settings, the result of [aa_settings()].
#'
#' @returns `NULL` if allowed, otherwise the reason for refusal (in the
#'   settings language).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_check_can_block(conn, "boss", acting_login = "boss")
#'   DBI::dbDisconnect(conn)
#' }
aa_check_can_block <- function(conn, login, acting_login = NULL, settings = aa_settings()) {
  aa_check_conn(conn)

  aa_problem_text(settings, aa_user_removal_problem(conn, login, acting_login, settings, "block"))
}

#' Can a user be deleted
#'
#' You cannot delete yourself or the last active administrator.
#'
#' @inheritParams aa_check_can_block
#'
#' @returns `NULL` if allowed, otherwise the reason for refusal (in the
#'   settings language).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_check_can_delete(conn, "boss", acting_login = "boss")
#'   DBI::dbDisconnect(conn)
#' }
aa_check_can_delete <- function(conn, login, acting_login = NULL, settings = aa_settings()) {
  aa_check_conn(conn)

  aa_problem_text(settings, aa_user_removal_problem(conn, login, acting_login, settings, "delete"))
}

#' Block or unblock a user
#'
#' A manual block closes login for the user (both by password and by autologin
#' token) without deleting the account, until an administrator lifts it. When
#' blocking, **all autologin tokens** of the user are revoked, and a session
#' already open for the user is closed at the login module's next check.
#'
#' Blocking is performed only if [aa_check_can_block()] allows it (you cannot
#' block yourself or the last active administrator), otherwise an error of class
#' `appauth_error_user`. Unblocking needs no checks and does not restore
#' revoked tokens; the user has to log in again.
#'
#' @inheritParams aa_check_can_block
#' @param blocked `TRUE` to block, `FALSE` to unblock.
#'
#' @returns The number of changed users (invisibly).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_create_user(conn, "worker", "worker-password", "user")
#'   aa_set_blocked(conn, "worker", TRUE, acting_login = "boss")
#'   aa_get_user(conn, "worker")
#'   aa_set_blocked(conn, "worker", FALSE)
#'   DBI::dbDisconnect(conn)
#' }
aa_set_blocked <- function(conn, login, blocked = TRUE, acting_login = NULL, settings = aa_settings()) {
  aa_check_conn(conn)
  aa_check_flag(blocked, "blocked")

  if (blocked) {
    problem <- aa_user_removal_problem(conn, login, acting_login, settings, "block")
    if (!is.null(problem)) aa_abort_problem(settings, problem)
  }

  if (!aa_is_string(login)) {
    return(invisible(0L))
  }

  n <- aa_execute(
    conn,
    "UPDATE users SET blocked = ? WHERE login = ?",
    params = list(as.integer(blocked), login)
  )
  n <- aa_rows_matched(conn, n, login)

  if (n > 0 && blocked) {
    aa_revoke_user_tokens(conn, login)
  }

  invisible(n)
}

#' Delete a user
#'
#' Deletes the user record, **the user's autologin tokens and failed login
#' attempts**. This matters: without deleting the tokens, a person who later
#' gets the same login could log in with the cookie of the previous owner.
#'
#' Deletion is performed only if [aa_check_can_delete()] allows it (you cannot
#' delete yourself or the last active administrator), otherwise an error of
#' class `appauth_error_user`. A session open for the user is closed at the
#' login module's next check.
#'
#' @inheritParams aa_check_can_block
#'
#' @returns The number of deleted users (invisibly).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_create_user(conn, "worker", "worker-password", "user")
#'   aa_delete_user(conn, "worker", acting_login = "boss")
#'   aa_list_users(conn)
#'   DBI::dbDisconnect(conn)
#' }
aa_delete_user <- function(conn, login, acting_login = NULL, settings = aa_settings()) {
  aa_check_conn(conn)

  problem <- aa_user_removal_problem(conn, login, acting_login, settings, "delete")
  if (!is.null(problem)) aa_abort_problem(settings, problem)

  n <- aa_execute(conn, "DELETE FROM users WHERE login = ?", params = list(login))

  if (n > 0) {
    aa_delete_user_tokens(conn, login)
    aa_delete_user_resets(conn, login)
    tryCatch(
      aa_execute(conn, "DELETE FROM totp_recovery WHERE user_login = ?", params = list(login)),
      error = function(e) NULL
    )
    # the login attempts table may not exist; this must not block deletion
    tryCatch(aa_clear_attempts(conn, login, settings), error = function(e) NULL)
  }

  invisible(n)
}

#' Change your own password
#'
#' For the user themselves: the current password must be confirmed. The new
#' password is checked against the rules from the settings and must differ from
#' the current one. Autologin tokens of other sessions are revoked; the token of
#' the current session (`keep_token`) stays. The password change requirement
#' (`must_change`) is cleared.
#'
#' Errors (wrong current password, weak or the same password) have class
#' `appauth_error_user` and text in the settings language.
#'
#' @inheritParams aa_get_user
#' @param old_password The current password.
#' @param new_password The new password.
#' @param settings Settings, the result of [aa_settings()].
#' @param keep_token Autologin token of the current session that must not be
#'   revoked.
#'
#' @returns `TRUE` (invisibly).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_change_own_password(conn, "boss", "boss-password", "new-boss-password")
#'   DBI::dbDisconnect(conn)
#' }
aa_change_own_password <- function(conn, login, old_password, new_password,
                                   settings = aa_settings(), keep_token = NULL) {
  aa_check_conn(conn)

  current <- aa_authenticate(conn, login, old_password)

  if (is.null(current) || isTRUE(current$blocked[1] == 1)) {
    aa_abort_user(settings, "password_wrong")
  }

  problem <- aa_password_problem(new_password, settings, login)
  if (!is.null(problem)) aa_abort_problem(settings, problem)

  if (identical(old_password, new_password)) {
    aa_abort_user(settings, "password_same")
  }

  aa_set_password(conn, current$login[1], new_password, settings,
                  must_change = FALSE, keep_token = keep_token)

  invisible(TRUE)
}

#' End all sessions of a user
#'
#' Revokes all autologin tokens of the user. Open sessions with such tokens are
#' ended by [aa_session_guard()] at its next check, and the cookies in browsers
#' stop working.
#'
#' @inheritParams aa_get_user
#'
#' @returns The number of revoked tokens (invisibly).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   token <- aa_issue_token(conn, "boss")
#'   aa_revoke_sessions(conn, "boss")
#'   is.null(aa_find_session_user(conn, token))
#'   DBI::dbDisconnect(conn)
#' }
aa_revoke_sessions <- function(conn, login) {
  aa_check_conn(conn)

  if (!aa_is_string(login)) {
    return(invisible(0L))
  }

  invisible(aa_revoke_user_tokens(conn, login))
}
