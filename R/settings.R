#' Настройки авторизации
#'
#' Собирает настройки, от которых зависит поведение пакета: правила пароля,
#' защита от подбора, сроки хранения данных, список ролей и язык интерфейса.
#' Значения по умолчанию соответствуют приложению Server Manager. Объект
#' настроек передаётся в остальные функции и модули пакета, глобальных
#' переменных пакет не использует.
#'
#' @section Защита от подбора пароля:
#' Если за `lockout_minutes` минут под одним логином накопилось
#' `max_failed_logins` неудачных попыток, вход под этим логином блокируется на
#' `lockout_minutes` минут с момента последней неудачной попытки. Попытки во
#' время блокировки не записываются и блокировку не продлевают. Кроме того,
#' если за последнюю минуту по всем логинам вместе накопилось
#' `max_failed_logins_per_minute` неудачных попыток, вход временно закрыт для
#' всех: это останавливает перебор по многим логинам сразу.
#'
#' @param max_failed_logins Число неудачных попыток входа до блокировки логина.
#' @param lockout_minutes Окно подсчёта неудачных попыток и длительность
#'   блокировки, минут.
#' @param max_failed_logins_per_minute Общий лимит неудачных попыток входа по
#'   всем логинам за минуту.
#' @param password_min,password_max Минимальная и максимальная длина нового
#'   пароля. Ограничение действует только для новых и сбрасываемых паролей,
#'   существующие пароли не затрагиваются.
#' @param password_policy Что делать со слабыми новыми паролями (из списка
#'   [aa_common_passwords()], совпадающими с логином без учёта регистра или
#'   состоящими из одного повторяющегося символа): `"off"` ничего не проверять,
#'   `"warn"` (по умолчанию) принять пароль, но показать предупреждение, `"reject"`
#'   отклонить пароль. Существующие пароли не затрагиваются.
#' @param login_max Максимальная длина логина (логин также приводится к нижнему
#'   регистру и обрезается по краям при подсчёте попыток).
#' @param autologin Использовать ли автовход по cookie. Если `FALSE`, пользователь
#'   вводит пароль при каждой загрузке страницы, токены не выдаются.
#' @param session_days Срок жизни токена автовхода, дней.
#' @param session_check_seconds Как часто проверять, что открытая сессия ещё
#'   разрешена (пользователя не заблокировали и не удалили), секунд.
#' @param attempts_retention_hours Сколько часов хранить записи о попытках входа.
#' @param token_retention_days Сколько дней хранить просроченные и отозванные
#'   токены перед удалением.
#' @param roles Допустимые роли пользователей.
#' @param admin_role Роль администратора, она должна входить в `roles`. Только
#'   эта роль управляет пользователями, независимо от матрицы прав приложения,
#'   и именно её получает первый созданный пользователь.
#' @param must_change_default Значение галочки «потребовать смену пароля при
#'   следующем входе» в окне добавления пользователя и при сбросе пароля.
#'   `TRUE` (по умолчанию): пароль, который задал администратор, временный, и
#'   администратор снимает галочку, если смена не нужна. `FALSE`: галочка
#'   выключена, администратор включает её сам.
#' @param reset_enabled Включить восстановление пароля по email: на форме входа
#'   появляется ссылка «Забыли пароль?». По умолчанию `FALSE`. Требует `send_reset`
#'   и `reset_base_url`.
#' @param send_reset Функция отправки письма `function(email, link, login)`:
#'   отправляет письмо со ссылкой `link` на адрес `email` (например, через
#'   `emayili`). Ошибка в функции не прерывает запрос и не видна пользователю,
#'   причина попадает в событие `password_reset_requested`.
#' @param reset_base_url Адрес приложения, на который ведёт ссылка из письма, например
#'   `"https://apps.example.com/my_app"`. К нему добавляется `?reset=<токен>`.
#' @param reset_ttl_minutes Срок жизни ссылки для смены пароля, минут.
#' @param reset_max_per_hour Сколько писем для восстановления можно отправить
#'   одному пользователю за час, остальные запросы молча игнорируются.
#' @param reset_max_per_minute Общий лимит писем восстановления по всем
#'   пользователям за минуту (защита от рассылки спама).
#' @param totp_enabled Включить двухфакторную аутентификацию (одноразовые коды
#'   TOTP из приложения-аутентификатора). По умолчанию `FALSE`. Требует `totp_key`.
#'   Двухфакторная защита добровольная: каждый пользователь включает её сам в
#'   модуле [aa_totp_server()], а у кого она включена, тот вводит код при входе по
#'   паролю.
#' @param totp_key Ключ шифрования секретов TOTP в базе, строка не короче 16
#'   символов (например, из переменной среды). **Хранить вне базы и вне репозитория.**
#'   Если ключ потерять или заменить, существующие секреты расшифровать не удастся,
#'   и пользователям придётся подключать 2FA заново (администратор сбрасывает её в
#'   карточке).
#' @param totp_issuer Название сервиса, которое покажет приложение-аутентификатор.
#' @param totp_window На сколько 30-секундных шагов в обе стороны допускается
#'   расхождение часов (0 до 5, по умолчанию 1).
#' @param texts Тексты интерфейса, результат [aa_texts()].
#'
#' @returns Список настроек класса `aa_settings`.
#' @export
#'
#' @examples
#' # настройки по умолчанию
#' settings <- aa_settings()
#'
#' # восстановление пароля по email
#' settings <- aa_settings(
#'   reset_enabled  = TRUE,
#'   reset_base_url = "https://apps.example.com/my_app",
#'   send_reset     = function(email, link, login) message("Письмо для ", login, ": ", link)
#' )
#'
#' # более строгая защита, английский интерфейс и свои роли
#' settings <- aa_settings(
#'   max_failed_logins = 3,
#'   lockout_minutes   = 30,
#'   password_min      = 10,
#'   roles             = c("admin", "editor", "viewer"),
#'   texts             = aa_texts("en")
#' )
#' settings$lockout_minutes
aa_settings <- function(
    max_failed_logins            = 5,
    lockout_minutes              = 15,
    max_failed_logins_per_minute = 30,
    password_min                 = 6,
    password_max                 = 128,
    password_policy              = "warn",
    login_max                    = 64,
    autologin                    = TRUE,
    session_days                 = 30,
    session_check_seconds        = 30,
    attempts_retention_hours     = 24,
    token_retention_days         = 30,
    roles                        = c("admin", "user", "viewer"),
    admin_role                   = "admin",
    must_change_default          = TRUE,
    reset_enabled                = FALSE,
    send_reset                   = NULL,
    reset_base_url               = NULL,
    reset_ttl_minutes            = 60,
    reset_max_per_hour           = 3,
    reset_max_per_minute         = 10,
    totp_enabled                 = FALSE,
    totp_key                     = NULL,
    totp_issuer                  = "appauth",
    totp_window                  = 1,
    texts                        = aa_texts("ru")
) {
  aa_check_positive(max_failed_logins, "max_failed_logins")
  aa_check_positive(lockout_minutes, "lockout_minutes")
  aa_check_positive(max_failed_logins_per_minute, "max_failed_logins_per_minute")
  aa_check_positive(password_min, "password_min")
  aa_check_positive(password_max, "password_max")
  aa_check_positive(login_max, "login_max")
  aa_check_flag(autologin, "autologin")
  aa_check_flag(must_change_default, "must_change_default")
  aa_check_flag(reset_enabled, "reset_enabled")
  aa_check_positive(reset_ttl_minutes, "reset_ttl_minutes")
  aa_check_positive(reset_max_per_hour, "reset_max_per_hour")
  aa_check_positive(reset_max_per_minute, "reset_max_per_minute")
  aa_check_flag(totp_enabled, "totp_enabled")
  aa_check_positive(session_days, "session_days")
  aa_check_positive(session_check_seconds, "session_check_seconds")
  aa_check_positive(attempts_retention_hours, "attempts_retention_hours")
  aa_check_positive(token_retention_days, "token_retention_days")

  if (!(aa_is_string(password_policy) && password_policy %in% c("off", "warn", "reject"))) {
    rlang::abort(
      "Параметр `password_policy` должен быть одним из значений: \"off\", \"warn\", \"reject\".",
      class = "appauth_error_settings"
    )
  }

  if (!(is.null(send_reset) || is.function(send_reset))) {
    rlang::abort(
      "Параметр `send_reset` должен быть функцией `function(email, link, login)` или `NULL`.",
      class = "appauth_error_settings"
    )
  }

  if (!(is.null(reset_base_url) || aa_is_string(reset_base_url))) {
    rlang::abort(
      "Параметр `reset_base_url` должен быть строкой с адресом приложения или `NULL`.",
      class = "appauth_error_settings"
    )
  }

  if (reset_enabled && !(is.function(send_reset) && aa_is_string(reset_base_url))) {
    rlang::abort(
      "Для `reset_enabled = TRUE` нужны функция `send_reset` и адрес приложения `reset_base_url`.",
      class = "appauth_error_settings"
    )
  }

  if (!(is.null(totp_key) || (is.character(totp_key) && length(totp_key) == 1 && !is.na(totp_key)))) {
    rlang::abort(
      "Параметр `totp_key` должен быть строкой или `NULL`.",
      class = "appauth_error_settings"
    )
  }

  if (totp_enabled && !(aa_is_string(totp_key) && nchar(totp_key) >= 16)) {
    rlang::abort(
      "Для `totp_enabled = TRUE` нужен ключ шифрования `totp_key` (строка не короче 16 символов).",
      class = "appauth_error_settings"
    )
  }

  if (!aa_is_string(totp_issuer)) {
    rlang::abort(
      "Параметр `totp_issuer` должен быть непустой строкой.",
      class = "appauth_error_settings"
    )
  }

  if (!(is.numeric(totp_window) && length(totp_window) == 1 && is.finite(totp_window) &&
        totp_window >= 0 && totp_window <= 5 && totp_window == round(totp_window))) {
    rlang::abort(
      "Параметр `totp_window` должен быть целым числом от 0 до 5.",
      class = "appauth_error_settings"
    )
  }

  if (password_min > password_max) {
    rlang::abort(
      "Параметр `password_min` не может быть больше `password_max`.",
      class = "appauth_error_settings"
    )
  }

  if (!(is.character(roles) && length(roles) >= 1 && !anyNA(roles) &&
        all(nzchar(roles)) && !anyDuplicated(roles))) {
    rlang::abort(
      "Параметр `roles` должен быть вектором уникальных непустых строк.",
      class = "appauth_error_settings"
    )
  }

  if (!(aa_is_string(admin_role) && admin_role %in% roles)) {
    rlang::abort(
      "Параметр `admin_role` должен быть одной из ролей из `roles`.",
      class = "appauth_error_settings"
    )
  }

  if (!inherits(texts, "aa_texts")) {
    rlang::abort(
      "Параметр `texts` должен быть результатом `aa_texts()`.",
      class = "appauth_error_settings"
    )
  }

  structure(
    list(
      max_failed_logins            = max_failed_logins,
      lockout_minutes              = lockout_minutes,
      max_failed_logins_per_minute = max_failed_logins_per_minute,
      password_min                 = password_min,
      password_max                 = password_max,
      password_policy              = password_policy,
      login_max                   = login_max,
      autologin                    = autologin,
      session_days                 = session_days,
      session_check_seconds        = session_check_seconds,
      attempts_retention_hours     = attempts_retention_hours,
      token_retention_days         = token_retention_days,
      roles                        = roles,
      admin_role                   = admin_role,
      must_change_default          = must_change_default,
      reset_enabled                = reset_enabled,
      send_reset                   = send_reset,
      reset_base_url               = reset_base_url,
      reset_ttl_minutes            = reset_ttl_minutes,
      reset_max_per_hour           = reset_max_per_hour,
      reset_max_per_minute         = reset_max_per_minute,
      totp_enabled                 = totp_enabled,
      totp_key                     = totp_key,
      totp_issuer                  = totp_issuer,
      totp_window                  = totp_window,
      texts                        = texts
    ),
    class = "aa_settings"
  )
}

#' Настройки из списка (например, из раздела `config.yaml`)
#'
#' Удобно, когда настройки защиты хранятся в конфиге приложения. Берутся только
#' известные параметры [aa_settings()], остальные игнорируются, а любой параметр
#' можно переопределить аргументами `...`.
#'
#' @param x Список настроек, например `yaml::read_yaml("config.yaml")$security`,
#'   либо `NULL`.
#' @param ... Параметры [aa_settings()], которые заменяют значения из `x`.
#'
#' @returns Список настроек класса `aa_settings`.
#' @export
#'
#' @examples
#' security <- list(max_failed_logins = 3, lockout_minutes = 10, unknown_key = 1)
#' settings <- aa_settings_from_list(security, texts = aa_texts("en"))
#' settings$max_failed_logins
aa_settings_from_list <- function(x = NULL, ...) {
  if (!(is.null(x) || is.list(x))) {
    rlang::abort(
      "Первый аргумент должен быть списком настроек или `NULL`.",
      class = "appauth_error_settings"
    )
  }

  known <- setdiff(names(formals(aa_settings)), "texts")
  from_list <- if (is.null(x)) list() else x[intersect(names(x), known)]

  do.call(aa_settings, utils::modifyList(from_list, list(...)))
}

#' @export
print.aa_settings <- function(x, ...) {
  cat("Настройки appauth\n")
  cat("  Попыток входа до блокировки логина: ", x$max_failed_logins,
      " за ", x$lockout_minutes, " мин., блокировка на ", x$lockout_minutes, " мин.\n", sep = "")
  cat("  Общий лимит неудачных попыток: ", x$max_failed_logins_per_minute, " в минуту\n", sep = "")
  cat("  Длина нового пароля: от ", x$password_min, " до ", x$password_max, " символов\n", sep = "")
  cat("  Слабые пароли: ", switch(x$password_policy, off = "не проверяются", warn = "предупреждение", reject = "отклоняются"), "\n", sep = "")
  cat("  Автовход: ", if (x$autologin) "включён" else "выключен",
      ", срок токена ", x$session_days, " дн.\n", sep = "")
  cat("  Пароль от администратора: ", if (x$must_change_default) "временный (смена при входе)" else "постоянный",
      " по умолчанию\n", sep = "")
  cat("  Восстановление пароля по email: ",
      if (x$reset_enabled) paste0("включено, ссылка действует ", x$reset_ttl_minutes, " мин.") else "выключено",
      "\n", sep = "")
  cat("  Двухфакторная аутентификация: ", if (x$totp_enabled) "включена (добровольная)" else "выключена", "\n", sep = "")
  cat("  Роли: ", paste(x$roles, collapse = ", "),
      " (администратор: ", x$admin_role, ")\n", sep = "")
  cat("  Язык интерфейса: ", attr(x$texts, "lang"), "\n", sep = "")
  invisible(x)
}
