# Two-factor authentication: one-time TOTP codes (RFC 6238) and recovery codes.
#
# Rules these functions uphold:
#  - the secret is stored in the database only in encrypted form (sodium, key from the
#    `totp_key` setting), so the database alone is not enough to get codes;
#  - until the user confirms a code from the app, 2FA is not enabled
#    (`totp_enabled = 0`), and a pending secret can be replaced;
#  - the same code (time step) is accepted once: `totp_last_step`
#    protects against reuse of a code that was spied on;
#  - recovery codes are one-time, only sha256 is stored in the database;
#  - guessing codes is limited by the general login protection: a wrong code is recorded as a
#    failed login attempt (aa_record_attempt), and aa_login_gate() is called
#    before the code is checked.

aa_base32_alphabet <- "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

# Base32 encoding (RFC 4648, without padding)
#
# @param x A `raw` vector.
#
# @returns A string of `A-Z2-7` characters.
# @noRd
aa_base32_encode <- function(x) {
  if (length(x) == 0) {
    return("")
  }

  bits <- unlist(lapply(as.integer(x), function(b) {
    as.integer(rev(intToBits(b)[1:8]))
  }))
  pad <- (5 - length(bits) %% 5) %% 5
  bits <- c(bits, rep(0L, pad))
  groups <- matrix(bits, ncol = 5, byrow = TRUE)
  idx <- as.vector(groups %*% c(16L, 8L, 4L, 2L, 1L)) + 1L

  paste(strsplit(aa_base32_alphabet, "")[[1]][idx], collapse = "")
}

# Base32 decoding
#
# @param x A base32 string (case and spaces do not matter, `=` padding is
# ignored).
#
# @returns A `raw` vector or `NULL` if the string has invalid characters.
# @noRd
aa_base32_decode <- function(x) {
  if (!aa_is_string(x)) {
    return(NULL)
  }

  x <- toupper(gsub("[[:space:]=-]", "", x))

  if (!nzchar(x) || grepl("[^A-Z2-7]", x)) {
    return(NULL)
  }

  idx <- match(strsplit(x, "")[[1]], strsplit(aa_base32_alphabet, "")[[1]]) - 1L
  bits <- unlist(lapply(idx, function(i) as.integer(rev(intToBits(i)[1:5]))))
  n <- length(bits) %/% 8
  if (n == 0) {
    return(NULL)
  }

  bytes <- matrix(bits[seq_len(n * 8)], ncol = 8, byrow = TRUE) %*%
    c(128L, 64L, 32L, 16L, 8L, 4L, 2L, 1L)

  as.raw(as.vector(bytes))
}

#' Random secret for an authenticator app
#'
#' @returns A base32 string of 32 characters (160 bits), the way it is entered
#' into the app
#'   manually.
#' @export
#'
#' @examples
#' nchar(aa_totp_secret())
aa_totp_secret <- function() {
  aa_base32_encode(openssl::rand_bytes(20))
}

#' One-time TOTP code for a point in time
#'
#' The RFC 6238 algorithm (HMAC-SHA1, 30-second step). Needed in tests and for
#' comparing with
#' an authenticator app.
#'
#' @param secret Secret in base32.
#' @param time Point in time (now by default).
#' @param digits Number of digits in the code.
#' @param period Step length, seconds.
#'
#' @returns A string of `digits` digits or `NA` if the secret is invalid.
#' @export
#'
#' @examples
#' aa_totp_code("JBSWY3DPEHPK3PXP")
aa_totp_code <- function(secret, time = Sys.time(), digits = 6, period = 30) {
  key <- aa_base32_decode(secret)

  if (is.null(key)) {
    return(NA_character_)
  }

  aa_hotp(key, floor(as.numeric(time) / period), digits)
}

# HOTP code by counter (RFC 4226)
#
# @param key Key (`raw`).
# @param counter Counter (integer, time step).
# @param digits Number of digits.
#
# @returns A string of `digits` digits.
# @noRd
aa_hotp <- function(key, counter, digits = 6) {
  # an 8-byte counter, most significant byte first: the upper 4 bytes are zero until the year 2106
  msg <- c(
    raw(4),
    writeBin(as.integer(counter), raw(), size = 4, endian = "big")
  )
  hash <- as.integer(as.raw(openssl::sha1(msg, key = key)))
  offset <- bitwAnd(hash[20], 15L) + 1L
  bin <- bitwOr(
    bitwOr(
      bitwShiftL(bitwAnd(hash[offset], 127L), 24L),
      bitwShiftL(hash[offset + 1L], 16L)
    ),
    bitwOr(bitwShiftL(hash[offset + 2L], 8L), hash[offset + 3L])
  )

  formatC(bin %% (10^digits), width = digits, format = "d", flag = "0")
}

#' otpauth link for an authenticator app
#'
#' The QR code is built from this link, and apps also understand it on manual
#' entry.
#'
#' @param secret Secret in base32.
#' @param login User login.
#' @param issuer Service name the app will show.
#'
#' @returns A string like `otpauth://totp/...`.
#' @export
#'
#' @examples
#' aa_totp_uri("JBSWY3DPEHPK3PXP", "ivan", "Reports portal")
aa_totp_uri <- function(secret, login, issuer = "appauth") {
  enc <- function(x) utils::URLencode(x, reserved = TRUE)

  sprintf(
    "otpauth://totp/%s:%s?secret=%s&issuer=%s&algorithm=SHA1&digits=6&period=30",
    enc(issuer),
    enc(login),
    secret,
    enc(issuer)
  )
}

# Secret encryption key from the settings
#
# @param settings Settings, the result of [aa_settings()].
#
# @returns A key (`raw`, 32 bytes).
# @noRd
aa_totp_key <- function(settings) {
  if (!aa_is_string(settings$totp_key)) {
    rlang::abort(
      "Two-factor authentication needs the encryption key `totp_key` in the settings.",
      class = "appauth_error_settings"
    )
  }

  sodium::hash(charToRaw(settings$totp_key), size = 32)
}

# Encrypt a secret for storing in the database
#
# @param secret Base32 secret.
# @param settings Settings, the result of [aa_settings()].
#
# @returns A hex string: a nonce (24 bytes) and the ciphertext.
# @noRd
aa_totp_seal <- function(secret, settings) {
  nonce <- sodium::random(24)
  cipher <- sodium::data_encrypt(
    charToRaw(secret),
    aa_totp_key(settings),
    nonce
  )

  sodium::bin2hex(c(nonce, cipher))
}

# Decrypt a secret from the database
#
# @param sealed A string from `aa_totp_seal()`.
# @param settings Settings, the result of [aa_settings()].
#
# @returns A base32 secret or `NA` if decryption failed (another key,
#   corrupted data).
# @noRd
aa_totp_unseal <- function(sealed, settings) {
  if (!aa_is_string(sealed)) {
    return(NA_character_)
  }

  tryCatch(
    {
      raw <- sodium::hex2bin(sealed)
      plain <- sodium::data_decrypt(
        raw[-(1:24)],
        aa_totp_key(settings),
        raw[1:24]
      )
      rawToChar(plain)
    },
    error = function(e) NA_character_
  )
}

# User 2FA data from the database
#
# @param conn Database connection.
# @param login Login.
#
# @returns A one-row table (`totp_secret`, `totp_enabled`,
#   `totp_last_step`) or `NULL` if the user does not exist or the schema is not
#   upgraded.
# @noRd
aa_totp_row <- function(conn, login) {
  if (!aa_is_string(login)) {
    return(NULL)
  }

  row <- tryCatch(
    aa_query(
      conn,
      "SELECT totp_secret, totp_enabled, totp_last_step FROM users WHERE login = ?",
      params = list(login)
    ),
    error = function(e) NULL
  )

  if (is.null(row) || nrow(row) != 1) NULL else row
}

#' Whether two-factor authentication is enabled for a user
#'
#' @inheritParams aa_get_user
#'
#' @returns `TRUE` or `FALSE` (`FALSE` both for a nonexistent user and
#'   if the schema is not upgraded to version 8).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_totp_enabled(conn, "boss")
#'   DBI::dbDisconnect(conn)
#' }
aa_totp_enabled <- function(conn, login) {
  aa_check_conn(conn)

  row <- aa_totp_row(conn, login)

  !is.null(row) && isTRUE(as.logical(row$totp_enabled[1]))
}

.aa_totp_role_required <- function(role, settings) {
  isTRUE(settings$totp_enabled) &&
    aa_is_string(role) &&
    role %in% settings$totp_required_roles
}

.aa_totp_enrollment_needed <- function(conn, login, role, settings) {
  .aa_totp_role_required(role, settings) &&
    !isTRUE(aa_totp_enabled(conn, login))
}

#' Start setting up two-factor authentication
#'
#' Creates a new secret and stores it in the database in encrypted form, but
#' **does not
#' enable** 2FA: it is enabled only after [aa_totp_enable()] with a correct code
#' from the app. A repeated call replaces the pending secret. If 2FA is already
#' enabled, an error of class `appauth_error_user` is raised.
#'
#' @inheritParams aa_get_user
#' @param settings Settings, the result of [aa_settings()] with `totp_enabled =
#' TRUE`.
#'
#' @returns A list: `secret` (base32, for manual entry) and `uri` (an
#'   `otpauth://` link, the QR code is built from it).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   settings <- aa_settings(totp_enabled = TRUE, totp_key =
#'   "a-long-random-key-for-the-example")
#'   setup <- aa_totp_setup(conn, "boss", settings)
#'   setup$uri
#'   DBI::dbDisconnect(conn)
#' }
aa_totp_setup <- function(conn, login, settings = aa_settings()) {
  aa_check_conn(conn)

  row <- aa_totp_row(conn, login)

  if (is.null(row)) {
    aa_abort_user(settings, "user_not_found")
  }

  if (isTRUE(as.logical(row$totp_enabled[1]))) {
    aa_abort_user(settings, "totp_already_enabled")
  }

  secret <- aa_totp_secret()

  aa_execute(
    conn,
    "UPDATE users SET totp_secret = ?, totp_enabled = 0, totp_last_step = 0 WHERE login = ?",
    params = list(aa_totp_seal(secret, settings), login)
  )

  list(secret = secret, uri = aa_totp_uri(secret, login, settings$totp_issuer))
}

# Check a TOTP code and remember the step
#
# @param secret Base32 secret.
# @param code Entered code.
# @param last_step Last accepted time step.
# @param settings Settings, the result of [aa_settings()].
# @param time Point in time.
#
# @returns The accepted time step or `NA` if the code is wrong or already used.
# @noRd
aa_totp_match_step <- function(
  secret,
  code,
  last_step,
  settings,
  time = Sys.time()
) {
  code <- gsub("[[:space:]]", "", as.character(code))

  if (!grepl("^[0-9]{6}$", code)) {
    return(NA_real_)
  }

  now_step <- floor(as.numeric(time) / 30)
  key <- aa_base32_decode(secret)

  if (is.null(key)) {
    return(NA_real_)
  }

  steps <- seq(now_step - settings$totp_window, now_step + settings$totp_window)
  # comparison without early exit: the check time does not depend on which step matched
  matched <- vapply(
    steps,
    function(s) identical(aa_hotp(key, s, 6), code),
    logical(1)
  )
  last_step <- if (is.na(last_step)) 0 else as.numeric(last_step)
  steps <- steps[matched & steps > last_step]

  if (length(steps) == 0) NA_real_ else max(steps)
}

# Recovery code hash
#
# @param code Code in any case, with spaces or hyphens.
#
# @returns A sha256 string or `NA` if the format does not fit.
# @noRd
aa_recovery_hash <- function(code) {
  code <- tolower(gsub("[[:space:]-]", "", as.character(code)))

  if (!grepl("^[0-9a-f]{10}$", code)) {
    return(NA_character_)
  }

  aa_token_hash(code)
}

# Create a set of recovery codes
#
# @param conn Database connection.
# @param login Login.
# @param n How many codes.
#
# @returns A vector of codes like `abcde-12345` (shown once).
# @noRd
aa_new_recovery_codes <- function(conn, login, n = 10) {
  raw_codes <- vapply(
    seq_len(n),
    function(i) {
      paste(as.character(openssl::rand_bytes(5)), collapse = "")
    },
    character(1)
  )

  aa_execute(
    conn,
    "DELETE FROM totp_recovery WHERE user_login = ?",
    params = list(login)
  )

  for (code in raw_codes) {
    aa_execute(
      conn,
      "INSERT INTO totp_recovery (user_login, code_hash, created_at) VALUES (?, ?, ?)",
      params = list(login, aa_token_hash(code), aa_utc())
    )
  }

  paste0(substr(raw_codes, 1, 5), "-", substr(raw_codes, 6, 10))
}

#' Enable two-factor authentication
#'
#' Checks the app code against the pending secret ([aa_totp_setup()]) and
#' enables 2FA. Creates 10 recovery codes: **they are returned once**, only
#' hashes
#' stay in the database. A wrong code raises an error of class
#' `appauth_error_user`
#' (`reason = "totp_wrong"`).
#'
#' @inheritParams aa_totp_setup
#' @param code Code from the authenticator app.
#'
#' @returns A vector of recovery codes (invisibly).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   settings <- aa_settings(totp_enabled = TRUE, totp_key =
#'   "a-long-random-key-for-the-example")
#'   setup <- aa_totp_setup(conn, "boss", settings)
#'   codes <- aa_totp_enable(conn, "boss", aa_totp_code(setup$secret), settings)
#'   length(codes)
#'   DBI::dbDisconnect(conn)
#' }
aa_totp_enable <- function(conn, login, code, settings = aa_settings()) {
  aa_check_conn(conn)

  row <- aa_totp_row(conn, login)

  if (is.null(row)) {
    aa_abort_user(settings, "user_not_found")
  }

  if (isTRUE(as.logical(row$totp_enabled[1]))) {
    aa_abort_user(settings, "totp_already_enabled")
  }

  secret <- aa_totp_unseal(row$totp_secret[1], settings)
  step <- if (is.na(secret)) {
    NA_real_
  } else {
    aa_totp_match_step(secret, code, 0, settings)
  }

  if (is.na(step)) {
    aa_abort_user(settings, "totp_wrong")
  }

  DBI::dbWithTransaction(conn, {
    aa_execute(
      conn,
      "UPDATE users SET totp_enabled = 1, totp_last_step = ? WHERE login = ?",
      params = list(step, login)
    )
    codes <- aa_new_recovery_codes(conn, login)
  })

  invisible(codes)
}

#' Disable two-factor authentication
#'
#' Erases the user's secret and recovery codes. The function **checks nothing**:
#' the [aa_totp_server()] module requires a password and a code before calling
#' it, and reset
#' by an administrator ([aa_users_server()]) is allowed only to an
#' administrator.
#'
#' @inheritParams aa_get_user
#'
#' @returns `TRUE` if something was reset for the user, otherwise `FALSE`
#'   (invisibly).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_totp_disable(conn, "boss")
#'   DBI::dbDisconnect(conn)
#' }
aa_totp_disable <- function(conn, login) {
  aa_check_conn(conn)

  if (!aa_is_string(login)) {
    return(invisible(FALSE))
  }

  n <- aa_execute(
    conn,
    "UPDATE users SET totp_secret = NULL, totp_enabled = 0, totp_last_step = 0
     WHERE login = ? AND (totp_secret IS NOT NULL OR totp_enabled = 1)",
    params = list(login)
  )
  aa_execute(
    conn,
    "DELETE FROM totp_recovery WHERE user_login = ?",
    params = list(login)
  )

  invisible(n > 0)
}

#' How many recovery codes are left
#'
#' @inheritParams aa_get_user
#'
#' @returns An integer: the number of unused recovery codes.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_recovery_codes_left(conn, "boss")
#'   DBI::dbDisconnect(conn)
#' }
aa_recovery_codes_left <- function(conn, login) {
  aa_check_conn(conn)

  if (!aa_is_string(login)) {
    return(0L)
  }

  as.integer(tryCatch(
    aa_query(
      conn,
      "SELECT COUNT(*) AS n FROM totp_recovery WHERE user_login = ? AND used = 0",
      params = list(login)
    )$n,
    error = function(e) 0L
  ))
}

#' Verify the second factor at sign-in
#'
#' Accepts a code from the app (6 digits) or a recovery code. An app code
#' is accepted once: a repeat of the same code (time step) is rejected. A
#' recovery
#' code is one-time. The function **does not limit the number of attempts
#' itself**: call
#' [aa_login_gate()] before it and [aa_record_attempt()] after a wrong code, as
#' the sign-in module does.
#'
#' @inheritParams aa_totp_setup
#' @param code Entered code.
#'
#' @returns A list: `ok` (`TRUE` or `FALSE`) and `method` (`"totp"`,
#' `"recovery"`
#'   or `NA`).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   settings <- aa_settings(totp_enabled = TRUE, totp_key =
#'   "a-long-random-key-for-the-example")
#'   aa_verify_second_factor(conn, "boss", "123456", settings)$ok
#'   DBI::dbDisconnect(conn)
#' }
aa_verify_second_factor <- function(
  conn,
  login,
  code,
  settings = aa_settings()
) {
  aa_check_conn(conn)

  failed <- list(ok = FALSE, method = NA_character_)
  row <- aa_totp_row(conn, login)

  if (
    is.null(row) ||
      !isTRUE(as.logical(row$totp_enabled[1])) ||
      !aa_is_string(code)
  ) {
    return(failed)
  }

  hash <- aa_recovery_hash(code)

  if (!is.na(hash)) {
    # a recovery code is claimed with an atomic query: of two simultaneous ones only one works
    used <- aa_execute(
      conn,
      "UPDATE totp_recovery SET used = 1 WHERE user_login = ? AND code_hash = ? AND used = 0",
      params = list(login, hash)
    )

    return(if (used == 1) list(ok = TRUE, method = "recovery") else failed)
  }

  secret <- aa_totp_unseal(row$totp_secret[1], settings)

  if (is.na(secret)) {
    return(failed)
  }

  step <- aa_totp_match_step(secret, code, row$totp_last_step[1], settings)

  if (is.na(step)) {
    return(failed)
  }

  # the step is remembered atomically: the same code in a second request will not pass
  claimed <- aa_execute(
    conn,
    "UPDATE users SET totp_last_step = ? WHERE login = ? AND totp_last_step < ?",
    params = list(step, login, step)
  )

  if (claimed == 1) list(ok = TRUE, method = "totp") else failed
}
