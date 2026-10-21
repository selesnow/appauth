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
#' @param texts Тексты интерфейса, результат [aa_texts()].
#'
#' @returns Список настроек класса `aa_settings`.
#' @export
#'
#' @examples
#' # настройки по умолчанию
#' settings <- aa_settings()
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
    login_max                    = 64,
    autologin                    = TRUE,
    session_days                 = 30,
    session_check_seconds        = 30,
    attempts_retention_hours     = 24,
    token_retention_days         = 30,
    roles                        = c("admin", "user", "viewer"),
    admin_role                   = "admin",
    texts                        = aa_texts("ru")
) {
  aa_check_positive(max_failed_logins, "max_failed_logins")
  aa_check_positive(lockout_minutes, "lockout_minutes")
  aa_check_positive(max_failed_logins_per_minute, "max_failed_logins_per_minute")
  aa_check_positive(password_min, "password_min")
  aa_check_positive(password_max, "password_max")
  aa_check_positive(login_max, "login_max")
  aa_check_flag(autologin, "autologin")
  aa_check_positive(session_days, "session_days")
  aa_check_positive(session_check_seconds, "session_check_seconds")
  aa_check_positive(attempts_retention_hours, "attempts_retention_hours")
  aa_check_positive(token_retention_days, "token_retention_days")

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
      login_max                    = login_max,
      autologin                    = autologin,
      session_days                 = session_days,
      session_check_seconds        = session_check_seconds,
      attempts_retention_hours     = attempts_retention_hours,
      token_retention_days         = token_retention_days,
      roles                        = roles,
      admin_role                   = admin_role,
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
  cat("  Автовход: ", if (x$autologin) "включён" else "выключен",
      ", срок токена ", x$session_days, " дн.\n", sep = "")
  cat("  Роли: ", paste(x$roles, collapse = ", "),
      " (администратор: ", x$admin_role, ")\n", sep = "")
  cat("  Язык интерфейса: ", attr(x$texts, "lang"), "\n", sep = "")
  invisible(x)
}
