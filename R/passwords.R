# Пароли: хеширование, проверка, правила, перенос из открытого вида.
#
# Пароли хранятся только в виде хеша scrypt (пакет sodium). Хеш содержит соль и
# параметры и начинается с префикса "$7$". Значение в колонке password, не
# являющееся хешем, никогда не проходит проверку: открытые пароли не
# сравниваются.

#' Хешировать пароль
#'
#' Возвращает хеш scrypt (пакет `sodium`) для хранения в базе. Хеш содержит
#' соль и параметры, поэтому два вызова с одним паролем дают разные строки, а
#' проверка выполняется функцией [aa_verify_password()]. Хеш необратим:
#' восстановить пароль из него нельзя.
#'
#' Правила длины пароля функция не проверяет, для этого есть
#' [aa_validate_password()].
#'
#' @param password Пароль, непустая строка.
#'
#' @returns Строка с хешем, начинающаяся с `$7$`.
#' @export
#'
#' @examples
#' hash <- aa_hash_password("secret-password")
#' substr(hash, 1, 3)
#' aa_verify_password("secret-password", hash)
aa_hash_password <- function(password) {
  if (!aa_is_string(password)) {
    rlang::abort(
      "Пароль должен быть непустой строкой.",
      class = "appauth_error_password"
    )
  }

  sodium::password_store(password)
}

#' Является ли значение хешем пароля
#'
#' Отличает хеш, созданный [aa_hash_password()], от пароля в открытом виде.
#' Функция векторизована, `NA` не считается хешем.
#'
#' @param x Вектор строк, например колонка `password` таблицы `users`.
#'
#' @returns Логический вектор той же длины.
#' @export
#'
#' @examples
#' aa_is_password_hash(c(aa_hash_password("secret"), "root", NA))
aa_is_password_hash <- function(x) {
  !is.na(x) & grepl("^\\$7\\$", x)
}

#' Проверить пароль по хешу
#'
#' Сравнивает введённый пароль с сохранённым хешем. Если сохранённое значение
#' не является хешем (например, пароль в открытом виде), результат всегда
#' `FALSE`: открытые пароли не сравниваются. Повреждённый хеш и некорректные
#' аргументы тоже дают `FALSE`, ошибки функция не бросает.
#'
#' @param password Введённый пароль.
#' @param stored Значение из колонки `password` таблицы `users`.
#'
#' @returns `TRUE` или `FALSE`.
#' @export
#'
#' @examples
#' hash <- aa_hash_password("secret")
#' aa_verify_password("secret", hash)
#' aa_verify_password("other", hash)
#'
#' # пароль в открытом виде не проходит проверку, даже если совпадает
#' aa_verify_password("root", "root")
aa_verify_password <- function(password, stored) {
  if (!aa_is_string(password)) {
    return(FALSE)
  }

  if (!(is.character(stored) && length(stored) == 1 && aa_is_password_hash(stored))) {
    return(FALSE)
  }

  isTRUE(tryCatch(sodium::password_verify(stored, password), error = function(e) FALSE))
}

# Хеш-заглушка для выравнивания времени проверки, когда пользователя не
# существует: проверка по нему занимает столько же, сколько по настоящему
# хешу, и по времени ответа нельзя понять, есть ли такой логин. Создаётся один
# раз за сессию R.
.aa_dummy <- new.env(parent = emptyenv())

#' Хеш-заглушка для выравнивания времени проверки
#'
#' @returns Строка с хешем (одна и та же в течение сессии R).
#' @noRd
aa_dummy_hash <- function() {
  if (is.null(.aa_dummy$hash)) {
    .aa_dummy$hash <- aa_hash_password("dummy-password-for-timing")
  }

  .aa_dummy$hash
}

#' Проверить новый пароль по правилам
#'
#' Проверяет пароль, который задаётся пользователю (при создании или сбросе).
#' Правила берутся из настроек: минимальная и максимальная длина считаются в
#' символах, а не в байтах. Ограничения действуют только для новых паролей,
#' уже существующие пароли не затрагиваются.
#'
#' @param password Проверяемый пароль.
#' @param settings Настройки, результат [aa_settings()].
#'
#' @returns `NULL`, если пароль подходит, иначе текст ошибки (на языке настроек).
#' @export
#'
#' @examples
#' aa_validate_password("abc")
#' aa_validate_password("long-enough-password")
#' aa_validate_password("abc", aa_settings(texts = aa_texts("en")))
aa_validate_password <- function(password, settings = aa_settings()) {
  if (!aa_is_string(password)) {
    return(aa_text(settings, "password_empty"))
  }

  n <- nchar(password, type = "chars")

  if (n < settings$password_min) {
    return(aa_text(settings, "password_too_short", as.integer(settings$password_min)))
  }

  if (n > settings$password_max) {
    return(aa_text(settings, "password_too_long", as.integer(settings$password_max)))
  }

  NULL
}

#' Проверить логин нового пользователя
#'
#' Логин не должен быть пустым (пробелы по краям не считаются) и не длиннее
#' `login_max` символов из настроек.
#'
#' @param login Проверяемый логин.
#' @param settings Настройки, результат [aa_settings()].
#'
#' @returns `NULL`, если логин подходит, иначе текст ошибки (на языке настроек).
#' @export
#'
#' @examples
#' aa_validate_login("alsey")
#' aa_validate_login("   ")
aa_validate_login <- function(login, settings = aa_settings()) {
  if (!(is.character(login) && length(login) == 1 && !is.na(login) && nzchar(trimws(login)))) {
    return(aa_text(settings, "login_empty"))
  }

  if (nchar(login, type = "chars") > settings$login_max) {
    return(aa_text(settings, "login_too_long", as.integer(settings$login_max)))
  }

  NULL
}

#' Перенести пароли из открытого вида в хеши
#'
#' Разовая миграция для приложений со старой самописной авторизацией, где
#' пароли в таблице `users` хранятся в открытом виде. Все значения колонки
#' `password`, не являющиеся хешами, заменяются хешами scrypt. Уже
#' хешированные пароли пропускаются, поэтому функцию можно запускать повторно.
#'
#' Порядок работы: перед изменениями делается резервная копия файла базы (если
#' есть что менять и `backup` не `FALSE`), все изменения выполняются одной
#' транзакцией, а каждый новый хеш проверяется по исходному паролю до записи.
#' При любой ошибке изменения откатываются. Пароли функция нигде не выводит.
#'
#' **Запускайте функцию при остановленном приложении.** Резервная копия
#' содержит пароли в открытом виде: удалите её после проверки (и убедитесь, что
#' её нет в синхронизируемых папках и в git). После миграции вход по старым
#' паролям работает, так как введённый пароль проверяется по новому хешу.
#'
#' @param db_path Путь к файлу базы данных SQLite.
#' @param backup `TRUE` (по умолчанию) - копия рядом с базой с именем
#'   `<база>.bak_<дата>`, строка - свой путь для копии, `FALSE` - без копии
#'   (не рекомендуется).
#' @param dry_run Если `TRUE`, ничего не менять, только показать, чьи пароли
#'   были бы перенесены.
#'
#' @returns Список (невидимо): `migrated` (логины, чьи пароли перенесены или
#'   были бы перенесены), `skipped` (логины, у которых пароль уже хеш),
#'   `backup` (путь к копии или `NA`), `dry_run`.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   db <- tempfile(fileext = ".db")
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), db)
#'   DBI::dbExecute(conn, "CREATE TABLE users (login TEXT, password TEXT, role TEXT)")
#'   DBI::dbExecute(conn, "INSERT INTO users VALUES ('alsey', 'plain-secret', 'admin')")
#'   DBI::dbDisconnect(conn)
#'
#'   # что будет перенесено
#'   aa_migrate_plaintext_passwords(db, dry_run = TRUE)
#'
#'   # выполнить без резервной копии (в примере; в работе копию оставляйте)
#'   aa_migrate_plaintext_passwords(db, backup = FALSE)
#' }
aa_migrate_plaintext_passwords <- function(db_path, backup = TRUE, dry_run = FALSE) {
  rlang::check_installed("RSQLite", reason = "для переноса паролей в хеши.")

  if (!(aa_is_string(db_path) && file.exists(db_path))) {
    rlang::abort(
      paste0("Файл базы данных не найден: ", paste(db_path, collapse = ", ")),
      class = "appauth_error_migration"
    )
  }

  aa_check_flag(dry_run, "dry_run")

  if (!(is.logical(backup) && length(backup) == 1 && !is.na(backup)) && !aa_is_string(backup)) {
    rlang::abort(
      "Параметр `backup` должен быть TRUE, FALSE или путём к файлу копии.",
      class = "appauth_error_migration"
    )
  }

  conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  if (!DBI::dbExistsTable(conn, "users")) {
    rlang::abort(
      "В базе нет таблицы `users`, переносить нечего.",
      class = "appauth_error_migration"
    )
  }

  # ключ строки это login (он уникален), колонки id в старых базах может не быть
  users <- DBI::dbGetQuery(conn, "SELECT login, password FROM users")
  is_hash <- aa_is_password_hash(users$password)
  to_migrate <- users[!is_hash, , drop = FALSE]

  result <- list(
    migrated = to_migrate$login,
    skipped  = users$login[is_hash],
    backup   = NA_character_,
    dry_run  = dry_run
  )

  if (dry_run || nrow(to_migrate) == 0) {
    return(invisible(result))
  }

  # резервная копия файла базы перед изменениями
  if (!identical(backup, FALSE)) {
    backup_path <- if (isTRUE(backup)) {
      paste0(db_path, ".bak_", format(Sys.time(), "%Y%m%d_%H%M%S"))
    } else {
      backup
    }

    if (!file.copy(db_path, backup_path)) {
      rlang::abort(
        paste0("Не удалось создать резервную копию: ", backup_path),
        class = "appauth_error_migration"
      )
    }

    result$backup <- backup_path
  }

  tryCatch(
    DBI::dbWithTransaction(conn, {
      for (i in seq_len(nrow(to_migrate))) {
        plain <- to_migrate$password[i]
        login <- to_migrate$login[i]

        if (!aa_is_string(plain)) {
          rlang::abort(paste0("У пользователя ", login, " пустой пароль."))
        }

        new_hash <- aa_hash_password(plain)

        # убеждаемся, что хеш соответствует исходному паролю до записи
        if (!aa_verify_password(plain, new_hash)) {
          rlang::abort(paste0("Хеш не прошёл проверку для ", login, "."))
        }

        DBI::dbExecute(
          conn,
          "UPDATE users SET password = ? WHERE login = ?",
          params = list(new_hash, login)
        )
      }
    }),
    error = function(e) {
      rlang::abort(
        paste0("Миграция отменена, изменения не применены: ", conditionMessage(e)),
        class = "appauth_error_migration",
        parent = e
      )
    }
  )

  if (!is.na(result$backup)) {
    rlang::inform(paste0(
      "Резервная копия базы содержит пароли в открытом виде: ", result$backup,
      ". Удалите её после проверки."
    ))
  }

  invisible(result)
}

#' Список распространённых слабых паролей
#'
#' Используется функцией [aa_check_default_accounts()] по умолчанию.
#'
#' @returns Вектор строк.
#' @export
#'
#' @examples
#' head(aa_common_passwords())
aa_common_passwords <- function() {
  c(
    "root", "admin", "administrator", "password", "passw0rd", "pass", "test",
    "tester", "user", "guest", "demo", "changeme", "welcome", "letmein",
    "qwerty", "qwerty123", "1234", "12345", "123456", "1234567", "12345678",
    "123456789", "1234567890", "111111", "000000", "abc123", "iloveyou"
  )
}

#' Найти учётные записи со слабыми паролями
#'
#' Гигиеническая проверка таблицы `users`: находит пользователей, у которых
#' пароль хранится в открытом виде, совпадает с логином (в нижнем и верхнем
#' регистре тоже) или входит в список распространённых слабых паролей. Проверка
#' идёт по хешам, пароли в открытом виде функция не показывает. Проверка может
#' занять несколько секунд на каждого пользователя из-за стойкого хеширования.
#'
#' Для одного пользователя может быть несколько строк результата, например, для
#' пароля `root` в открытом виде у логина `root`.
#'
#' @param conn Подключение к базе SQLite, в которой уже есть таблица `users`.
#' @param common Список слабых паролей для проверки, по умолчанию
#'   [aa_common_passwords()].
#'
#' @returns Таблица с колонками `login`, `role` и `reason`: `plaintext`
#'   (пароль хранится в открытом виде), `login_as_password` (пароль совпадает с
#'   логином) или `common_password` (пароль из списка слабых). Если таких
#'   пользователей нет, таблица пустая.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   DBI::dbExecute(
#'     conn, "INSERT INTO users (login, password, role) VALUES (?, ?, 'user')",
#'     params = list("tester", aa_hash_password("tester"))
#'   )
#'   aa_check_default_accounts(conn)
#'   DBI::dbDisconnect(conn)
#' }
aa_check_default_accounts <- function(conn, common = aa_common_passwords()) {
  aa_check_sqlite(conn)

  if (!(is.character(common) && !anyNA(common))) {
    rlang::abort(
      "Параметр `common` должен быть вектором строк.",
      class = "appauth_error_password"
    )
  }

  users <- DBI::dbGetQuery(conn, "SELECT login, role, password FROM users ORDER BY rowid")

  found <- list()
  add <- function(i, reason) {
    found[[length(found) + 1]] <<- data.frame(
      login = users$login[i], role = users$role[i], reason = reason,
      stringsAsFactors = FALSE
    )
  }

  for (i in seq_len(nrow(users))) {
    stored <- users$password[i]
    login  <- users$login[i]
    login_variants <- unique(c(login, tolower(login), toupper(login)))

    if (!aa_is_password_hash(stored)) {
      # пароль в открытом виде: это уже проблема, плюс смотрим, не слабый ли он
      add(i, "plaintext")

      if (!is.na(stored) && stored %in% login_variants) {
        add(i, "login_as_password")
      } else if (!is.na(stored) && stored %in% common) {
        add(i, "common_password")
      }

      next
    }

    if (any(vapply(login_variants, aa_verify_password, logical(1), stored = stored))) {
      add(i, "login_as_password")
    } else if (any(vapply(common, aa_verify_password, logical(1), stored = stored))) {
      add(i, "common_password")
    }
  }

  if (length(found) == 0) {
    return(data.frame(login = character(), role = character(), reason = character(),
                      stringsAsFactors = FALSE))
  }

  do.call(rbind, found)
}
