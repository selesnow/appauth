# Двухфакторная аутентификация: одноразовые коды TOTP (RFC 6238) и резервные коды.
#
# Правила, которые держат эти функции:
#  - секрет хранится в базе только в зашифрованном виде (sodium, ключ из настройки
#    `totp_key`), поэтому одной базы для получения кодов недостаточно;
#  - пока пользователь не подтвердил код из приложения, 2FA не включена
#    (`totp_enabled = 0`), а ожидающий секрет можно заменить;
#  - один и тот же код (шаг времени) принимается один раз: `totp_last_step`
#    защищает от повторного использования подсмотренного кода;
#  - резервные коды одноразовые, в базе только sha256;
#  - подбор кодов ограничивает общая защита входа: неверный код записывается как
#    неудачная попытка входа (aa_record_attempt), а перед проверкой кода вызывается
#    aa_login_gate().

aa_base32_alphabet <- "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

#' Кодирование в base32 (RFC 4648, без заполнения)
#'
#' @param x Вектор `raw`.
#'
#' @returns Строка из символов `A-Z2-7`.
#' @noRd
aa_base32_encode <- function(x) {
  if (length(x) == 0) {
    return("")
  }

  bits <- unlist(lapply(as.integer(x), function(b) as.integer(rev(intToBits(b)[1:8]))))
  pad <- (5 - length(bits) %% 5) %% 5
  bits <- c(bits, rep(0L, pad))
  groups <- matrix(bits, ncol = 5, byrow = TRUE)
  idx <- as.vector(groups %*% c(16L, 8L, 4L, 2L, 1L)) + 1L

  paste(strsplit(aa_base32_alphabet, "")[[1]][idx], collapse = "")
}

#' Декодирование base32
#'
#' @param x Строка base32 (регистр и пробелы не важны, заполнение `=` игнорируется).
#'
#' @returns Вектор `raw` или `NULL`, если в строке есть недопустимые символы.
#' @noRd
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

  bytes <- matrix(bits[seq_len(n * 8)], ncol = 8, byrow = TRUE) %*% c(128L, 64L, 32L, 16L, 8L, 4L, 2L, 1L)

  as.raw(as.vector(bytes))
}

#' Случайный секрет для приложения-аутентификатора
#'
#' @returns Строка base32 из 32 символов (160 бит), так её вводят в приложение
#'   вручную.
#' @export
#'
#' @examples
#' nchar(aa_totp_secret())
aa_totp_secret <- function() {
  aa_base32_encode(openssl::rand_bytes(20))
}

#' Одноразовый код TOTP для момента времени
#'
#' Алгоритм RFC 6238 (HMAC-SHA1, шаг 30 секунд). Нужна в тестах и для сверки с
#' приложением-аутентификатором.
#'
#' @param secret Секрет в base32.
#' @param time Момент времени (по умолчанию сейчас).
#' @param digits Число цифр кода.
#' @param period Длина шага, секунд.
#'
#' @returns Строка из `digits` цифр или `NA`, если секрет некорректен.
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

#' Код HOTP по счётчику (RFC 4226)
#'
#' @param key Ключ (`raw`).
#' @param counter Счётчик (целое, шаг времени).
#' @param digits Число цифр.
#'
#' @returns Строка из `digits` цифр.
#' @noRd
aa_hotp <- function(key, counter, digits = 6) {
  # счётчик 8 байт в порядке от старшего: старшие 4 байта нулевые до 2106 года
  msg <- c(raw(4), writeBin(as.integer(counter), raw(), size = 4, endian = "big"))
  hash <- as.integer(as.raw(openssl::sha1(msg, key = key)))
  offset <- bitwAnd(hash[20], 15L) + 1L
  bin <- bitwOr(
    bitwOr(bitwShiftL(bitwAnd(hash[offset], 127L), 24L), bitwShiftL(hash[offset + 1L], 16L)),
    bitwOr(bitwShiftL(hash[offset + 2L], 8L), hash[offset + 3L])
  )

  formatC(bin %% (10 ^ digits), width = digits, format = "d", flag = "0")
}

#' Ссылка otpauth для приложения-аутентификатора
#'
#' Из этой ссылки строится QR-код, её же понимают приложения при ручном вводе.
#'
#' @param secret Секрет в base32.
#' @param login Логин пользователя.
#' @param issuer Название сервиса, которое покажет приложение.
#'
#' @returns Строка вида `otpauth://totp/...`.
#' @export
#'
#' @examples
#' aa_totp_uri("JBSWY3DPEHPK3PXP", "ivan", "Reports portal")
aa_totp_uri <- function(secret, login, issuer = "appauth") {
  enc <- function(x) utils::URLencode(x, reserved = TRUE)

  sprintf(
    "otpauth://totp/%s:%s?secret=%s&issuer=%s&algorithm=SHA1&digits=6&period=30",
    enc(issuer), enc(login), secret, enc(issuer)
  )
}

#' Ключ шифрования секретов из настроек
#'
#' @param settings Настройки, результат [aa_settings()].
#'
#' @returns Ключ (`raw`, 32 байта).
#' @noRd
aa_totp_key <- function(settings) {
  if (!aa_is_string(settings$totp_key)) {
    rlang::abort(
      "Для двухфакторной аутентификации нужен ключ шифрования `totp_key` в настройках.",
      class = "appauth_error_settings"
    )
  }

  sodium::hash(charToRaw(settings$totp_key), size = 32)
}

#' Зашифровать секрет для хранения в базе
#'
#' @param secret Секрет base32.
#' @param settings Настройки, результат [aa_settings()].
#'
#' @returns Строка hex: одноразовое число (24 байта) и шифртекст.
#' @noRd
aa_totp_seal <- function(secret, settings) {
  nonce <- sodium::random(24)
  cipher <- sodium::data_encrypt(charToRaw(secret), aa_totp_key(settings), nonce)

  sodium::bin2hex(c(nonce, cipher))
}

#' Расшифровать секрет из базы
#'
#' @param sealed Строка из [aa_totp_seal()].
#' @param settings Настройки, результат [aa_settings()].
#'
#' @returns Секрет base32 или `NA`, если расшифровать не удалось (другой ключ,
#'   повреждённые данные).
#' @noRd
aa_totp_unseal <- function(sealed, settings) {
  if (!aa_is_string(sealed)) {
    return(NA_character_)
  }

  tryCatch(
    {
      raw <- sodium::hex2bin(sealed)
      plain <- sodium::data_decrypt(raw[-(1:24)], aa_totp_key(settings), raw[1:24])
      rawToChar(plain)
    },
    error = function(e) NA_character_
  )
}

#' Данные 2FA пользователя из базы
#'
#' @param conn Подключение к базе данных.
#' @param login Логин.
#'
#' @returns Таблица из одной строки (`totp_secret`, `totp_enabled`,
#'   `totp_last_step`) или `NULL`, если пользователя нет или схема не достроена.
#' @noRd
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

#' Включена ли двухфакторная аутентификация у пользователя
#'
#' @inheritParams aa_get_user
#'
#' @returns `TRUE` или `FALSE` (`FALSE` и для несуществующего пользователя, и
#'   если схема не достроена до версии 8).
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

#' Начать подключение двухфакторной аутентификации
#'
#' Создаёт новый секрет и сохраняет его в базе в зашифрованном виде, но **не
#' включает** 2FA: она включится только после [aa_totp_enable()] с верным кодом
#' из приложения. Повторный вызов заменяет ожидающий секрет. Если 2FA уже
#' включена, ошибка класса `appauth_error_user`.
#'
#' @inheritParams aa_get_user
#' @param settings Настройки, результат [aa_settings()] с `totp_enabled = TRUE`.
#'
#' @returns Список: `secret` (base32, для ручного ввода) и `uri` (ссылка
#'   `otpauth://`, из неё строится QR-код).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   settings <- aa_settings(totp_enabled = TRUE, totp_key = "a-long-random-key-for-the-example")
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

#' Проверить код TOTP и запомнить шаг
#'
#' @param secret Секрет base32.
#' @param code Введённый код.
#' @param last_step Последний принятый шаг времени.
#' @param settings Настройки, результат [aa_settings()].
#' @param time Момент времени.
#'
#' @returns Принятый шаг времени или `NA`, если код неверен или уже использован.
#' @noRd
aa_totp_match_step <- function(secret, code, last_step, settings, time = Sys.time()) {
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
  # сравнение без раннего выхода: время проверки не зависит от того, какой шаг подошёл
  matched <- vapply(steps, function(s) identical(aa_hotp(key, s, 6), code), logical(1))
  last_step <- if (is.na(last_step)) 0 else as.numeric(last_step)
  steps <- steps[matched & steps > last_step]

  if (length(steps) == 0) NA_real_ else max(steps)
}

#' Хеш резервного кода
#'
#' @param code Код в любом регистре, с пробелами или дефисами.
#'
#' @returns Строка sha256 или `NA`, если формат не подходит.
#' @noRd
aa_recovery_hash <- function(code) {
  code <- tolower(gsub("[[:space:]-]", "", as.character(code)))

  if (!grepl("^[0-9a-f]{10}$", code)) {
    return(NA_character_)
  }

  aa_token_hash(code)
}

#' Создать набор резервных кодов
#'
#' @param conn Подключение к базе данных.
#' @param login Логин.
#' @param n Сколько кодов.
#'
#' @returns Вектор кодов вида `abcde-12345` (показываются один раз).
#' @noRd
aa_new_recovery_codes <- function(conn, login, n = 10) {
  raw_codes <- vapply(seq_len(n), function(i) {
    paste(as.character(openssl::rand_bytes(5)), collapse = "")
  }, character(1))

  aa_execute(conn, "DELETE FROM totp_recovery WHERE user_login = ?", params = list(login))

  for (code in raw_codes) {
    aa_execute(
      conn,
      "INSERT INTO totp_recovery (user_login, code_hash, created_at) VALUES (?, ?, ?)",
      params = list(login, aa_token_hash(code), aa_utc())
    )
  }

  paste0(substr(raw_codes, 1, 5), "-", substr(raw_codes, 6, 10))
}

#' Включить двухфакторную аутентификацию
#'
#' Проверяет код из приложения для ожидающего секрета ([aa_totp_setup()]) и
#' включает 2FA. Создаёт 10 резервных кодов: **они возвращаются один раз**, в базе
#' остаются только хеши. Неверный код даёт ошибку класса `appauth_error_user`
#' (`reason = "totp_wrong"`).
#'
#' @inheritParams aa_totp_setup
#' @param code Код из приложения-аутентификатора.
#'
#' @returns Вектор резервных кодов (невидимо).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   settings <- aa_settings(totp_enabled = TRUE, totp_key = "a-long-random-key-for-the-example")
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
  step <- if (is.na(secret)) NA_real_ else aa_totp_match_step(secret, code, 0, settings)

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

#' Выключить двухфакторную аутентификацию
#'
#' Стирает секрет и резервные коды пользователя. Функция **ничего не проверяет**:
#' модуль [aa_totp_server()] перед вызовом требует пароль и код, а сброс
#' администратором ([aa_users_server()]) разрешён только администратору.
#'
#' @inheritParams aa_get_user
#'
#' @returns `TRUE`, если у пользователя что-то было сброшено, иначе `FALSE`
#'   (невидимо).
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
  aa_execute(conn, "DELETE FROM totp_recovery WHERE user_login = ?", params = list(login))

  invisible(n > 0)
}

#' Сколько резервных кодов осталось
#'
#' @inheritParams aa_get_user
#'
#' @returns Целое число неиспользованных резервных кодов.
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

#' Проверить второй фактор при входе
#'
#' Принимает код из приложения (6 цифр) или резервный код. Код из приложения
#' принимается один раз: повтор того же кода (шага времени) отклоняется. Резервный
#' код одноразовый. Функция **не ограничивает число попыток сама**: перед ней
#' вызывайте [aa_login_gate()], а после неверного кода [aa_record_attempt()], как
#' делает модуль входа.
#'
#' @inheritParams aa_totp_setup
#' @param code Введённый код.
#'
#' @returns Список: `ok` (`TRUE` или `FALSE`) и `method` (`"totp"`, `"recovery"`
#'   или `NA`).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   settings <- aa_settings(totp_enabled = TRUE, totp_key = "a-long-random-key-for-the-example")
#'   aa_verify_second_factor(conn, "boss", "123456", settings)$ok
#'   DBI::dbDisconnect(conn)
#' }
aa_verify_second_factor <- function(conn, login, code, settings = aa_settings()) {
  aa_check_conn(conn)

  failed <- list(ok = FALSE, method = NA_character_)
  row <- aa_totp_row(conn, login)

  if (is.null(row) || !isTRUE(as.logical(row$totp_enabled[1])) || !aa_is_string(code)) {
    return(failed)
  }

  hash <- aa_recovery_hash(code)

  if (!is.na(hash)) {
    # резервный код занимается атомарным запросом: из двух одновременных сработает один
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

  # шаг запоминается атомарно: тот же код во втором запросе уже не пройдёт
  claimed <- aa_execute(
    conn,
    "UPDATE users SET totp_last_step = ? WHERE login = ? AND totp_last_step < ?",
    params = list(step, login, step)
  )

  if (claimed == 1) list(ok = TRUE, method = "totp") else failed
}
