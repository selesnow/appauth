# Словари текстов интерфейса и сообщений пакета.
# Ключи в обоих словарях должны совпадать (это проверяет тест).

aa_texts_ru <- list(
  # форма входа
  login_title              = "Авторизация",
  login_label              = "Логин",
  password_label           = "Пароль",
  login_button             = "Войти",
  # окно создания первого администратора
  setup_title              = "Создание администратора",
  setup_hint               = "В приложении ещё нет пользователей. Первый созданный пользователь получает роль %s.",
  password_confirm_label   = "Подтвердите пароль",
  setup_button             = "Создать администратора",
  # сообщения при входе
  bad_credentials          = "Неверный логин или пароль",
  locked                   = "Слишком много неудачных попыток входа. Повторите через %d мин.",
  throttled                = "Слишком много попыток входа. Повторите через минуту.",
  blocked_user             = "Учётная запись заблокирована администратором. Обратитесь к администратору.",
  # проверка логина и пароля
  passwords_mismatch       = "Пароли не совпадают",
  password_empty           = "Пароль не может быть пустым",
  password_too_short       = "Пароль должен содержать минимум %d символов",
  password_too_long        = "Пароль должен содержать максимум %d символов",
  login_empty              = "Логин не может быть пустым",
  login_whitespace         = "Логин не должен начинаться или заканчиваться пробелом",
  login_too_long           = "Логин должен содержать максимум %d символов",
  # статусы пользователей в таблице
  status_blocked           = "Заблокирован администратором",
  status_locked            = "Вход заблокирован после неудачных попыток (ещё %d мин.)",
  # управление пользователями
  user_not_specified       = "Пользователь не указан",
  user_not_found           = "Пользователь не найден",
  user_exists              = "Пользователь уже существует",
  user_exists_case         = "Пользователь с таким логином уже существует (логины различаются только регистром)",
  invalid_role             = "Недопустимая роль",
  cannot_block_self        = "Нельзя заблокировать самого себя",
  cannot_block_last_admin  = "Нельзя заблокировать последнего активного администратора",
  cannot_delete_self       = "Нельзя удалить самого себя",
  cannot_delete_last_admin = "Нельзя удалить последнего активного администратора",
  cannot_change_last_admin_role = "Нельзя снять роль администратора у последнего активного администратора",
  # права доступа
  access_denied            = "Недостаточно прав для этого действия"
)

aa_texts_en <- list(
  # login form
  login_title              = "Authorization",
  login_label              = "Login",
  password_label           = "Password",
  login_button             = "Sign in",
  # first administrator setup
  setup_title              = "Create administrator",
  setup_hint               = "The application has no users yet. The first user you create gets the %s role.",
  password_confirm_label   = "Confirm password",
  setup_button             = "Create administrator",
  # sign-in messages
  bad_credentials          = "Incorrect login or password",
  locked                   = "Too many failed sign-in attempts. Try again in %d min.",
  throttled                = "Too many sign-in attempts. Try again in a minute.",
  blocked_user             = "The account has been blocked by an administrator. Please contact the administrator.",
  # login and password validation
  passwords_mismatch       = "Passwords do not match",
  password_empty           = "Password cannot be empty",
  password_too_short       = "Password must be at least %d characters long",
  password_too_long        = "Password must be at most %d characters long",
  login_empty              = "Login cannot be empty",
  login_whitespace         = "Login must not start or end with a space",
  login_too_long           = "Login must be at most %d characters long",
  # user statuses in the table
  status_blocked           = "Blocked by an administrator",
  status_locked            = "Sign-in is locked after failed attempts (%d min. left)",
  # user management
  user_not_specified       = "User is not specified",
  user_not_found           = "User not found",
  user_exists              = "User already exists",
  user_exists_case         = "A user with this login already exists (logins differ only in letter case)",
  invalid_role             = "Invalid role",
  cannot_block_self        = "You cannot block yourself",
  cannot_block_last_admin  = "You cannot block the last active administrator",
  cannot_delete_self       = "You cannot delete yourself",
  cannot_delete_last_admin = "You cannot delete the last active administrator",
  cannot_change_last_admin_role = "You cannot remove the administrator role from the last active administrator",
  # access control
  access_denied            = "You do not have permission to perform this action"
)

#' Тексты интерфейса и сообщений
#'
#' Возвращает набор текстов для выбранного языка. Любую строку можно заменить
#' своей, указав её название и новое значение. Тексты с подстановкой значений
#' содержат маркеры `%d` (число) и `%s` (строка), значения подставляет
#' [aa_text()].
#'
#' Доступные ключи можно посмотреть через [aa_text_keys()].
#'
#' @param lang Язык текстов: `"ru"` (по умолчанию) или `"en"`.
#' @param ... Свои тексты в виде `ключ = "строка"`, заменяют стандартные.
#'
#' @returns Именованный список строк класса `aa_texts`.
#' @export
#'
#' @examples
#' # английские тексты
#' texts <- aa_texts("en")
#'
#' # русские тексты со своим названием кнопки входа
#' texts <- aa_texts("ru", login_button = "Войти в систему")
#' texts$login_button
aa_texts <- function(lang = c("ru", "en"), ...) {
  lang <- rlang::arg_match(lang)
  base <- if (lang == "ru") aa_texts_ru else aa_texts_en

  overrides <- list(...)

  if (length(overrides) > 0) {
    nms <- names(overrides)

    if (is.null(nms) || any(is.na(nms) | !nzchar(nms))) {
      rlang::abort(
        "Свои тексты нужно передавать с названиями: `aa_texts(login_button = \"...\")`.",
        class = "appauth_error_texts"
      )
    }

    unknown <- setdiff(nms, names(base))
    if (length(unknown) > 0) {
      rlang::abort(
        paste0(
          "Неизвестные ключи текстов: ", paste(unknown, collapse = ", "),
          ". Список доступных ключей возвращает `aa_text_keys()`."
        ),
        class = "appauth_error_texts"
      )
    }

    not_string <- !vapply(overrides, aa_is_string, logical(1))
    if (any(not_string)) {
      rlang::abort(
        paste0(
          "Значения текстов должны быть непустыми строками, проверьте: ",
          paste(nms[not_string], collapse = ", "), "."
        ),
        class = "appauth_error_texts"
      )
    }

    base[nms] <- overrides
  }

  structure(base, class = "aa_texts", lang = lang)
}

#' Ключи текстов интерфейса
#'
#' @returns Вектор названий ключей, которые можно переопределить в [aa_texts()].
#' @export
#'
#' @examples
#' aa_text_keys()
aa_text_keys <- function() {
  names(aa_texts_ru)
}

#' Получить текст по ключу
#'
#' Возвращает строку из набора текстов. Если передать значения, они
#' подставляются в строку по правилам [sprintf()].
#'
#' @param x Набор текстов (результат [aa_texts()]) или настройки (результат
#'   [aa_settings()]).
#' @param key Ключ текста, см. [aa_text_keys()].
#' @param ... Значения для подстановки в маркеры `%d` и `%s`.
#'
#' @returns Строка.
#' @export
#'
#' @examples
#' texts <- aa_texts("ru")
#' aa_text(texts, "login_button")
#' aa_text(texts, "locked", 15)
aa_text <- function(x, key, ...) {
  if (inherits(x, "aa_settings")) {
    x <- x$texts
  }

  if (!inherits(x, "aa_texts")) {
    rlang::abort(
      "Первым аргументом должен быть результат `aa_texts()` или `aa_settings()`.",
      class = "appauth_error_texts"
    )
  }

  if (!aa_is_string(key) || !key %in% names(x)) {
    rlang::abort(
      paste0(
        "Неизвестный ключ текста: ", paste(key, collapse = ", "),
        ". Список доступных ключей возвращает `aa_text_keys()`."
      ),
      class = "appauth_error_texts"
    )
  }

  fmt <- x[[key]]
  args <- list(...)

  if (length(args) == 0) {
    return(fmt)
  }

  do.call(sprintf, c(list(fmt), args))
}

#' @export
print.aa_texts <- function(x, ...) {
  lang <- attr(x, "lang")
  cat("Тексты appauth, язык: ", if (is.null(lang)) "не указан" else lang,
      ", строк: ", length(x), "\n", sep = "")
  invisible(x)
}
