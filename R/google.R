# Вход через Google (OpenID Connect, authorization code flow с PKCE).
#
# Как это устроено и почему безопасно:
#  - вход начинается кнопкой: пакет создаёт одноразовые state, nonce и PKCE-проверку и
#    сохраняет их в таблице oauth_states (state только в виде sha256, срок жизни 10 минут);
#  - state дополнительно кладётся в короткоживущий cookie браузера: вернувшись от Google,
#    пакет сверяет state из адреса с cookie, поэтому чужую ссылку со своим кодом в
#    браузер жертвы подсунуть нельзя (login CSRF);
#  - код обменивается на токен на стороне сервера (client_secret не покидает сервер);
#  - id_token проверяется целиком: подпись по ключам Google (только RS256), издатель,
#    аудитория, срок, nonce, подтверждённый email и домен организации;
#  - пользователь ищется по email среди уже существующих: автоматически новых не
#    создаём, роль берётся из базы, заблокированный пользователь не входит;
#  - пакет ничего не пишет в логи сам: причину отказа получает хук on_event.

#' Адреса Google
#'
#' Вынесены в функцию, чтобы тесты могли их подменить.
#'
#' @returns Список с адресами и допустимыми издателями токена.
#' @noRd
aa_google_urls <- function() {
  list(
    auth    = "https://accounts.google.com/o/oauth2/v2/auth",
    token   = "https://oauth2.googleapis.com/token",
    jwks    = "https://www.googleapis.com/oauth2/v3/certs",
    issuers = c("https://accounts.google.com", "accounts.google.com")
  )
}

#' Base64url без заполнения (RFC 4648, раздел 5)
#'
#' @param raw Вектор `raw`.
#'
#' @returns Строка.
#' @noRd
aa_b64url_encode <- function(raw) {
  chartr("+/", "-_", sub("=+$", "", as.character(openssl::base64_encode(raw))))
}

#' Расшифровка base64url
#'
#' @param text Строка base64url.
#'
#' @returns Вектор `raw`.
#' @noRd
aa_b64url_decode <- function(text) {
  b64 <- chartr("-_", "+/", text)
  pad <- (4 - nchar(b64) %% 4) %% 4

  openssl::base64_decode(paste0(b64, strrep("=", pad)))
}

#' Приведение значения `email_verified` из токена к логическому
#'
#' Google отдаёт булево значение, но строку `"true"` тоже принимаем.
#'
#' @param x Значение из токена.
#'
#' @returns `TRUE` или `FALSE`.
#' @noRd
aa_google_flag <- function(x) {
  isTRUE(x) || identical(tolower(as.character(x)), "true")
}

#' Начать вход через Google
#'
#' Создаёт одноразовые `state`, `nonce` и PKCE-проверку, сохраняет их в базе и
#' возвращает адрес страницы согласия Google.
#'
#' @param conn Подключение к базе SQLite со схемой [aa_init_db()].
#' @param settings Настройки, результат [aa_settings()], с `google_enabled = TRUE`.
#'
#' @returns Список: `url` (куда отправить браузер) и `state` (его нужно положить в
#'   cookie браузера, чтобы потом сверить).
#' @noRd
aa_google_start <- function(conn, settings) {
  if (!isTRUE(settings$google_enabled)) {
    rlang::abort("Вход через Google выключен.", class = "appauth_error_settings")
  }

  # защита от засорения таблицы: общий лимит запусков в минуту
  recent <- DBI::dbGetQuery(
    conn,
    "SELECT COUNT(*) AS n FROM oauth_states WHERE created_at > datetime('now', '-1 minutes')"
  )$n

  if (recent >= 60) {
    rlang::abort("Слишком много запусков входа через Google.", class = "appauth_error_throttled")
  }

  state    <- aa_b64url_encode(openssl::rand_bytes(32))
  nonce    <- aa_b64url_encode(openssl::rand_bytes(16))
  verifier <- aa_b64url_encode(openssl::rand_bytes(32))
  challenge <- aa_b64url_encode(unclass(openssl::sha256(charToRaw(verifier))))

  DBI::dbExecute(
    conn,
    "INSERT INTO oauth_states (state_hash, nonce, code_verifier, expires_at)
     VALUES (?, ?, ?, datetime('now', '+600 seconds'))",
    params = list(aa_token_hash(state), nonce, verifier)
  )

  query <- list(
    client_id             = settings$google_client_id,
    redirect_uri          = settings$google_redirect_uri,
    response_type         = "code",
    scope                 = "openid email",
    state                 = state,
    nonce                 = nonce,
    code_challenge        = challenge,
    code_challenge_method = "S256",
    prompt                = "select_account"
  )

  # подсказка Google, какой домен предложить; настоящая проверка домена идёт по токену
  if (length(settings$google_domains) == 1) {
    query$hd <- settings$google_domains
  }

  pairs <- paste0(
    names(query), "=",
    vapply(query, function(x) utils::URLencode(x, reserved = TRUE), character(1))
  )

  list(url = paste0(aa_google_urls()$auth, "?", paste(pairs, collapse = "&")), state = state)
}

#' Забрать сохранённый state (один раз)
#'
#' Гасит запись атомарным запросом: одним и тем же `state` воспользоваться второй раз
#' нельзя, просроченный `state` не принимается.
#'
#' @param conn Подключение к базе SQLite.
#' @param state Значение `state` из адреса.
#'
#' @returns Список `nonce` и `code_verifier` или `NULL`.
#' @noRd
aa_google_take_state <- function(conn, state) {
  if (!aa_is_string(state) || nchar(state) > 200) {
    return(NULL)
  }

  hash <- aa_token_hash(state)

  claimed <- DBI::dbExecute(
    conn,
    "UPDATE oauth_states SET used = 1
     WHERE state_hash = ? AND used = 0 AND expires_at > datetime('now')",
    params = list(hash)
  )

  if (claimed != 1) {
    return(NULL)
  }

  row <- DBI::dbGetQuery(
    conn,
    "SELECT nonce, code_verifier FROM oauth_states WHERE state_hash = ?",
    params = list(hash)
  )

  if (nrow(row) != 1) NULL else as.list(row)
}

#' Обменять код на id_token
#'
#' @param settings Настройки, результат [aa_settings()].
#' @param code Код авторизации из адреса.
#' @param verifier PKCE-проверка, сохранённая при старте входа.
#'
#' @returns Строка `id_token` или `NULL`.
#' @noRd
aa_google_exchange_code <- function(settings, code, verifier) {
  req <- httr2::request(aa_google_urls()$token)
  req <- httr2::req_body_form(
    req,
    code          = code,
    client_id     = settings$google_client_id,
    client_secret = settings$google_client_secret,
    redirect_uri  = settings$google_redirect_uri,
    grant_type    = "authorization_code",
    code_verifier = verifier
  )
  req <- httr2::req_timeout(req, 15)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)

  resp <- httr2::req_perform(req)

  if (httr2::resp_status(resp) != 200) {
    body <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
    message(
      "appauth: Google отклонил обмен кода (HTTP ", httr2::resp_status(resp), "): ",
      paste(c(body$error, body$error_description), collapse = ": ")
    )
    return(NULL)
  }

  token <- httr2::resp_body_json(resp)$id_token

  if (aa_is_string(token)) token else NULL
}

#' Загрузить публичные ключи Google
#'
#' @returns Список ключей JWK.
#' @noRd
aa_google_fetch_jwks <- function() {
  req <- httr2::req_timeout(httr2::request(aa_google_urls()$jwks), 15)

  httr2::resp_body_json(httr2::req_perform(req))$keys
}

aa_google_jwks_cache <- new.env(parent = emptyenv())

#' Публичные ключи Google с кешем на час
#'
#' @param refresh Принудительно загрузить заново (ключ с неизвестным `kid`).
#'
#' @returns Список ключей JWK.
#' @noRd
aa_google_jwks <- function(refresh = FALSE) {
  now <- as.numeric(Sys.time())

  if (!refresh && !is.null(aa_google_jwks_cache$keys) && now - aa_google_jwks_cache$at < 3600) {
    return(aa_google_jwks_cache$keys)
  }

  keys <- aa_google_fetch_jwks()
  aa_google_jwks_cache$keys <- keys
  aa_google_jwks_cache$at <- now

  keys
}

#' Публичный ключ для токена по `kid`
#'
#' @param kid Идентификатор ключа из заголовка токена.
#'
#' @returns Ключ (`openssl`) или `NULL`.
#' @noRd
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

#' Проверить id_token
#'
#' @param id_token Строка токена.
#' @param settings Настройки, результат [aa_settings()].
#' @param nonce Ожидаемый `nonce`.
#' @param now Текущее время (для тестов).
#'
#' @returns Список: `ok`, `reason` (`bad_token`, `bad_nonce`, `email_unverified`,
#'   `domain`) и `email` (нормализованный адрес, если он известен).
#' @noRd
aa_google_verify_id_token <- function(id_token, settings, nonce, now = Sys.time()) {
  fail <- function(reason, email = NA_character_) list(ok = FALSE, reason = reason, email = email)

  parts <- strsplit(id_token, ".", fixed = TRUE)[[1]]

  if (length(parts) != 3 || !all(nzchar(parts))) {
    return(fail("bad_token"))
  }

  header <- tryCatch(
    jsonlite::fromJSON(rawToChar(aa_b64url_decode(parts[1])), simplifyVector = FALSE),
    error = function(e) NULL
  )

  # только RS256: другие алгоритмы (в том числе none) не принимаем
  if (!is.list(header) || !identical(header[["alg"]], "RS256") || !aa_is_string(header[["kid"]])) {
    return(fail("bad_token"))
  }

  key <- aa_google_public_key(header[["kid"]])

  if (is.null(key)) {
    return(fail("bad_token"))
  }

  claims <- tryCatch(jose::jwt_decode_sig(id_token, key), error = function(e) NULL)

  if (!is.list(claims)) {
    return(fail("bad_token"))
  }

  email <- aa_normalize_email(claims[["email"]])

  audience_ok <- aa_is_string(settings$google_client_id) &&
    settings$google_client_id %in% unlist(claims[["aud"]]) &&
    (length(unlist(claims[["aud"]])) == 1 || identical(claims[["azp"]], settings$google_client_id))

  exp_ok <- is.numeric(claims[["exp"]]) && length(claims[["exp"]]) == 1 && claims[["exp"]] > as.numeric(now)

  if (!isTRUE(claims[["iss"]] %in% aa_google_urls()$issuers) || !audience_ok || !exp_ok) {
    return(fail("bad_token", email))
  }

  if (!aa_is_string(claims[["nonce"]]) || !identical(claims[["nonce"]], nonce)) {
    return(fail("bad_nonce", email))
  }

  if (!nzchar(email) || !aa_google_flag(claims[["email_verified"]])) {
    return(fail("email_unverified", email))
  }

  domains <- settings$google_domains

  if (length(domains) > 0) {
    # hd это основной домен организации Workspace: у сотрудника со вторичным доменом он
    # отличается от домена email, поэтому оба значения проверяются по списку отдельно
    hd <- tolower(as.character(claims[["hd"]] %||% ""))
    email_domain <- sub("^.*@", "", email)

    domain_ok <- nzchar(hd) && hd %in% domains && email_domain %in% domains

    if (!domain_ok) {
      return(fail("domain", email))
    }
  }

  list(ok = TRUE, reason = "ok", email = email)
}

#' Завершить вход через Google
#'
#' Принимает `code` и `state` из адреса возврата, проверяет всё и находит
#' пользователя по email. Сверка `state` с cookie браузера делается в модуле
#' [aa_auth_server()], до вызова этой функции.
#'
#' @param conn Подключение к базе SQLite.
#' @param settings Настройки, результат [aa_settings()].
#' @param code,state Параметры из адреса возврата.
#'
#' @returns Список: `ok`, `reason`, `email`, `login` и `role` (последние два при
#'   успехе). Причины отказа: `disabled`, `bad_state`, `bad_code`, `exchange_failed`,
#'   `bad_token`, `bad_nonce`, `email_unverified`, `domain`, `no_user`, `blocked`.
#' @noRd
aa_google_complete <- function(conn, settings, code, state) {
  fail <- function(reason, email = NA_character_) {
    list(ok = FALSE, reason = reason, email = email, login = NA_character_, role = NA_character_)
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
      message("appauth: не удалось обменять код Google на токен: ", conditionMessage(e))
      NULL
    }
  )

  if (!aa_is_string(id_token)) {
    return(fail("exchange_failed"))
  }

  verified <- tryCatch(
    aa_google_verify_id_token(id_token, settings, saved$nonce),
    error = function(e) {
      message("appauth: не удалось проверить токен Google: ", conditionMessage(e))
      list(ok = FALSE, reason = "bad_token", email = NA_character_)
    }
  )

  if (!isTRUE(verified$ok)) {
    return(fail(verified$reason, verified$email))
  }

  user <- DBI::dbGetQuery(
    conn,
    "SELECT login, role, blocked FROM users WHERE email = ?",
    params = list(verified$email)
  )

  if (nrow(user) != 1) {
    return(fail("no_user", verified$email))
  }

  if (isTRUE(user$blocked[1] == 1)) {
    return(fail("blocked", verified$email))
  }

  list(ok = TRUE, reason = "ok", email = verified$email, login = user$login[1], role = user$role[1])
}

#' Разобрать адрес на схему, хост и порт
#'
#' @param url Адрес (`https://host[:port][/путь]`).
#'
#' @returns Список `scheme`, `host`, `port` (строки, порт по умолчанию подставляется)
#'   или `NULL`, если адрес не разобрать.
#' @noRd
aa_url_origin <- function(url) {
  if (!aa_is_string(url)) {
    return(NULL)
  }

  m <- regmatches(url, regexec("^(https?)://([^/:?#]+)(?::([0-9]+))?", url, perl = TRUE))[[1]]

  if (length(m) == 0) {
    return(NULL)
  }

  scheme <- tolower(m[2])
  port <- if (nzchar(m[4])) m[4] else if (identical(scheme, "https")) "443" else "80"

  list(scheme = scheme, host = tolower(m[3]), port = port)
}

#' Адрес сайта (схема, хост, порт) строкой, без порта по умолчанию
#'
#' @param origin Результат [aa_url_origin()].
#'
#' @returns Строка вида `https://sm.example.com`.
#' @noRd
aa_origin_string <- function(origin) {
  default <- identical(origin$port, if (identical(origin$scheme, "https")) "443" else "80")

  paste0(origin$scheme, "://", origin$host, if (!default) paste0(":", origin$port))
}

#' С какого адреса открыта страница
#'
#' Вынесено в функцию, чтобы тесты могли подменить адрес: у mock-сессии Shiny его нет.
#'
#' @param session Сессия модуля.
#'
#' @returns Результат вида [aa_url_origin()] или `NULL`, если браузер ещё не сообщил адрес.
#' @noRd
aa_page_origin <- function(session) {
  data <- shiny::isolate(session$clientData)
  protocol <- shiny::isolate(data$url_protocol)
  hostname <- shiny::isolate(data$url_hostname)
  port <- shiny::isolate(data$url_port)

  if (!aa_is_string(protocol) || !aa_is_string(hostname)) {
    return(NULL)
  }

  aa_url_origin(paste0(protocol, "//", hostname, if (aa_is_string(as.character(port))) paste0(":", port)))
}

#' Открыта ли страница на адресе возврата Google
#'
#' `state` входа лежит в cookie, а cookie принадлежит адресу сайта (по IP и по домену
#' они разные). Google возвращает пользователя на `google_redirect_uri`, поэтому вход
#' нужно начинать на том же адресе. Если адрес страницы неизвестен, считаем, что он
#' совпадает: лишний переход хуже, чем попытка начать вход на месте.
#'
#' @param session Сессия модуля.
#' @param redirect_uri Адрес возврата из настроек.
#'
#' @returns `TRUE` или `FALSE`.
#' @noRd
aa_page_matches <- function(session, redirect_uri) {
  page <- aa_page_origin(session)
  target <- aa_url_origin(redirect_uri)

  if (is.null(page) || is.null(target)) {
    return(TRUE)
  }

  identical(page, target)
}

#' Адрес для перехода на адрес возврата с автозапуском входа
#'
#' @param settings Настройки, результат [aa_settings()].
#'
#' @returns Адрес возврата с параметром `google=1`.
#' @noRd
aa_google_hop_url <- function(settings) {
  uri <- settings$google_redirect_uri

  paste0(uri, if (grepl("?", uri, fixed = TRUE)) "&" else "?", "google=1")
}

#' Отправить браузеру команду перейти на адрес
#'
#' Браузер выполнит переход только на Google или на адрес сайта `origin`, который
#' передаёт сервер. Вынесено в функцию, чтобы тесты могли перехватить переход.
#'
#' @param session Сессия модуля.
#' @param url Адрес перехода.
#' @param origin Адрес сайта, на который переход разрешён (кроме Google).
#'
#' @returns Невидимо `NULL`.
#' @noRd
aa_redirect <- function(session, url, origin) {
  session$sendCustomMessage("appauth_redirect", list(url = url, origin = origin))

  invisible(NULL)
}

#' Ключ текста для причины отказа входа через Google
#'
#' @param reason Причина из [aa_google_complete()].
#'
#' @returns Ключ в словаре текстов.
#' @noRd
aa_google_text_key <- function(reason) {
  switch(
    reason,
    blocked   = "blocked_user",
    no_user   = "google_no_user",
    domain    = "google_domain",
    cancelled = "google_cancelled",
    "google_failed"
  )
}
