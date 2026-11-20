# Sign-in with Google (OpenID Connect, authorization code flow with PKCE).
#
# How it works and why it is safe:
#  - sign-in starts with a button: the package creates a one-time state, nonce and PKCE verifier and
#    stores them in the oauth_states table (state only as sha256, lifetime 10 minutes);
#  - state is additionally put into a short-lived browser cookie: on return from Google
#    the package compares the state from the address with the cookie, so someone else's link with their own code
#    cannot be slipped into the victim's browser (login CSRF);
#  - the code is exchanged for a token on the server side (client_secret never leaves the server);
#  - the id_token is verified completely: signature against Google keys (RS256 only), issuer,
#    audience, expiry, nonce, verified email and organization domain;
#  - the user is looked up by email among existing ones: new users are not
#    created automatically, the role is taken from the database, a blocked user does not get in;
#  - the package writes nothing to logs itself: the reason for a refusal goes to the on_event hook.

# Google addresses
#
# Wrapped in a function so that tests can substitute them.
#
# @returns A list with the addresses and the allowed token issuers.
# @noRd
aa_google_urls <- function() {
  list(
    auth = "https://accounts.google.com/o/oauth2/v2/auth",
    token = "https://oauth2.googleapis.com/token",
    jwks = "https://www.googleapis.com/oauth2/v3/certs",
    issuers = c("https://accounts.google.com", "accounts.google.com")
  )
}

# Base64url without padding (RFC 4648, section 5)
#
# @param raw A `raw` vector.
#
# @returns A string.
# @noRd
aa_b64url_encode <- function(raw) {
  chartr("+/", "-_", sub("=+$", "", as.character(openssl::base64_encode(raw))))
}

# Base64url decoding
#
# @param text A base64url string.
#
# @returns A `raw` vector.
# @noRd
aa_b64url_decode <- function(text) {
  b64 <- chartr("-_", "+/", text)
  pad <- (4 - nchar(b64) %% 4) %% 4

  openssl::base64_decode(paste0(b64, strrep("=", pad)))
}

# Coercing the `email_verified` value from the token to a logical
#
# Google returns a boolean, but the string `"true"` is accepted too.
#
# @param x Value from the token.
#
# @returns `TRUE` or `FALSE`.
# @noRd
aa_google_flag <- function(x) {
  isTRUE(x) || identical(tolower(as.character(x)), "true")
}

# Start sign-in with Google
#
# Creates a one-time `state`, `nonce` and PKCE verifier, stores them in the
# database and
# returns the address of the Google consent page.
#
# @param conn Database connection with the [aa_init_db()] schema.
# @param settings Settings, the result of [aa_settings()], with `google_enabled
# = TRUE`.
#
# @returns A list: `url` (where to send the browser) and `state` (it must be
# put into the
#   browser cookie to compare later).
# @noRd
aa_google_start <- function(conn, settings) {
  if (!isTRUE(settings$google_enabled)) {
    rlang::abort(
      "Sign-in with Google is disabled.",
      class = "appauth_error_settings"
    )
  }

  # protection against table flooding: a global limit of starts per minute
  recent <- aa_query(
    conn,
    "SELECT COUNT(*) AS n FROM oauth_states WHERE created_at > ?",
    params = list(aa_utc(-60))
  )$n

  if (recent >= 60) {
    rlang::abort(
      "Too many Google sign-in starts.",
      class = "appauth_error_throttled"
    )
  }

  state <- aa_b64url_encode(openssl::rand_bytes(32))
  nonce <- aa_b64url_encode(openssl::rand_bytes(16))
  verifier <- aa_b64url_encode(openssl::rand_bytes(32))
  challenge <- aa_b64url_encode(unclass(openssl::sha256(charToRaw(verifier))))

  aa_execute(
    conn,
    "INSERT INTO oauth_states (state_hash, nonce, code_verifier, created_at, expires_at)
     VALUES (?, ?, ?, ?, ?)",
    params = list(aa_token_hash(state), nonce, verifier, aa_utc(), aa_utc(600))
  )

  query <- list(
    client_id = settings$google_client_id,
    redirect_uri = settings$google_redirect_uri,
    response_type = "code",
    scope = "openid email",
    state = state,
    nonce = nonce,
    code_challenge = challenge,
    code_challenge_method = "S256",
    prompt = "select_account"
  )

  # a hint for Google about which domain to offer; the real domain check is done on the token
  if (length(settings$google_domains) == 1) {
    query$hd <- settings$google_domains
  }

  pairs <- paste0(
    names(query),
    "=",
    vapply(
      query,
      function(x) utils::URLencode(x, reserved = TRUE),
      character(1)
    )
  )

  list(
    url = paste0(aa_google_urls()$auth, "?", paste(pairs, collapse = "&")),
    state = state
  )
}

# Take the stored state (once)
#
# Consumes the record with an atomic query: the same `state` cannot be used a
# second time,
# an expired `state` is not accepted.
#
# @param conn Database connection.
# @param state The `state` value from the address.
#
# @returns A list with `nonce` and `code_verifier`, or `NULL`.
# @noRd
aa_google_take_state <- function(conn, state) {
  if (!aa_is_string(state) || nchar(state) > 200) {
    return(NULL)
  }

  hash <- aa_token_hash(state)

  claimed <- aa_execute(
    conn,
    "UPDATE oauth_states SET used = 1
     WHERE state_hash = ? AND used = 0 AND expires_at > ?",
    params = list(hash, aa_utc())
  )

  if (claimed != 1) {
    return(NULL)
  }

  row <- aa_query(
    conn,
    "SELECT nonce, code_verifier FROM oauth_states WHERE state_hash = ?",
    params = list(hash)
  )

  if (nrow(row) != 1) NULL else as.list(row)
}

# Exchange the code for an id_token
#
# @param settings Settings, the result of [aa_settings()].
# @param code Authorization code from the address.
# @param verifier PKCE verifier stored at the start of sign-in.
#
# @returns An `id_token` string or `NULL`.
# @noRd
aa_google_exchange_code <- function(settings, code, verifier) {
  req <- httr2::request(aa_google_urls()$token)
  req <- httr2::req_body_form(
    req,
    code = code,
    client_id = settings$google_client_id,
    client_secret = settings$google_client_secret,
    redirect_uri = settings$google_redirect_uri,
    grant_type = "authorization_code",
    code_verifier = verifier
  )
  req <- httr2::req_timeout(req, 15)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)

  resp <- httr2::req_perform(req)

  if (httr2::resp_status(resp) != 200) {
    body <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
    message(
      "appauth: Google rejected the code exchange (HTTP ",
      httr2::resp_status(resp),
      "): ",
      paste(c(body$error, body$error_description), collapse = ": ")
    )
    return(NULL)
  }

  token <- httr2::resp_body_json(resp)$id_token

  if (aa_is_string(token)) token else NULL
}

# Load Google public keys
#
# @returns A list of JWK keys.
# @noRd
aa_google_fetch_jwks <- function() {
  req <- httr2::req_timeout(httr2::request(aa_google_urls()$jwks), 15)

  httr2::resp_body_json(httr2::req_perform(req))$keys
}

aa_google_jwks_cache <- new.env(parent = emptyenv())

# Google public keys cached for an hour
#
# @param refresh Force a reload (a key with an unknown `kid`).
#
# @returns A list of JWK keys.
# @noRd
aa_google_jwks <- function(refresh = FALSE) {
  now <- as.numeric(Sys.time())

  if (
    !refresh &&
      !is.null(aa_google_jwks_cache$keys) &&
      now - aa_google_jwks_cache$at < 3600
  ) {
    return(aa_google_jwks_cache$keys)
  }

  keys <- aa_google_fetch_jwks()
  aa_google_jwks_cache$keys <- keys
  aa_google_jwks_cache$at <- now

  keys
}

# Public key for a token by `kid`
#
# @param kid Key id from the token header.
#
# @returns A key (`openssl`) or `NULL`.
# @noRd
aa_google_public_key <- function(kid) {
  for (refresh in c(FALSE, TRUE)) {
    keys <- aa_google_jwks(refresh = refresh)

    for (key in keys) {
      if (identical(key[["kid"]], kid) && identical(key[["kty"]], "RSA")) {
        return(jose::read_jwk(jsonlite::toJSON(key, auto_unbox = TRUE)))
      }
    }
  }

  NULL
}

# Verify the id_token
#
# @param id_token Token string.
# @param settings Settings, the result of [aa_settings()].
# @param nonce Expected `nonce`.
# @param now Current time (for tests).
#
# @returns A list: `ok`, `reason` (`bad_token`, `bad_nonce`,
# `email_unverified`,
#   `domain`) and `email` (the normalized address if known).
# @noRd
aa_google_verify_id_token <- function(
  id_token,
  settings,
  nonce,
  now = Sys.time()
) {
  fail <- function(reason, email = NA_character_) {
    list(ok = FALSE, reason = reason, email = email)
  }

  parts <- strsplit(id_token, ".", fixed = TRUE)[[1]]

  if (length(parts) != 3 || !all(nzchar(parts))) {
    return(fail("bad_token"))
  }

  header <- tryCatch(
    jsonlite::fromJSON(
      rawToChar(aa_b64url_decode(parts[1])),
      simplifyVector = FALSE
    ),
    error = function(e) NULL
  )

  # RS256 only: other algorithms (including none) are not accepted
  if (
    !is.list(header) ||
      !identical(header[["alg"]], "RS256") ||
      !aa_is_string(header[["kid"]])
  ) {
    return(fail("bad_token"))
  }

  key <- aa_google_public_key(header[["kid"]])

  if (is.null(key)) {
    return(fail("bad_token"))
  }

  claims <- tryCatch(jose::jwt_decode_sig(id_token, key), error = function(e) {
    NULL
  })

  if (!is.list(claims)) {
    return(fail("bad_token"))
  }

  email <- aa_normalize_email(claims[["email"]])

  audience_ok <- aa_is_string(settings$google_client_id) &&
    settings$google_client_id %in% unlist(claims[["aud"]]) &&
    (length(unlist(claims[["aud"]])) == 1 ||
      identical(claims[["azp"]], settings$google_client_id))

  exp_ok <- is.numeric(claims[["exp"]]) &&
    length(claims[["exp"]]) == 1 &&
    claims[["exp"]] > as.numeric(now)

  if (
    !isTRUE(claims[["iss"]] %in% aa_google_urls()$issuers) ||
      !audience_ok ||
      !exp_ok
  ) {
    return(fail("bad_token", email))
  }

  if (
    !aa_is_string(claims[["nonce"]]) || !identical(claims[["nonce"]], nonce)
  ) {
    return(fail("bad_nonce", email))
  }

  if (!nzchar(email) || !aa_google_flag(claims[["email_verified"]])) {
    return(fail("email_unverified", email))
  }

  domains <- settings$google_domains

  if (length(domains) > 0) {
    # hd is the primary domain of the Workspace organization: for an employee with a secondary domain it
    # differs from the email domain, so both values are checked against the list separately
    hd <- tolower(as.character(claims[["hd"]] %||% ""))
    email_domain <- sub("^.*@", "", email)

    domain_ok <- nzchar(hd) && hd %in% domains && email_domain %in% domains

    if (!domain_ok) {
      return(fail("domain", email))
    }
  }

  list(ok = TRUE, reason = "ok", email = email)
}

# Complete sign-in with Google
#
# Takes `code` and `state` from the return address, verifies everything and
# finds
# the user by email. Comparing `state` with the browser cookie is done in the
# [aa_auth_server()] module, before this function is called.
#
# @param conn Database connection.
# @param settings Settings, the result of [aa_settings()].
# @param code,state Parameters from the return address.
#
# @returns A list: `ok`, `reason`, `email`, `login`, `role` and `must_change`
#   (the last three on success). Refusal reasons: `disabled`, `bad_state`,
#   `bad_code`, `exchange_failed`,
#   `bad_token`, `bad_nonce`, `email_unverified`, `domain`, `no_user`,
#   `blocked`.
# @noRd
aa_google_complete <- function(conn, settings, code, state) {
  fail <- function(reason, email = NA_character_) {
    list(
      ok = FALSE,
      reason = reason,
      email = email,
      login = NA_character_,
      role = NA_character_,
      must_change = FALSE
    )
  }

  if (!isTRUE(settings$google_enabled)) {
    return(fail("disabled"))
  }

  saved <- aa_google_take_state(conn, state)

  if (is.null(saved)) {
    return(fail("bad_state"))
  }

  if (!aa_is_string(code) || nchar(code) > 2048) {
    return(fail("bad_code"))
  }

  id_token <- tryCatch(
    aa_google_exchange_code(settings, code, saved$code_verifier),
    error = function(e) {
      message(
        "appauth: could not exchange the Google code for a token: ",
        conditionMessage(e)
      )
      NULL
    }
  )

  if (!aa_is_string(id_token)) {
    return(fail("exchange_failed"))
  }

  verified <- tryCatch(
    aa_google_verify_id_token(id_token, settings, saved$nonce),
    error = function(e) {
      message(
        "appauth: could not verify the Google token: ",
        conditionMessage(e)
      )
      list(ok = FALSE, reason = "bad_token", email = NA_character_)
    }
  )

  if (!isTRUE(verified$ok)) {
    return(fail(verified$reason, verified$email))
  }

  user <- aa_query(
    conn,
    "SELECT login, role, blocked, must_change FROM users WHERE email = ?",
    params = list(verified$email)
  )

  if (nrow(user) != 1) {
    return(fail("no_user", verified$email))
  }

  if (isTRUE(user$blocked[1] == 1)) {
    return(fail("blocked", verified$email))
  }

  list(
    ok = TRUE,
    reason = "ok",
    email = verified$email,
    login = user$login[1],
    role = user$role[1],
    must_change = isTRUE(user$must_change[1] == 1)
  )
}

# Parse an address into scheme, host and port
#
# @param url Address (`https://host[:port][/path]`).
#
# @returns A list with `scheme`, `host`, `port` (strings, the default port is
# filled in)
#   or `NULL` if the address cannot be parsed.
# @noRd
aa_url_origin <- function(url) {
  if (!aa_is_string(url)) {
    return(NULL)
  }

  m <- regmatches(
    url,
    regexec("^(https?)://([^/:?#]+)(?::([0-9]+))?", url, perl = TRUE)
  )[[1]]

  if (length(m) == 0) {
    return(NULL)
  }

  scheme <- tolower(m[2])
  port <- if (nzchar(m[4])) {
    m[4]
  } else if (identical(scheme, "https")) {
    "443"
  } else {
    "80"
  }

  list(scheme = scheme, host = tolower(m[3]), port = port)
}

# Site address (scheme, host, port) as a string, without the default port
#
# @param origin The result of `aa_url_origin()`.
#
# @returns A string like `https://app.example.com`.
# @noRd
aa_origin_string <- function(origin) {
  default <- identical(
    origin$port,
    if (identical(origin$scheme, "https")) "443" else "80"
  )

  paste0(
    origin$scheme,
    "://",
    origin$host,
    if (!default) paste0(":", origin$port)
  )
}

# Which address the page was opened from
#
# Wrapped in a function so that tests can substitute the address: the mock
# Shiny session has none.
#
# @param session Module session.
#
# @returns A result like `aa_url_origin()` or `NULL` if the browser has not
# reported the address yet.
# @noRd
aa_page_origin <- function(session) {
  data <- shiny::isolate(session$clientData)
  protocol <- shiny::isolate(data$url_protocol)
  hostname <- shiny::isolate(data$url_hostname)
  port <- shiny::isolate(data$url_port)

  if (!aa_is_string(protocol) || !aa_is_string(hostname)) {
    return(NULL)
  }

  aa_url_origin(paste0(
    protocol,
    "//",
    hostname,
    if (aa_is_string(as.character(port))) paste0(":", port)
  ))
}

# Whether the page is opened at the Google return address
#
# The sign-in `state` is stored in a cookie, and a cookie belongs to the site
# address (by IP and by domain
# they are different). Google returns the user to `google_redirect_uri`, so
# sign-in
# must start at the same address. If the page address is unknown, we assume it
# matches: an extra redirect is worse than an attempt to start sign-in in
# place.
#
# @param session Module session.
# @param redirect_uri Return address from the settings.
#
# @returns `TRUE` or `FALSE`.
# @noRd
aa_page_matches <- function(session, redirect_uri) {
  page <- aa_page_origin(session)
  target <- aa_url_origin(redirect_uri)

  if (is.null(page) || is.null(target)) {
    return(TRUE)
  }

  identical(page, target)
}

# Address for jumping to the return address with sign-in auto-start
#
# @param settings Settings, the result of [aa_settings()].
#
# @returns The return address with the `google=1` parameter.
# @noRd
aa_google_hop_url <- function(settings) {
  uri <- settings$google_redirect_uri

  paste0(uri, if (grepl("?", uri, fixed = TRUE)) "&" else "?", "google=1")
}

# Send the browser a command to go to an address
#
# The browser performs the redirect only to Google or to the site address
# `origin` that
# the server passes. Wrapped in a function so that tests can intercept the
# redirect.
#
# @param session Module session.
# @param url Redirect address.
# @param origin Site address to which the redirect is allowed (besides Google).
#
# @returns Invisibly `NULL`.
# @noRd
aa_redirect <- function(session, url, origin) {
  session$sendCustomMessage(
    "appauth_redirect",
    list(url = url, origin = origin)
  )

  invisible(NULL)
}

# Text key for a Google sign-in refusal reason
#
# @param reason Reason from `aa_google_complete()`.
#
# @returns A key in the text dictionary.
# @noRd
aa_google_text_key <- function(reason) {
  switch(
    reason,
    blocked = "blocked_user",
    no_user = "google_no_user",
    domain = "google_domain",
    cancelled = "google_cancelled",
    "google_failed"
  )
}
