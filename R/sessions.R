#' Autologin token hash
#'
#' Only the sha256 of the token is stored in the database, as text (64
#' characters).
#'
#' @param token Token from the cookie.
#'
#' @returns A string of 64 characters.
#' @noRd
aa_token_hash <- function(token) {
  as.character(openssl::sha256(token))
}

#' Issue an autologin token
#'
#' Creates a random token (32 bytes) and stores its hash and expiry
#' (`session_days` from [aa_settings()]) in the database. The token itself must
#' be handed to the browser (in a cookie); it cannot be recovered from the
#' database.
#'
#' No token is issued (`NULL` is returned) if autologin is disabled in the
#' settings, the user does not exist or the user is blocked.
#'
#' @param conn Database connection.
#' @param login User login.
#' @param settings Settings, the result of [aa_settings()].
#'
#' @returns A string with the token or `NULL`.
#' @export
#'
#' @examples
#' \dontrun{
#' token <- aa_issue_token(conn, "ivan")
#' if (!is.null(token)) session$sendCustomMessage("setAuthCookie", token)
#' }
aa_issue_token <- function(conn, login, settings = aa_settings()) {
  if (!isTRUE(settings$autologin) || !aa_is_string(login)) {
    return(NULL)
  }

  user <- aa_get_user(conn, login)
  if (is.null(user) || isTRUE(as.logical(user$blocked))) {
    return(NULL)
  }

  token <- openssl::base64_encode(openssl::rand_bytes(32))
  ttl <- as.integer(round(settings$session_days * 86400))

  aa_execute(
    conn,
    "INSERT INTO auth_sessions (user_login, token_hash, created_at, expires_at)
     VALUES (?, ?, ?, ?)",
    params = list(user$login, aa_token_hash(token), aa_utc(), aa_utc(ttl))
  )

  token
}

#' Find a user by autologin token
#'
#' Returns the user only if the token exists, is not revoked and has not
#' expired, and the user exists, is not blocked and is not required to change
#' the password (after a password change the user must log in again). The role
#' is taken from the database at the time of the check.
#'
#' @inheritParams aa_issue_token
#' @param token Token from the cookie.
#'
#' @returns A list with `login` and `role` fields, or `NULL`.
#' @export
#'
#' @examples
#' \dontrun{
#' user <- aa_find_session_user(conn, input$auth_cookie)
#' if (!is.null(user)) { # the user logs in without a password }
#' }
aa_find_session_user <- function(conn, token) {
  if (!aa_is_string(token)) {
    return(NULL)
  }

  res <- aa_query(
    conn,
    "SELECT u.login, u.role
     FROM auth_sessions s
     JOIN users u ON u.login = s.user_login
     WHERE s.token_hash = ?
       AND s.revoked = 0
       AND s.expires_at > ?
       AND u.blocked = 0
       AND u.must_change = 0",
    params = list(aa_token_hash(token), aa_utc())
  )

  if (nrow(res) != 1) {
    return(NULL)
  }

  list(login = res$login[1], role = res$role[1])
}

#' Revoke an autologin token
#'
#' Needed on logout: the cookie in the browser stops working afterwards.
#'
#' @inheritParams aa_find_session_user
#'
#' @returns The number of revoked tokens (0 or 1), invisibly.
#' @export
#'
#' @examples
#' \dontrun{
#' aa_revoke_token(conn, input$auth_cookie)
#' }
aa_revoke_token <- function(conn, token) {
  if (!aa_is_string(token)) {
    return(invisible(0L))
  }

  invisible(aa_execute(
    conn,
    "UPDATE auth_sessions SET revoked = 1 WHERE token_hash = ?",
    params = list(aa_token_hash(token))
  ))
}

#' Is the autologin token active
#'
#' @param conn Database connection.
#' @param token Token from the cookie.
#'
#' @returns `TRUE` if the token exists, is not revoked and has not expired.
#' @noRd
aa_token_active <- function(conn, token) {
  n <- aa_query(
    conn,
    "SELECT COUNT(*) AS n FROM auth_sessions
     WHERE token_hash = ? AND revoked = 0 AND expires_at > ?",
    params = list(aa_token_hash(token), aa_utc())
  )$n

  n > 0
}

#' How many active autologins users have
#'
#' Counts autologin tokens that are not revoked and have not expired: that many
#' devices currently "remember" the user's login (cookie), i.e. can log in
#' without a password. This is not the number of open tabs: the app does not
#' track them. If the token table does not exist or cannot be queried, it is
#' assumed there are no tokens.
#'
#' @param conn Database connection.
#' @param login User login or `NULL`.
#'
#' @returns For a given `login`, an integer (0 if there are no tokens). With
#'   `login = NULL`, a table with `login` and `n` columns for users that have
#'   active tokens.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_issue_token(conn, "boss")
#'   aa_active_autologins(conn, "boss")
#'   DBI::dbDisconnect(conn)
#' }
aa_active_autologins <- function(conn, login = NULL) {
  aa_check_conn(conn)

  counts <- tryCatch(
    aa_query(
      conn,
      "SELECT user_login AS login, COUNT(*) AS n FROM auth_sessions
       WHERE revoked = 0 AND expires_at > ?
       GROUP BY user_login",
      params = list(aa_utc())
    ),
    error = function(e) data.frame(login = character(), n = integer(), stringsAsFactors = FALSE)
  )
  counts$n <- as.integer(counts$n)

  if (is.null(login)) {
    return(counts)
  }
  if (!aa_is_string(login)) {
    return(0L)
  }

  n <- counts$n[counts$login == login]
  if (length(n) == 0) 0L else n[1]
}

#' Check that an open session is still valid
#'
#' Called periodically (every `session_check_seconds`) so that blocking,
#' deletion, role demotion and session termination take effect for a user who
#' is already logged in, not only at the next login. A session is invalid if
#' the user was deleted or blocked, the role in the database differs from the
#' role in the session, or the token of this session was revoked (password
#' reset, "end all sessions").
#'
#' If the database cannot be read, the session is considered valid
#' (`reason = "check_failed"`) so that a database failure does not kick out all
#' users; access is not widened, because no password is checked.
#'
#' @inheritParams aa_issue_token
#' @param role The role the user logged in with.
#' @param token Autologin token of this session (`auth$token()`) or `NULL` if
#'   the session has no token (for example, autologin is disabled): then the
#'   token is not checked.
#'
#' @returns A list: `valid` (logical), `reason` (`"ok"`, `"deleted"`,
#'   `"blocked"`, `"role_changed"`, `"token_revoked"`, `"check_failed"`) and
#'   `role` (the current role from the database or `NULL`).
#' @export
#'
#' @examples
#' \dontrun{
#' check <- aa_user_session_valid(conn, auth$user()$login, auth$user()$role, auth$token())
#' if (!check$valid) auth$logout(reason = check$reason)
#' }
aa_user_session_valid <- function(conn, login, role, token = NULL) {
  user <- tryCatch(aa_get_user(conn, login), error = function(e) e)

  if (inherits(user, "error")) {
    return(list(valid = TRUE, reason = "check_failed", role = NULL))
  }
  if (is.null(user)) {
    return(list(valid = FALSE, reason = "deleted", role = NULL))
  }
  if (isTRUE(as.logical(user$blocked))) {
    return(list(valid = FALSE, reason = "blocked", role = user$role))
  }
  if (!identical(as.character(user$role), as.character(role))) {
    return(list(valid = FALSE, reason = "role_changed", role = user$role))
  }

  if (aa_is_string(token)) {
    active <- tryCatch(aa_token_active(conn, token), error = function(e) NA)

    if (isFALSE(active)) {
      return(list(valid = FALSE, reason = "token_revoked", role = user$role))
    }
  }

  list(valid = TRUE, reason = "ok", role = user$role)
}
