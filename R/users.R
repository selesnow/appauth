# Пользователи: создание, первый администратор, вход по паролю, смена пароля и
# роли, блокировка, удаление и проверки допустимости действий.
#
# Правила, которые держат эти функции:
#  - логины сравниваются ТОЧНО (с учётом регистра), как в SQLite; для НОВЫХ
#    пользователей запрещён логин, который совпадает с существующим без учёта
#    регистра, существующие пары не трогаются;
#  - нельзя заблокировать или удалить самого себя и нельзя остаться без
#    активного (не заблокированного) администратора, в том числе сменой роли;
#  - сброс пароля и блокировка отзывают токены автовхода, удаление удаляет
#    токены и неудачные попытки входа логина.
#
# Функции действий (aa_create_user, aa_set_password, aa_set_role,
# aa_set_blocked, aa_delete_user) при нарушении правил прерываются ошибкой
# класса `appauth_error_user` с текстом на языке настроек; в поле `reason`
# лежит ключ причины из aa_text_keys(). Функции aa_check_* и aa_validate_*
# ничего не делают, а возвращают текст проблемы или NULL, их удобно
# использовать в интерфейсе.

#' Прервать действие с текстом проблемы
#'
#' @param settings Настройки, результат [aa_settings()].
#' @param problem Результат `aa_*_problem()`: список `reason` и `args`.
#' @param call Окружение для сообщения об ошибке.
#'
#' @noRd
aa_abort_problem <- function(settings, problem, call = rlang::caller_env()) {
  rlang::abort(
    aa_problem_text(settings, problem),
    class = "appauth_error_user",
    reason = problem$reason,
    call = call
  )
}

#' Пользователь по логину
#'
#' Логин сравнивается точно, с учётом регистра. Пароль в результат не
#' попадает.
#'
#' @param conn Подключение к базе SQLite (`DBI::dbConnect(RSQLite::SQLite(), ...)`).
#' @param login Логин.
#'
#' @returns Таблица из одной строки с колонками `login`, `role` и `blocked`
#'   либо `NULL`, если такого пользователя нет.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_get_user(conn, "boss")
#'   aa_get_user(conn, "nobody")
#'   DBI::dbDisconnect(conn)
#' }
aa_get_user <- function(conn, login) {
  aa_check_sqlite(conn)

  if (!aa_is_string(login)) {
    return(NULL)
  }

  user <- DBI::dbGetQuery(
    conn,
    "SELECT login, role, blocked FROM users WHERE login = ?",
    params = list(login)
  )

  if (nrow(user) == 0) NULL else user[1, , drop = FALSE]
}

#' Список пользователей
#'
#' @inheritParams aa_get_user
#'
#' @returns Таблица с колонками `login`, `role` и `blocked` в порядке создания.
#'   Хеши паролей в результат не попадают.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_list_users(conn)
#'   DBI::dbDisconnect(conn)
#' }
aa_list_users <- function(conn) {
  aa_check_sqlite(conn)

  DBI::dbGetQuery(conn, "SELECT login, role, blocked FROM users ORDER BY rowid")
}

#' Есть ли в базе хотя бы один пользователь
#'
#' Если пользователей нет, приложению нужно показать окно создания первого
#' администратора, это делает модуль входа пакета.
#'
#' @inheritParams aa_get_user
#'
#' @returns `TRUE` или `FALSE`.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_users_exist(conn)
#'   DBI::dbDisconnect(conn)
#' }
aa_users_exist <- function(conn) {
  aa_check_sqlite(conn)

  DBI::dbGetQuery(conn, "SELECT COUNT(*) AS n FROM users")$n > 0
}

#' Найти проблему в данных нового пользователя
#'
#' @inheritParams aa_create_user
#' @param check_password Проверять ли пароль.
#'
#' @returns `NULL` или список `reason` и `args`.
#' @noRd
aa_new_user_problem <- function(conn, login, password, role, settings, check_password = TRUE) {
  problem <- aa_login_problem(login, settings)
  if (!is.null(problem)) return(problem)

  if (check_password) {
    problem <- aa_password_problem(password, settings)
    if (!is.null(problem)) return(problem)
  }

  if (!(aa_is_string(role) && role %in% settings$roles)) {
    return(list(reason = "invalid_role", args = list()))
  }

  existing <- DBI::dbGetQuery(conn, "SELECT login FROM users")$login

  if (login %in% existing) {
    return(list(reason = "user_exists", args = list()))
  }

  # регистр сравниваем в R, так как lower() в SQLite не понимает кириллицу
  if (any(tolower(existing) == tolower(login))) {
    return(list(reason = "user_exists_case", args = list()))
  }

  NULL
}

#' Проверить данные нового пользователя
#'
#' Проверяет логин, пароль, роль и уникальность логина, ничего не создавая.
#' Подходит для показа ошибки в форме до создания пользователя.
#'
#' Логин считается занятым, если он совпадает с существующим точно или без учёта
#' регистра (так новые пользователи не создают пар вида `Kiruka` и `kiruka`).
#'
#' @inheritParams aa_create_user
#'
#' @returns `NULL`, если данные подходят, иначе текст проблемы (на языке настроек).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_validate_new_user(conn, "Boss", "another-password", "user")
#'   aa_validate_new_user(conn, "worker", "another-password", "user")
#'   DBI::dbDisconnect(conn)
#' }
aa_validate_new_user <- function(conn, login, password, role, settings = aa_settings()) {
  aa_check_sqlite(conn)

  aa_problem_text(settings, aa_new_user_problem(conn, login, password, role, settings))
}

#' Создать пользователя
#'
#' Создаёт пользователя с хешем пароля. Перед созданием проверяются логин,
#' пароль, роль (должна быть в `roles` из настроек) и уникальность логина.
#' При нарушении правил функция прерывается ошибкой класса `appauth_error_user`
#' с текстом на языке настроек (в поле `reason` ключ причины), который можно
#' показать пользователю.
#'
#' @inheritParams aa_get_user
#' @param password Пароль в открытом виде (в базу попадёт только хеш).
#' @param role Роль из списка `roles` настроек.
#' @param settings Настройки, результат [aa_settings()].
#'
#' @returns `TRUE` (невидимо).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_user(conn, "worker", "worker-password", "user")
#'   aa_list_users(conn)
#'
#'   # ошибку можно показать пользователю
#'   tryCatch(
#'     aa_create_user(conn, "worker", "another-password", "user"),
#'     appauth_error_user = function(e) conditionMessage(e)
#'   )
#'   DBI::dbDisconnect(conn)
#' }
aa_create_user <- function(conn, login, password, role, settings = aa_settings()) {
  aa_check_sqlite(conn)

  problem <- aa_new_user_problem(conn, login, password, role, settings)
  if (!is.null(problem)) aa_abort_problem(settings, problem)

  tryCatch(
    DBI::dbExecute(
      conn,
      "INSERT INTO users (login, password, role) VALUES (?, ?, ?)",
      params = list(login, aa_hash_password(password), role)
    ),
    error = function(e) {
      # при одновременном создании сработает ограничение уникальности логина
      if (grepl("UNIQUE", conditionMessage(e), fixed = TRUE)) {
        aa_abort_user(settings, "user_exists")
      }

      stop(e)
    }
  )

  invisible(TRUE)
}

#' Создать первого пользователя (администратора)
#'
#' Создаёт пользователя с ролью `admin_role` из настроек **только если
#' таблица `users` пуста**. Проверка и вставка выполняются одним SQL-запросом,
#' поэтому из двух одновременных запросов (две вкладки браузера, две сессии)
#' сработает только один.
#'
#' Логин и пароль проверяются по тем же правилам, что и в [aa_create_user()]
#' (при нарушении ошибка класса `appauth_error_user`).
#'
#' @inheritParams aa_create_user
#'
#' @returns `TRUE`, если администратор создан, `FALSE`, если пользователи уже есть.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_create_first_admin(conn, "second", "second-password")
#'   DBI::dbDisconnect(conn)
#' }
aa_create_first_admin <- function(conn, login, password, settings = aa_settings()) {
  aa_check_sqlite(conn)

  problem <- aa_login_problem(login, settings)
  if (is.null(problem)) problem <- aa_password_problem(password, settings)
  if (!is.null(problem)) aa_abort_problem(settings, problem)

  n <- DBI::dbExecute(
    conn,
    "INSERT INTO users (login, password, role)
     SELECT ?, ?, ?
     WHERE NOT EXISTS (SELECT 1 FROM users)",
    params = list(login, aa_hash_password(password), settings$admin_role)
  )

  n == 1
}

#' Проверить логин и пароль (вход)
#'
#' Ищет пользователя по логину (точно, с учётом регистра) и проверяет пароль по
#' хешу. Если пользователя нет, проверка всё равно выполняется на фиктивном
#' хеше, чтобы по времени ответа нельзя было понять, существует ли логин. Пароль
#' в открытом виде в базе никогда не принимается.
#'
#' Для пользователя, заблокированного администратором, при верном пароле
#' возвращается строка с `blocked = 1`: что делать дальше, решает вызывающий код
#' (модуль входа сообщает о блокировке только тому, кто знает пароль). При
#' неверном пароле результат всегда `NULL`.
#'
#' @inheritParams aa_get_user
#' @param password Введённый пароль.
#'
#' @returns Таблица из одной строки с колонками `login`, `role` и `blocked`
#'   (пароль в результат не попадает) либо `NULL`, если логин или пароль неверны.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_authenticate(conn, "boss", "boss-password")
#'   aa_authenticate(conn, "boss", "wrong")
#'   DBI::dbDisconnect(conn)
#' }
aa_authenticate <- function(conn, login, password) {
  aa_check_sqlite(conn)

  if (!aa_is_string(login) || !aa_is_string(password)) {
    return(NULL)
  }

  # колонка blocked появляется миграциями; если её по какой-то причине нет,
  # вход продолжает работать по паролю
  user <- tryCatch(
    DBI::dbGetQuery(
      conn,
      "SELECT login, role, password, blocked FROM users WHERE login = ?",
      params = list(login)
    ),
    error = function(e) {
      u <- DBI::dbGetQuery(
        conn,
        "SELECT login, role, password FROM users WHERE login = ?",
        params = list(login)
      )
      u$blocked <- 0L
      u
    }
  )

  if (nrow(user) != 1) {
    # пользователя нет: проверяем на фиктивном хеше, чтобы время ответа было тем же
    aa_verify_password(password, aa_dummy_hash())
    return(NULL)
  }

  if (!aa_verify_password(password, user$password[1])) {
    return(NULL)
  }

  user[, c("login", "role", "blocked"), drop = FALSE]
}

#' Задать пользователю новый пароль
#'
#' Записывает хеш нового пароля и **отзывает все токены автовхода**
#' пользователя, чтобы после сброса пароля старые сессии браузера перестали
#' работать. Пароль проверяется по правилам из настроек, при нарушении ошибка
#' класса `appauth_error_user`.
#'
#' @inheritParams aa_create_user
#'
#' @returns Число изменённых пользователей (невидимо): 1 или 0, если такого
#'   логина нет.
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_set_password(conn, "boss", "new-boss-password")
#'   aa_authenticate(conn, "boss", "new-boss-password")
#'   DBI::dbDisconnect(conn)
#' }
aa_set_password <- function(conn, login, password, settings = aa_settings()) {
  aa_check_sqlite(conn)

  problem <- aa_password_problem(password, settings)
  if (!is.null(problem)) aa_abort_problem(settings, problem)

  if (!aa_is_string(login)) {
    return(invisible(0L))
  }

  n <- DBI::dbExecute(
    conn,
    "UPDATE users SET password = ? WHERE login = ?",
    params = list(aa_hash_password(password), login)
  )

  if (n > 0) {
    aa_revoke_user_tokens(conn, login)
  }

  invisible(n)
}

#' Можно ли сменить пользователю роль
#'
#' Роль должна быть в списке `roles` настроек, а у **последнего активного
#' (не заблокированного) администратора** нельзя снять роль администратора,
#' иначе в приложении некому будет управлять пользователями.
#'
#' @inheritParams aa_create_user
#'
#' @returns `NULL`, если можно, иначе текст причины отказа (на языке настроек).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_check_can_change_role(conn, "boss", "user")
#'   DBI::dbDisconnect(conn)
#' }
aa_check_can_change_role <- function(conn, login, role, settings = aa_settings()) {
  aa_check_sqlite(conn)

  aa_problem_text(settings, aa_role_change_problem(conn, login, role, settings))
}

#' Найти проблему при смене роли
#'
#' @inheritParams aa_check_can_change_role
#'
#' @returns `NULL` или список `reason` и `args`.
#' @noRd
aa_role_change_problem <- function(conn, login, role, settings) {
  if (!aa_is_string(login)) {
    return(list(reason = "user_not_specified", args = list()))
  }

  if (!(aa_is_string(role) && role %in% settings$roles)) {
    return(list(reason = "invalid_role", args = list()))
  }

  user <- aa_get_user(conn, login)

  if (is.null(user)) {
    return(list(reason = "user_not_found", args = list()))
  }

  if (identical(user$role, settings$admin_role) && !identical(role, settings$admin_role) &&
      aa_active_admin_count(conn, settings, excluding = login) == 0) {
    return(list(reason = "cannot_change_last_admin_role", args = list()))
  }

  NULL
}

#' Сменить пользователю роль
#'
#' Роль должна быть в списке `roles` настроек, у последнего активного
#' администратора роль администратора снять нельзя (см.
#' [aa_check_can_change_role()]). При нарушении ошибка класса
#' `appauth_error_user`.
#'
#' Открытая сессия пользователя продолжает работать с прежней ролью до
#' ближайшей проверки живой сессии модулем входа, а при следующем входе роль
#' берётся из базы.
#'
#' @inheritParams aa_create_user
#'
#' @returns Число изменённых пользователей (невидимо).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_create_user(conn, "worker", "worker-password", "user")
#'   aa_set_role(conn, "worker", "viewer")
#'   aa_get_user(conn, "worker")
#'   DBI::dbDisconnect(conn)
#' }
aa_set_role <- function(conn, login, role, settings = aa_settings()) {
  aa_check_sqlite(conn)

  problem <- aa_role_change_problem(conn, login, role, settings)
  if (!is.null(problem)) aa_abort_problem(settings, problem)

  n <- DBI::dbExecute(
    conn,
    "UPDATE users SET role = ? WHERE login = ?",
    params = list(role, login)
  )

  invisible(n)
}

#' Найти проблему при блокировке или удалении
#'
#' @param action `"block"` или `"delete"`.
#' @inheritParams aa_check_can_block
#'
#' @returns `NULL` или список `reason` и `args`.
#' @noRd
aa_user_removal_problem <- function(conn, login, acting_login, settings, action) {
  if (!aa_is_string(login)) {
    return(list(reason = "user_not_specified", args = list()))
  }

  user <- aa_get_user(conn, login)

  if (is.null(user)) {
    return(list(reason = "user_not_found", args = list()))
  }

  if (!is.null(acting_login) && identical(login, acting_login)) {
    return(list(reason = paste0("cannot_", action, "_self"), args = list()))
  }

  # нельзя остаться без активных администраторов
  if (identical(user$role, settings$admin_role) &&
      aa_active_admin_count(conn, settings, excluding = login) == 0) {
    return(list(reason = paste0("cannot_", action, "_last_admin"), args = list()))
  }

  NULL
}

#' Можно ли заблокировать пользователя
#'
#' Нельзя заблокировать самого себя и последнего активного администратора.
#'
#' @inheritParams aa_get_user
#' @param acting_login Логин того, кто блокирует (текущий администратор), либо
#'   `NULL` (например, при вызове из скрипта).
#' @param settings Настройки, результат [aa_settings()].
#'
#' @returns `NULL`, если можно, иначе текст причины отказа (на языке настроек).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_check_can_block(conn, "boss", acting_login = "boss")
#'   DBI::dbDisconnect(conn)
#' }
aa_check_can_block <- function(conn, login, acting_login = NULL, settings = aa_settings()) {
  aa_check_sqlite(conn)

  aa_problem_text(settings, aa_user_removal_problem(conn, login, acting_login, settings, "block"))
}

#' Можно ли удалить пользователя
#'
#' Нельзя удалить самого себя и последнего активного администратора.
#'
#' @inheritParams aa_check_can_block
#'
#' @returns `NULL`, если можно, иначе текст причины отказа (на языке настроек).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_check_can_delete(conn, "boss", acting_login = "boss")
#'   DBI::dbDisconnect(conn)
#' }
aa_check_can_delete <- function(conn, login, acting_login = NULL, settings = aa_settings()) {
  aa_check_sqlite(conn)

  aa_problem_text(settings, aa_user_removal_problem(conn, login, acting_login, settings, "delete"))
}

#' Заблокировать или разблокировать пользователя
#'
#' Ручная блокировка закрывает пользователю вход (и по паролю, и по токену
#' автовхода) без удаления учётной записи, пока администратор не снимет её.
#' При блокировке **отзываются все токены автовхода** пользователя, а уже
#' открытая у него сессия закрывается при ближайшей проверке модулем входа.
#'
#' Блокировка выполняется только если [aa_check_can_block()] разрешает её
#' (нельзя заблокировать себя и последнего активного администратора), иначе
#' ошибка класса `appauth_error_user`. Разблокировка проверок не требует и
#' отозванные токены не восстанавливает, пользователю нужен новый вход.
#'
#' @inheritParams aa_check_can_block
#' @param blocked `TRUE` заблокировать, `FALSE` разблокировать.
#'
#' @returns Число изменённых пользователей (невидимо).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_create_user(conn, "worker", "worker-password", "user")
#'   aa_set_blocked(conn, "worker", TRUE, acting_login = "boss")
#'   aa_get_user(conn, "worker")
#'   aa_set_blocked(conn, "worker", FALSE)
#'   DBI::dbDisconnect(conn)
#' }
aa_set_blocked <- function(conn, login, blocked = TRUE, acting_login = NULL, settings = aa_settings()) {
  aa_check_sqlite(conn)
  aa_check_flag(blocked, "blocked")

  if (blocked) {
    problem <- aa_user_removal_problem(conn, login, acting_login, settings, "block")
    if (!is.null(problem)) aa_abort_problem(settings, problem)
  }

  if (!aa_is_string(login)) {
    return(invisible(0L))
  }

  n <- DBI::dbExecute(
    conn,
    "UPDATE users SET blocked = ? WHERE login = ?",
    params = list(as.integer(blocked), login)
  )

  if (n > 0 && blocked) {
    aa_revoke_user_tokens(conn, login)
  }

  invisible(n)
}

#' Удалить пользователя
#'
#' Удаляет запись пользователя, **его токены автовхода и неудачные попытки
#' входа**. Это важно: без удаления токенов человек, которому позже достанется
#' такой же логин, мог бы войти по cookie прежнего владельца.
#'
#' Удаление выполняется только если [aa_check_can_delete()] разрешает его
#' (нельзя удалить себя и последнего активного администратора), иначе ошибка
#' класса `appauth_error_user`. Открытая у пользователя сессия закрывается при
#' ближайшей проверке модулем входа.
#'
#' @inheritParams aa_check_can_block
#'
#' @returns Число удалённых пользователей (невидимо).
#' @export
#'
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
#'   aa_init_db(conn)
#'   aa_create_first_admin(conn, "boss", "boss-password")
#'   aa_create_user(conn, "worker", "worker-password", "user")
#'   aa_delete_user(conn, "worker", acting_login = "boss")
#'   aa_list_users(conn)
#'   DBI::dbDisconnect(conn)
#' }
aa_delete_user <- function(conn, login, acting_login = NULL, settings = aa_settings()) {
  aa_check_sqlite(conn)

  problem <- aa_user_removal_problem(conn, login, acting_login, settings, "delete")
  if (!is.null(problem)) aa_abort_problem(settings, problem)

  n <- DBI::dbExecute(conn, "DELETE FROM users WHERE login = ?", params = list(login))

  if (n > 0) {
    aa_delete_user_tokens(conn, login)
    # таблицы попыток входа может не быть, это не должно мешать удалению
    tryCatch(aa_clear_attempts(conn, login, settings), error = function(e) NULL)
  }

  invisible(n)
}
