# Self-registration: pending accounts, email confirmation and account creation.
#
# Rules these functions uphold:
#  - the password is hashed before it is stored in a pending registration, a
#    plain-text password never reaches the database;
#  - the confirmation token is one-time and is stored only as sha256;
#  - login, email and domain rules are checked again when the link is used, so a
#    pending account cannot take over a login or address created meanwhile;
#  - a registration request has the same on-screen answer whether or not the
#    login and address were available, only the event reports the reason.

# Link in the confirmation email
#
# @param settings Settings, the result of [aa_settings()].
# @param token Confirmation token.
#
# @returns A string with the link.
# @noRd
aa_registration_link <- function(settings, token) {
  base <- sub("/+$", "", settings$reset_base_url)
  paste0(
    base,
    if (grepl("?", base, fixed = TRUE)) "&" else "/?",
    "register=",
    token
  )
}

# Problem with the email domain of a registration
#
# @param email Normalized email.
# @param settings Settings, the result of [aa_settings()].
#
# @returns NULL or a list with `reason` and `args`.
# @noRd
aa_registration_domain_problem <- function(email, settings) {
  domains <- settings$registration_domains

  if (!length(domains)) {
    return(NULL)
  }

  domain <- sub("^.*@", "", email)
  if (tolower(domain) %in% domains) NULL else list(
    reason = "registration_domain",
    args = list(paste(domains, collapse = ", "))
  )
}

# Problem with a pending registration (login or address already requested)
#
# @inheritParams aa_register_user
#
# @returns NULL or a list with `reason` and `args`.
# @noRd
aa_registration_pending_problem <- function(conn, login, email) {
  pending <- aa_query(
    conn,
    "SELECT login, email FROM registrations
     WHERE used = 0 AND expires_at > ?",
    params = list(aa_utc())
  )

  if (any(tolower(pending$login) == tolower(login))) {
    return(list(reason = "user_exists", args = list()))
  }

  if (email %in% pending$email) {
    return(list(reason = "email_exists", args = list()))
  }

  NULL
}

# Pending registration for a confirmation token
#
# @param conn Database connection.
# @param token Token from the address.
#
# @returns A one-row data frame or NULL.
# @noRd
aa_registration_row <- function(conn, token) {
  if (!aa_is_string(token) || nchar(token) > 512) {
    return(NULL)
  }

  row <- aa_query(
    conn,
    "SELECT login, email, password, role, token_hash FROM registrations
     WHERE token_hash = ? AND used = 0 AND expires_at > ?",
    params = list(aa_token_hash(token), aa_utc())
  )

  if (nrow(row) != 1) NULL else row[1, , drop = FALSE]
}

#' Request self-registration
#'
#' Checks the login, password, email and the domain and rate limits from the
#' settings, and stores a pending registration with the password hash. With
#' `registration_verify_email = TRUE` a one-time confirmation link is sent with
#' `settings$send_reset(email, link, login)`; with `FALSE` the account is
#' created immediately. Only the token hash is stored in the database.
#'
#' The result is meant for the journal and for choosing a generic on-screen
#' answer: the reason `user_exists` or `email_exists` must not be shown to a
#' visitor, because that would reveal which accounts exist.
#'
#' @param conn Connection with the [aa_init_db()] schema.
#' @param login Desired login.
#' @param password Desired password (only the hash is stored).
#' @param email Email address of the visitor.
#' @param settings Settings, the result of [aa_settings()] with
#'   `registration_enabled = TRUE`.
#'
#' @returns A list (invisibly): `sent`, `reason` and `login`. Reasons: `created`,
#'   `sent`, `disabled`, `user_exists`, `email_exists`, `email_invalid`,
#'   `registration_domain`, `registration_throttled`, `send_failed` or a login or
#'   password validation reason.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'
#'   settings <- aa_settings(
#'     registration_enabled = TRUE,
#'     registration_verify_email = FALSE,
#'     registration_role = "viewer"
#'   )
#'   aa_register_user(conn, "worker", "worker-password", "worker@example.com",
#'                    settings)$reason
#'   aa_list_users(conn)
#'   DBI::dbDisconnect(conn)
#' }
aa_register_user <- function(
  conn,
  login,
  password,
  email,
  settings = aa_settings()
) {
  aa_check_conn(conn)

  result <- function(reason, login = NA_character_) {
    invisible(list(
      sent = reason %in% c("created", "sent"),
      reason = reason,
      login = login
    ))
  }

  if (!isTRUE(settings$registration_enabled)) {
    return(result("disabled"))
  }

  problem <- aa_new_user_problem(
    conn,
    login,
    password,
    settings$registration_role,
    settings
  )
  if (!is.null(problem)) {
    return(result(problem$reason, if (aa_is_string(login)) login else NA_character_))
  }

  email <- aa_normalize_email(email)
  problem <- aa_email_problem(conn, email)
  if (!is.null(problem)) {
    return(result(problem$reason, login))
  }

  problem <- aa_registration_domain_problem(email, settings)
  if (!is.null(problem)) {
    return(result(problem$reason, login))
  }

  token <- NULL
  failure <- NULL
  tryCatch(
    aa_write_section(conn, function() {
      problem <- aa_registration_pending_problem(conn, login, email)
      if (!is.null(problem)) {
        rlang::abort(
          problem$reason,
          class = "appauth_registration_problem",
          reason = problem$reason
        )
      }

      recent <- aa_query(
        conn,
        "SELECT COUNT(*) AS n FROM registrations WHERE created_at > ?",
        params = list(aa_utc(-3600))
      )$n

      if (recent >= settings$registration_max_per_hour) {
        rlang::abort(
          "registration_throttled",
          class = "appauth_registration_problem",
          reason = "registration_throttled"
        )
      }

      token <<- paste(as.character(openssl::rand_bytes(32)), collapse = "")
      ttl <- as.integer(round(settings$reset_ttl_minutes * 60))

      aa_execute(
        conn,
        paste0(
          "INSERT INTO registrations
             (login, email, password, role, token_hash, created_at, expires_at)
           VALUES (?, ?, ?, ?, ?, ?, ?)"
        ),
        params = list(
          login,
          email,
          aa_hash_password(password),
          settings$registration_role,
          aa_token_hash(token),
          aa_utc(),
          aa_utc(ttl)
        )
      )
    }),
    appauth_registration_problem = function(e) {
      failure <<- e$reason
    }
  )

  if (!is.null(failure)) {
    return(result(failure, login))
  }

  if (!isTRUE(settings$registration_verify_email)) {
    confirmed <- tryCatch(
      aa_confirm_registration(conn, token, settings),
      error = function(e) NULL
    )
    return(if (is.null(confirmed)) {
      result("user_exists", login)
    } else {
      result("created", login)
    })
  }

  sent <- tryCatch(
    {
      settings$send_reset(
        email = email,
        link = aa_registration_link(settings, token),
        login = login
      )
      TRUE
    },
    error = function(e) {
      message(
        "appauth: could not send the registration email: ",
        conditionMessage(e)
      )
      FALSE
    }
  )

  if (!sent) {
    aa_execute(
      conn,
      "UPDATE registrations SET used = 1 WHERE token_hash = ?",
      params = list(aa_token_hash(token))
    )
    return(result("send_failed", login))
  }

  result("sent", login)
}

#' User who owns a registration link
#'
#' Checks the confirmation token without changing anything: the token must be
#' unused, not expired, and the login and address must still be available. The
#' new password form is shown only for a working link.
#'
#' @param conn Connection with the [aa_init_db()] schema.
#' @param token Token from the `?register=<token>` link.
#'
#' @returns The login or `NULL`.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_registration_token_login(conn, "not-a-token")
#'   DBI::dbDisconnect(conn)
#' }
aa_registration_token_login <- function(conn, token) {
  aa_check_conn(conn)

  row <- aa_registration_row(conn, token)
  if (is.null(row)) {
    return(NULL)
  }

  user <- aa_query(
    conn,
    "SELECT login FROM users WHERE login = ? OR email = ?",
    params = list(row$login, row$email)
  )

  if (nrow(user) > 0) NULL else row$login
}

#' Create an account from a registration link
#'
#' Checks the token again, consumes it atomically and creates the user with the
#' hashed password stored in the pending registration. A weak password has
#' already been rejected when the registration was requested; a conflict with
#' an account created meanwhile leaves the token unused and raises an error of
#' class `appauth_error_user`.
#'
#' @param conn Connection with the [aa_init_db()] schema.
#' @param token Token from the address.
#' @param settings Settings, the result of [aa_settings()].
#'
#' @returns The login of the created user (invisibly).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   settings <- aa_settings(
#'     registration_enabled = TRUE,
#'     registration_verify_email = FALSE
#'   )
#'   tryCatch(
#'     aa_confirm_registration(conn, "not-a-token", settings),
#'     appauth_error_user = function(e) conditionMessage(e)
#'   )
#'   DBI::dbDisconnect(conn)
#' }
aa_confirm_registration <- function(conn, token, settings = aa_settings()) {
  aa_check_conn(conn)
  call <- sys.call()

  aa_write_section(conn, function() {
    row <- aa_registration_row(conn, token)
    if (is.null(row)) {
      aa_abort_user(settings, "registration_link_invalid", call = call)
    }

    problem <- aa_new_user_problem(
      conn,
      row$login,
      NULL,
      row$role,
      settings,
      check_password = FALSE
    )
    if (!is.null(problem)) {
      aa_abort_problem(settings, problem, call = call)
    }

    problem <- aa_email_problem(conn, row$email)
    if (!is.null(problem)) {
      aa_abort_problem(settings, problem, call = call)
    }

    claimed <- aa_execute(
      conn,
      "UPDATE registrations SET used = 1
       WHERE token_hash = ? AND used = 0 AND expires_at > ?",
      params = list(aa_token_hash(token), aa_utc())
    )

    if (claimed != 1) {
      aa_abort_user(settings, "registration_link_invalid", call = call)
    }

    aa_insert_user(
      conn,
      row$login,
      row$password,
      row$role,
      settings,
      email = row$email,
      call = call
    )

    invisible(row$login)
  })
}

# Consume an unused registration for the same login or address
#
# Called when an account with the same email is created by an administrator or
# through Google sign-up, so a stale confirmation link cannot create a second
# account with the same address.
#
# @param conn Database connection.
# @param login Login of the created user.
# @param email Email of the created user.
#
# @returns The number of consumed registrations (invisibly).
# @noRd
aa_invalidate_registrations <- function(conn, login, email = NULL) {
  email <- aa_normalize_email(email)

  if (!nzchar(email)) {
    return(invisible(0L))
  }

  invisible(aa_execute(
    conn,
    "UPDATE registrations SET used = 1
     WHERE used = 0 AND (email = ? OR login = ?)",
    params = list(email, login)
  ))
}
