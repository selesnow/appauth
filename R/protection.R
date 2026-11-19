# Protection of login against password guessing.
#
# Failed attempts are counted per EXACT login (case-sensitive, like the login
# itself), regardless of whether such a login exists: so the messages cannot be
# used to learn the list of users. If max_failed_logins failed attempts
# accumulate within a window of lockout_minutes minutes, login under that login
# is blocked for lockout_minutes minutes from the last failure. Attempts made
# during the lockout are not recorded and do not extend it. A successful login
# resets the counter. There is also a global limit of failures per minute across
# all logins; it stops guessing across many logins and growth of the table.
#
# Time is stored in UTC and compared with SQLite. The counter reset after a
# success is based on the monotonic row number, not on time: time is stored with
# one-second precision, and fast events would lose their order.

#' Login key in the login attempts table
#'
#' The exact login truncated to `login_max` characters. Empty and
#' whitespace-only logins are not recorded (key `""`).
#'
#' @param login The entered login.
#' @param settings Settings, the result of [aa_settings()].
#'
#' @returns A string.
#' @noRd
aa_login_key <- function(login, settings) {
  if (!(is.character(login) && length(login) == 1 && !is.na(login)) || !nzchar(trimws(login))) {
    return("")
  }

  substr(login, 1, settings$login_max)
}

#' Record a login attempt
#'
#' Stores the result of a login attempt for brute-force protection. Attempts
#' with an empty login are not recorded. Call it only for attempts made NOT
#' during a lockout: attempts during a lockout are not recorded so as not to
#' extend it.
#'
#' @param conn A connection to the SQLite database
#'   (`DBI::dbConnect(RSQLite::SQLite(), ...)`).
#' @param login The entered login (exact, case-sensitive).
#' @param success `TRUE` for a successful login (resets the failure counter),
#'   `FALSE` for a failed attempt.
#' @param settings Settings, the result of [aa_settings()].
#'
#' @returns `TRUE` if the attempt was recorded, `FALSE` if the login is empty
#'   (invisibly).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_record_attempt(conn, "alsey", success = FALSE)
#'   DBI::dbDisconnect(conn)
#' }
aa_record_attempt <- function(conn, login, success, settings = aa_settings()) {
  aa_check_conn(conn)
  aa_check_flag(success, "success")

  key <- aa_login_key(login, settings)

  if (!nzchar(key)) {
    return(invisible(FALSE))
  }

  aa_execute(
    conn,
    "INSERT INTO login_attempts (login, success, attempted_at) VALUES (?, ?, ?)",
    params = list(key, as.integer(success), aa_utc())
  )

  invisible(TRUE)
}

#' Seconds left until a login lockout ends
#'
#' Counts the failed attempts of a login after its last successful login and
#' within the `lockout_minutes` window. If there are at least
#' `max_failed_logins` of them, the login is blocked until the end of the
#' window, counted from the last failure.
#'
#' The login is matched **exactly**: `Alsey` and `alsey` are different logins
#' with separate counters, as at login.
#'
#' @inheritParams aa_record_attempt
#'
#' @returns An integer number of seconds, 0 if login is allowed.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   for (i in 1:5) aa_record_attempt(conn, "alsey", FALSE)
#'   aa_login_lock_remaining(conn, "alsey")
#'   aa_login_lock_remaining(conn, "Alsey")
#'   DBI::dbDisconnect(conn)
#' }
aa_login_lock_remaining <- function(conn, login, settings = aa_settings()) {
  aa_check_conn(conn)

  key <- aa_login_key(login, settings)

  if (!nzchar(key)) {
    return(0L)
  }

  window_seconds <- as.integer(settings$lockout_minutes * 60)

  # failures after the last successful login (by row number) and within the window
  r <- aa_query(
    conn,
    "SELECT COUNT(*) AS n,
            MAX(attempted_at) AS last_fail
     FROM login_attempts
     WHERE login = ?
       AND success = 0
       AND attempted_at > ?
       AND id > COALESCE(
             (SELECT MAX(id) FROM login_attempts WHERE login = ? AND success = 1),
             0)",
    params = list(key, aa_utc(-window_seconds), key)
  )

  if (r$n < settings$max_failed_logins) {
    return(0L)
  }

  last_fail <- as.POSIXct(r$last_fail, tz = "UTC", format = "%Y-%m-%d %H:%M:%S")
  remaining <- as.numeric(last_fail) + window_seconds - floor(as.numeric(Sys.time()))

  max(0L, as.integer(remaining))
}

#' Is the global failed login limit exceeded
#'
#' Counts failed attempts across all logins together over the last minute. If
#' there are at least `max_failed_logins_per_minute` of them, login is
#' temporarily closed for everyone: this stops guessing across many logins and
#' growth of the attempts table.
#'
#' @inheritParams aa_record_attempt
#'
#' @returns `TRUE` or `FALSE`.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_global_throttled(conn)
#'   DBI::dbDisconnect(conn)
#' }
aa_global_throttled <- function(conn, settings = aa_settings()) {
  aa_check_conn(conn)

  n <- aa_query(
    conn,
    "SELECT COUNT(*) AS n FROM login_attempts
     WHERE success = 0 AND attempted_at > ?",
    params = list(aa_utc(-60))
  )$n

  n >= settings$max_failed_logins_per_minute
}

#' Clear a login lockout caused by failed attempts
#'
#' Deletes the failed login attempts of a login (successful ones stay), so the
#' login can be used again right away. A manual block by an administrator
#' ([aa_set_blocked()]) is not lifted by this function.
#'
#' @inheritParams aa_record_attempt
#'
#' @returns The number of deleted records (invisibly).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   for (i in 1:5) aa_record_attempt(conn, "alsey", FALSE)
#'   aa_clear_attempts(conn, "alsey")
#'   aa_login_lock_remaining(conn, "alsey")
#'   DBI::dbDisconnect(conn)
#' }
aa_clear_attempts <- function(conn, login, settings = aa_settings()) {
  aa_check_conn(conn)

  key <- aa_login_key(login, settings)

  if (!nzchar(key)) {
    return(invisible(0L))
  }

  invisible(aa_execute(
    conn,
    "DELETE FROM login_attempts WHERE login = ? AND success = 0",
    params = list(key)
  ))
}

#' Can a login be attempted right now
#'
#' A single check before verifying the password: first the global failure limit
#' across all logins, then the lockout of this login. If login is closed, there
#' is no need to verify the password, and no need to record the attempt
#' (otherwise the lockout would be extended).
#'
#' The function **does not stop login on an error**: if the protection tables
#' do not exist or cannot be queried, login is considered allowed (the password
#' is still verified) and the reason is written to the app log. This way an
#' unavailable attempts table does not lock out all users.
#'
#' @inheritParams aa_record_attempt
#'
#' @returns A list: `allowed` (`TRUE` or `FALSE`), `reason` (`NA`, `"throttled"`
#'   for the global limit or `"locked"` for a login lockout), `seconds` (how many
#'   seconds are left until the login lockout ends, otherwise 0) and `message`
#'   (text to show to the user in the settings language, `NA` if login is
#'   allowed).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_login_gate(conn, "alsey")$allowed
#'   for (i in 1:5) aa_record_attempt(conn, "alsey", FALSE)
#'   aa_login_gate(conn, "alsey")
#'   DBI::dbDisconnect(conn)
#' }
aa_login_gate <- function(conn, login, settings = aa_settings()) {
  aa_check_conn(conn)

  allowed <- list(allowed = TRUE, reason = NA_character_, seconds = 0L, message = NA_character_)

  tryCatch({
    if (aa_global_throttled(conn, settings)) {
      return(list(
        allowed = FALSE, reason = "throttled", seconds = 0L,
        message = aa_text(settings, "throttled")
      ))
    }

    seconds <- aa_login_lock_remaining(conn, login, settings)

    if (seconds > 0) {
      return(list(
        allowed = FALSE, reason = "locked", seconds = seconds,
        message = aa_text(settings, "locked", max(1L, as.integer(ceiling(seconds / 60))))
      ))
    }

    allowed
  }, error = function(e) {
    message("appauth: the login lockout check is unavailable: ", conditionMessage(e))
    allowed
  })
}

#' Users with statuses for a table
#'
#' A list of users with the flags needed for the table on the access management
#' tab: whether the user is blocked by an administrator, whether login is
#' blocked after failed attempts and how much time is left. If the attempts
#' tables are unavailable, the attempt-based lockout status is treated as
#' absent.
#'
#' @inheritParams aa_record_attempt
#'
#' @returns A table with columns `login`, `role`, `blocked`, `state`
#'   (`"blocked"` for a block by an administrator, `"locked"` for a lockout by
#'   attempts, otherwise `"ok"`), `lock_seconds` (seconds until the attempt
#'   lockout ends) and `status` (status text in the settings language, an empty
#'   string for `"ok"`), as well as `created_at` and `last_login_at` (dates from
#'   the database in UTC, as in [aa_get_user()]) and `created` and `last_login`
#'   (the same dates for display: server local time, with the texts for
#'   "unknown" and "never logged in" for unknown dates), as well as `has_email`
#'   (1 if an email is set for password recovery; the address itself is not
#'   included), `totp_on` (1 if the user has 2FA enabled) and `autologins` (how
#'   many active autologins, see [aa_active_autologins()]).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_users_overview(conn)
#'   DBI::dbDisconnect(conn)
#' }
aa_users_overview <- function(conn, settings = aa_settings()) {
  aa_check_conn(conn)

  users <- aa_list_users(conn)

  if (nrow(users) == 0) {
    return(data.frame(
      login = character(), role = character(), blocked = integer(),
      state = character(), lock_seconds = integer(), status = character(),
      created_at = character(), last_login_at = character(),
      created = character(), last_login = character(),
      has_email = integer(), totp_on = integer(), autologins = integer(),
      stringsAsFactors = FALSE
    ))
  }

  # email and 2FA: an old schema may lack the columns, then treat them as not set
  flags <- tryCatch(
    aa_query(
      conn,
      "SELECT login,
              CASE WHEN email IS NULL OR email = '' THEN 0 ELSE 1 END AS has_email,
              CASE WHEN totp_enabled = 1 THEN 1 ELSE 0 END AS totp_on
       FROM users"
    ),
    error = function(e) NULL
  )
  by_login <- function(column) {
    if (is.null(flags)) {
      return(rep(0L, nrow(users)))
    }
    as.integer(flags[[column]][match(users$login, flags$login)])
  }
  has_email <- by_login("has_email")
  totp_on <- by_login("totp_on")
  has_email[is.na(has_email)] <- 0L
  totp_on[is.na(totp_on)] <- 0L

  autologin_counts <- aa_active_autologins(conn)
  autologins <- autologin_counts$n[match(users$login, autologin_counts$login)]
  autologins[is.na(autologins)] <- 0L

  lock_seconds <- vapply(users$login, function(login) {
    tryCatch(aa_login_lock_remaining(conn, login, settings), error = function(e) 0L)
  }, integer(1), USE.NAMES = FALSE)

  state <- ifelse(users$blocked == 1, "blocked", ifelse(lock_seconds > 0, "locked", "ok"))

  status <- vapply(seq_len(nrow(users)), function(i) {
    switch(
      state[i],
      blocked = aa_text(settings, "status_blocked"),
      locked  = aa_text(settings, "status_locked", max(1L, as.integer(ceiling(lock_seconds[i] / 60)))),
      ""
    )
  }, character(1))

  data.frame(
    login        = users$login,
    role         = users$role,
    blocked      = as.integer(users$blocked),
    state        = state,
    lock_seconds = lock_seconds,
    status       = status,
    created_at    = as.character(users$created_at),
    last_login_at = as.character(users$last_login_at),
    created       = aa_format_db_time(users$created_at, aa_text(settings, "date_unknown")),
    last_login    = aa_format_db_time(users$last_login_at, aa_text(settings, "date_never")),
    has_email     = has_email,
    totp_on       = totp_on,
    autologins    = as.integer(autologins),
    stringsAsFactors = FALSE
  )
}
