# Internal helpers for working with the authentication tables. Used by the
# user, login protection and session functions; not exported.

#' Revoke all auto-login tokens of a user
#'
#' Tokens stay in the table flagged `revoked = 1` and stop working.
#' Needed on password reset and when a user is blocked.
#'
#' @param conn Database connection.
#' @param login User login.
#' @param keep_hash Hash of a token to keep valid (the token of the current
#'   session when changing one's own password), or `NULL`.
#'
#' @returns Number of revoked tokens.
#' @noRd
aa_revoke_user_tokens <- function(conn, login, keep_hash = NULL) {
  if (is.null(keep_hash)) {
    aa_execute(
      conn,
      "UPDATE auth_sessions SET revoked = 1 WHERE user_login = ?",
      params = list(login)
    )
  } else {
    aa_execute(
      conn,
      "UPDATE auth_sessions SET revoked = 1 WHERE user_login = ? AND token_hash <> ?",
      params = list(login, keep_hash)
    )
  }
}

#' Delete auto-login tokens of a user
#'
#' Needed when deleting a user: without it, a person who later receives the same
#' login could sign in with the cookie of the previous owner.
#'
#' @inheritParams aa_revoke_user_tokens
#'
#' @returns Number of deleted tokens.
#' @noRd
aa_delete_user_tokens <- function(conn, login) {
  aa_execute(
    conn,
    "DELETE FROM auth_sessions WHERE user_login = ?",
    params = list(login)
  )
}

#' Number of active (not blocked) administrators
#'
#' @param conn Database connection.
#' @param settings Settings, the result of [aa_settings()].
#' @param excluding Login to leave out (for example, the one being blocked
#'   or deleted), or `NULL`.
#'
#' @returns An integer.
#' @noRd
aa_active_admin_count <- function(conn, settings, excluding = NULL) {
  if (is.null(excluding)) {
    aa_query(
      conn,
      "SELECT COUNT(*) AS n FROM users WHERE role = ? AND blocked = 0",
      params = list(settings$admin_role)
    )$n
  } else {
    aa_query(
      conn,
      "SELECT COUNT(*) AS n FROM users WHERE role = ? AND blocked = 0 AND login <> ?",
      params = list(settings$admin_role, excluding)
    )$n
  }
}

#' User action error
#'
#' Aborts with a message in the settings language. The application can
#' catch the error and show its text to the user; the class `appauth_error_user`
#' is common, and the `reason` field holds the reason key (for example, `"user_exists"`).
#'
#' @param settings Settings, the result of [aa_settings()].
#' @param reason Text key from [aa_text_keys()].
#' @param ... Values to substitute into the text.
#' @param call Environment for the error message.
#'
#' @noRd
aa_abort_user <- function(settings, reason, ..., call = rlang::caller_env()) {
  rlang::abort(
    aa_text(settings, reason, ...),
    class = "appauth_error_user",
    reason = reason,
    call = call
  )
}
