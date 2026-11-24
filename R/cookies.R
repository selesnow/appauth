.aa_cookie_endpoints <- new.env(parent = emptyenv())

aa_cookie_url_encode <- function(x) {
  utils::URLencode(x, reserved = TRUE)
}

aa_request_cookie <- function(session, name) {
  request <- suppressWarnings(tryCatch(session$request, error = function(e) NULL))
  raw <- request$HTTP_COOKIE

  if (!aa_is_string(raw) || !nzchar(raw)) {
    return(NULL)
  }

  parts <- strsplit(raw, ";", fixed = TRUE)[[1]]

  for (part in parts) {
    pos <- regexpr("=", part, fixed = TRUE)
    if (pos < 1) {
      next
    }

    key <- trimws(substr(part, 1, pos - 1))
    if (identical(key, name)) {
      return(utils::URLdecode(substr(part, pos + 1, nchar(part))))
    }
  }

  NULL
}

aa_cookie_app_path <- function(session) {
  request <- suppressWarnings(tryCatch(session$request, error = function(e) NULL))
  script <- if (is.null(request)) "" else request$SCRIPT_NAME %||% ""

  if (!aa_is_string(script) || !nzchar(script)) {
    return("/")
  }
  if (!startsWith(script, "/")) {
    script <- paste0("/", script)
  }
  if (!endsWith(script, "/")) {
    script <- paste0(script, "/")
  }

  script
}

aa_cookie_request_path <- function(session) {
  paste0(aa_cookie_app_path(session), "__appauth/cookie")
}

aa_cookie_key <- function(conn, settings) {
  if (aa_is_string(settings$cookie_key)) {
    return(sodium::hash(charToRaw(settings$cookie_key), size = 32L))
  }

  if (!DBI::dbExistsTable(conn, "appauth_cookie_keys")) {
    rlang::abort(
      "appauth: run `aa_init_db()` before issuing HttpOnly cookie tickets.",
      class = "appauth_error_schema"
    )
  }

  secret <- aa_query(
    conn,
    "SELECT secret FROM appauth_cookie_keys WHERE id = 1"
  )$secret

  if (length(secret) != 1 || !aa_is_string(secret[1])) {
    rlang::abort(
      "appauth: the cookie encryption key is missing from the database.",
      class = "appauth_error_schema"
    )
  }

  sodium::hash(charToRaw(secret[1]), size = 32L)
}

aa_cookie_encrypt <- function(payload, conn, settings) {
  key <- aa_cookie_key(conn, settings)
  nonce <- sodium::random(24L)
  cipher <- sodium::data_encrypt(serialize(payload, NULL), key, nonce)
  openssl::base64_encode(c(nonce, cipher))
}

aa_cookie_decrypt <- function(blob, conn, settings) {
  raw <- openssl::base64_decode(blob)

  if (length(raw) <= 24L) {
    return(NULL)
  }

  key <- aa_cookie_key(conn, settings)
  nonce <- raw[1:24]
  cipher <- raw[25:length(raw)]

  tryCatch(
    unserialize(sodium::data_decrypt(cipher, key, nonce)),
    error = function(e) NULL
  )
}

aa_cookie_ticket <- function(conn, settings, payload) {
  ticket <- openssl::base64_encode(openssl::rand_bytes(32))
  encrypted <- aa_cookie_encrypt(payload, conn, settings)
  ttl <- as.integer(settings$cookie_ticket_ttl_seconds)

  aa_execute(
    conn,
    "INSERT INTO cookie_tickets (token_hash, payload, created_at, expires_at)
     VALUES (?, ?, ?, ?)",
    params = list(
      aa_token_hash(ticket),
      encrypted,
      aa_utc(),
      aa_utc(ttl)
    )
  )

  ticket
}

aa_cookie_take_ticket <- function(conn, settings, ticket) {
  if (!aa_is_string(ticket)) {
    return(NULL)
  }

  now <- aa_utc()
  hash <- aa_token_hash(ticket)

  changed <- aa_execute(
    conn,
    "UPDATE cookie_tickets
     SET consumed_at = ?
     WHERE token_hash = ?
       AND consumed_at IS NULL
       AND expires_at > ?",
    params = list(now, hash, now)
  )

  if (length(changed) != 1 || is.na(changed) || changed < 1) {
    return(NULL)
  }

  row <- aa_query(
    conn,
    "SELECT payload FROM cookie_tickets
     WHERE token_hash = ? AND consumed_at = ?",
    params = list(hash, now)
  )

  if (nrow(row) != 1) {
    return(NULL)
  }

  payload <- aa_cookie_decrypt(row$payload[1], conn, settings)

  if (!is.list(payload) || !aa_is_string(payload$action)) {
    return(NULL)
  }

  payload
}

aa_cookie_clear_ticket <- function(conn, settings, name, redirect = NULL) {
  aa_cookie_ticket(
    conn,
    settings,
    list(action = "clear", name = name, redirect = redirect)
  )
}

aa_cookie_set_ticket <- function(
  conn,
  settings,
  name,
  value,
  max_age,
  redirect = NULL
) {
  aa_cookie_ticket(
    conn,
    settings,
    list(
      action = "set",
      name = name,
      value = value,
      max_age = as.integer(max_age),
      redirect = redirect
    )
  )
}

aa_cookie_endpoint_url <- function(path, id, ticket) {
  paste0(
    path,
    "?id=",
    aa_cookie_url_encode(id),
    "&ticket=",
    aa_cookie_url_encode(ticket)
  )
}

aa_request_secure <- function(req) {
  if (isTRUE(settings_flag(req$HTTP_X_FORWARDED_SSL))) {
    return(TRUE)
  }

  proto <- req$HTTP_X_FORWARDED_PROTO %||% ""
  if (grepl("https", tolower(proto), fixed = TRUE)) {
    return(TRUE)
  }

  https <- req$HTTPS %||% ""
  if (tolower(as.character(https)) %in% c("on", "1", "true")) {
    return(TRUE)
  }

  identical(as.character(req$SERVER_PORT %||% ""), "443")
}

settings_flag <- function(x) {
  if (is.logical(x) && length(x) == 1 && !is.na(x)) {
    return(x)
  }

  if (is.character(x) && length(x) == 1 && !is.na(x)) {
    return(tolower(x) %in% c("on", "1", "true"))
  }

  FALSE
}

aa_cookie_header <- function(payload, req, settings, name) {
  if (!aa_is_string(name) || grepl("[\r\n;=]", name)) {
    rlang::abort("appauth: invalid cookie name.", class = "appauth_error_settings")
  }

  clear <- identical(payload$action, "clear")
  value <- if (clear) "" else payload$value %||% ""

  if (!is.character(value) || length(value) != 1 || is.na(value) ||
    grepl("[\r\n;]", value)) {
    rlang::abort("appauth: invalid cookie value.", class = "appauth_error_settings")
  }

  max_age <- if (clear) 0L else as.integer(payload$max_age %||% 0L)
  secure <- if (is.null(settings$cookie_secure)) {
    aa_request_secure(req)
  } else {
    isTRUE(settings$cookie_secure)
  }

  if (identical(settings$cookie_samesite, "None")) {
    secure <- TRUE
  }

  parts <- c(
    paste0(name, "=", utils::URLencode(value, reserved = TRUE)),
    paste0("Path=", settings$cookie_path),
    paste0("Max-Age=", max(0L, max_age)),
    "HttpOnly",
    paste0("SameSite=", settings$cookie_samesite)
  )

  if (isTRUE(secure)) {
    parts <- c(parts, "Secure")
  }

  paste(parts, collapse = "; ")
}

aa_register_cookie_endpoint <- function(
  id,
  conn,
  settings,
  cookie_name,
  oauth_cookie,
  path
) {
  assign(
    id,
    list(
      conn = conn,
      settings = settings,
      cookie_name = cookie_name,
      oauth_cookie = oauth_cookie,
      path = path
    ),
    envir = .aa_cookie_endpoints
  )

  invisible(TRUE)
}

aa_unregister_cookie_endpoint <- function(id) {
  if (exists(id, envir = .aa_cookie_endpoints, inherits = FALSE)) {
    rm(list = id, envir = .aa_cookie_endpoints)
  }

  invisible(TRUE)
}

aa_cookie_http_handler <- function(req) {
  if (!identical(req$REQUEST_METHOD, "GET")) {
    return(NULL)
  }

  path <- req$PATH_INFO %||% ""
  if (!grepl("__appauth/cookie$", path)) {
    return(NULL)
  }

  query <- shiny::parseQueryString(req$QUERY_STRING %||% "")
  id <- query[["id"]]
  ticket <- query[["ticket"]]

  entry <- if (aa_is_string(id) &&
    exists(id, envir = .aa_cookie_endpoints, inherits = FALSE)) {
    get(id, envir = .aa_cookie_endpoints, inherits = FALSE)
  } else {
    NULL
  }

  if (is.null(entry)) {
    return(shiny::httpResponse(
      status = 404L,
      content_type = "text/plain; charset=UTF-8",
      content = "Unknown appauth cookie endpoint"
    ))
  }

  payload <- tryCatch(
    aa_cookie_take_ticket(entry$conn, entry$settings, ticket),
    error = function(e) NULL
  )

  if (is.null(payload)) {
    return(shiny::httpResponse(
      status = 400L,
      content_type = "text/plain; charset=UTF-8",
      content = "Invalid or expired appauth cookie ticket"
    ))
  }

  name <- payload$name %||% entry$cookie_name
  header <- tryCatch(
    aa_cookie_header(payload, req, entry$settings, name),
    error = function(e) NULL
  )

  if (is.null(header)) {
    return(shiny::httpResponse(
      status = 400L,
      content_type = "text/plain; charset=UTF-8",
      content = "Invalid appauth cookie ticket"
    ))
  }

  headers <- list(
    "Set-Cookie" = header,
    "Cache-Control" = "no-store",
    "Pragma" = "no-cache"
  )

  redirect <- payload$redirect

  if (
    aa_is_string(redirect) && nzchar(redirect) && !grepl("[\r\n]", redirect)
  ) {
    headers$Location <- redirect
    return(shiny::httpResponse(
      status = 302L,
      headers = headers,
      content = ""
    ))
  }

  shiny::httpResponse(
    status = 204L,
    headers = headers,
    content = ""
  )
}

aa_register_cookie_handler <- function() {
  manager <- tryCatch(
    get("handlerManager", envir = asNamespace("shiny")),
    error = function(e) NULL
  )

  if (is.null(manager)) {
    return(invisible(FALSE))
  }

  handlers <- tryCatch(manager$handlers$handlers, error = function(e) list())
  if ("appauth_cookie" %in% names(handlers)) {
    return(invisible(FALSE))
  }

  tryCatch(
    manager$addHandler(
      aa_cookie_http_handler,
      "appauth_cookie",
      tail = TRUE
    ),
    error = function(e) NULL
  )

  invisible(TRUE)
}
