# Слой диалектов: всё, что отличается между базами данных.
#
# Пакет работает с SQLite (по умолчанию), DuckDB, MySQL / MariaDB и PostgreSQL.
# Чтобы остальной код не зависел от базы, различия собраны здесь:
#   * время считает R и передаёт параметром (строка UTC "ГГГГ-ММ-ДД ЧЧ:ММ:СС"),
#     поэтому в запросах нет datetime('now'), NOW() и подобного;
#   * обёртки aa_query() и aa_execute() подставляют плейсхолдеры нужного вида;
#   * типы колонок, автоинкремент и индексы описаны функциями ниже.
# Даты везде хранятся текстом UTC: так сравнение дат одинаково во всех базах,
# а работающие базы SQLite остаются совместимыми без переноса данных.

#' Поддерживаемые базы данных
#'
#' @returns Названия диалектов.
#' @noRd
aa_dialects <- function() c("sqlite", "duckdb", "mysql", "postgres")

#' Диалект базы по подключению
#'
#' @param conn Подключение DBI.
#'
#' @returns `"sqlite"`, `"duckdb"`, `"mysql"` (MySQL и MariaDB), `"postgres"`
#'   или `NA`, если база не поддерживается.
#' @noRd
aa_dialect <- function(conn) {
  if (inherits(conn, "SQLiteConnection")) {
    "sqlite"
  } else if (inherits(conn, "duckdb_connection")) {
    "duckdb"
  } else if (inherits(conn, "MariaDBConnection") || inherits(conn, "MySQLConnection")) {
    "mysql"
  } else if (inherits(conn, "PqConnection")) {
    "postgres"
  } else {
    NA_character_
  }
}

#' Проверка подключения к базе данных
#'
#' Подключение должно быть открытым и принадлежать одной из поддерживаемых баз:
#' SQLite (`RSQLite`), DuckDB (`duckdb`), MySQL / MariaDB (`RMariaDB`) или
#' PostgreSQL (`RPostgres`).
#'
#' @param conn Подключение к базе данных.
#' @param call Окружение для сообщения об ошибке.
#'
#' @returns Подключение (невидимо), либо ошибка класса `appauth_error_connection`.
#' @noRd
aa_check_conn <- function(conn, call = rlang::caller_env()) {
  if (is.na(aa_dialect(conn))) {
    rlang::abort(
      paste0(
        "Пакет appauth работает с базами SQLite, DuckDB, MySQL / MariaDB и PostgreSQL: ",
        "передайте подключение, созданное через `DBI::dbConnect()` с драйвером ",
        "RSQLite::SQLite(), duckdb::duckdb(), RMariaDB::MariaDB() или RPostgres::Postgres()."
      ),
      class = "appauth_error_connection",
      call = call
    )
  }

  if (!DBI::dbIsValid(conn)) {
    rlang::abort(
      "Подключение к базе данных закрыто, откройте его заново.",
      class = "appauth_error_connection",
      call = call
    )
  }

  invisible(conn)
}

#' Текущее время в UTC для записи в базу
#'
#' @param offset_seconds Сдвиг в секундах от текущего момента (может быть отрицательным).
#' @param now Момент, от которого считать (для тестов).
#'
#' @returns Строка `"ГГГГ-ММ-ДД ЧЧ:ММ:СС"` по UTC.
#' @noRd
aa_utc <- function(offset_seconds = 0, now = Sys.time()) {
  format(now + offset_seconds, "%Y-%m-%d %H:%M:%S", tz = "UTC")
}

#' Заменить плейсхолдеры `?` на вид, который понимает база
#'
#' PostgreSQL (RPostgres) принимает только `$1, $2, ...`, остальные базы `?`.
#' В запросах пакета знак `?` не встречается внутри строковых литералов.
#'
#' @param conn Подключение к базе.
#' @param sql Текст запроса с плейсхолдерами `?`.
#'
#' @returns Текст запроса.
#' @noRd
aa_prepare_sql <- function(conn, sql) {
  if (!identical(aa_dialect(conn), "postgres") || !grepl("?", sql, fixed = TRUE)) {
    return(sql)
  }

  pieces <- strsplit(paste0(sql, "\001"), "?", fixed = TRUE)[[1]]
  n <- length(pieces) - 1L

  out <- paste0(paste0(pieces[seq_len(n)], "$", seq_len(n), collapse = ""), pieces[n + 1L])
  sub("\001", "", out, fixed = TRUE)
}

#' Привести 64-битные целые к обычным числам
#'
#' `COUNT(*)` в PostgreSQL и MySQL возвращается как `integer64`, с которым
#' неудобно сравнивать и форматировать значения.
#'
#' @param x Таблица результата запроса.
#'
#' @returns Таблица, где `integer64` заменены на числа.
#' @noRd
aa_fix_integers <- function(x) {
  for (i in seq_along(x)) {
    if (inherits(x[[i]], "integer64")) {
      x[[i]] <- as.numeric(x[[i]])
    }
  }

  x
}

#' Выполнить запрос с результатом
#'
#' Обёртка над `DBI::dbGetQuery()`: плейсхолдеры в `?`, числа без `integer64`.
#'
#' @param conn Подключение к базе.
#' @param sql Текст запроса.
#' @param params Список параметров или `NULL`.
#'
#' @returns Таблица.
#' @noRd
aa_query <- function(conn, sql, params = NULL) {
  sql <- aa_prepare_sql(conn, sql)

  res <- if (is.null(params)) {
    DBI::dbGetQuery(conn, sql)
  } else {
    DBI::dbGetQuery(conn, sql, params = params)
  }

  aa_fix_integers(res)
}

#' Выполнить запрос без результата
#'
#' Обёртка над `DBI::dbExecute()`: плейсхолдеры в `?`.
#'
#' @inheritParams aa_query
#'
#' @returns Число затронутых строк.
#' @noRd
aa_execute <- function(conn, sql, params = NULL) {
  sql <- aa_prepare_sql(conn, sql)

  n <- if (is.null(params)) {
    DBI::dbExecute(conn, sql)
  } else {
    DBI::dbExecute(conn, sql, params = params)
  }

  as.integer(n)
}

#' Сколько строк подошло под условие обновления
#'
#' SQLite, DuckDB и PostgreSQL возвращают число найденных строк, а MySQL только
#' число изменённых: обновление тем же значением даёт 0. Для MySQL при нулевом
#' результате наличие пользователя проверяется отдельно.
#'
#' @param conn Подключение к базе.
#' @param n Число затронутых строк из `aa_execute()`.
#' @param login Логин, по которому шло обновление `users`.
#'
#' @returns Число подошедших строк (0 или 1).
#' @noRd
aa_rows_matched <- function(conn, n, login) {
  if (n > 0 || !identical(aa_dialect(conn), "mysql")) {
    return(n)
  }

  as.integer(aa_query(conn, "SELECT COUNT(*) AS n FROM users WHERE login = ?", params = list(login))$n)
}

#' Колонки таблицы (в нижнем регистре)
#'
#' @param conn Подключение к базе.
#' @param table Название таблицы.
#'
#' @returns Вектор названий колонок.
#' @noRd
aa_table_columns <- function(conn, table) {
  tolower(DBI::dbListFields(conn, table))
}

#' Нарушено ли ограничение уникальности
#'
#' @param e Ошибка, пойманная при записи.
#'
#' @returns `TRUE` или `FALSE`.
#' @noRd
aa_is_unique_violation <- function(e) {
  grepl(
    "UNIQUE|Duplicate entry|duplicate key|Duplicate key",
    conditionMessage(e),
    ignore.case = FALSE
  )
}

#' Порядок строк таблицы пользователей «по добавлению»
#'
#' @param conn Подключение к базе.
#'
#' @returns Выражение для `ORDER BY`.
#' @noRd
aa_users_order <- function(conn) {
  if ("id" %in% aa_table_columns(conn, "users")) {
    "id"
  } else if (identical(aa_dialect(conn), "sqlite")) {
    "rowid"
  } else {
    "login"
  }
}

#' Двоичная collation без игнорирования пробелов в конце
#'
#' Обычная `utf8mb4_bin` считает `"alsey"` и `"alsey "` равными (PAD SPACE), а логины
#' должны сравниваться точно. В MySQL 8 для этого есть `utf8mb4_0900_bin`, в MariaDB
#' `utf8mb4_nopad_bin`.
#'
#' @param conn Подключение к MySQL / MariaDB.
#'
#' @returns Название collation.
#' @noRd
aa_mysql_collation <- function(conn) {
  version <- DBI::dbGetQuery(conn, "SELECT VERSION() AS v")$v

  if (grepl("mariadb", version, ignore.case = TRUE)) "utf8mb4_nopad_bin" else "utf8mb4_0900_bin"
}

#' Типы колонок схемы для базы
#'
#' Логины, роли и хеши сравниваются точно (с учётом регистра), поэтому в MySQL,
#' где сравнение по умолчанию без учёта регистра, такие колонки создаются с
#' двоичной collation. Время хранится текстом UTC.
#'
#' @param conn Подключение к базе.
#'
#' @returns Список: `key` (короткий текст для логинов, ролей, хешей), `text`
#'   (произвольный текст), `ts` (колонка времени) и `ts_now` (колонка времени
#'   со значением по умолчанию «сейчас»).
#' @noRd
aa_col_types <- function(conn) {
  dialect <- aa_dialect(conn)

  key <- switch(
    dialect,
    sqlite   = "TEXT",
    mysql    = paste0("VARCHAR(255) CHARACTER SET utf8mb4 COLLATE ", aa_mysql_collation(conn)),
    "VARCHAR(255)"
  )

  ts <- if (dialect == "sqlite") "TEXT" else "VARCHAR(19)"

  now_default <- switch(
    dialect,
    sqlite   = "DEFAULT (datetime('now'))",
    mysql    = "DEFAULT (DATE_FORMAT(UTC_TIMESTAMP(), '%Y-%m-%d %H:%i:%s'))",
    postgres = "DEFAULT to_char(timezone('UTC', now()), 'YYYY-MM-DD HH24:MI:SS')",
    duckdb   = "DEFAULT (substr(CAST(timezone('UTC', now()) AS VARCHAR), 1, 19))"
  )

  list(
    key = key,
    text = "TEXT",
    ts = ts,
    ts_now = paste(ts, now_default)
  )
}

#' Описание колонки `id` с автоинкрементом
#'
#' Для DuckDB заодно создаёт последовательность таблицы.
#'
#' @param conn Подключение к базе.
#' @param table Название таблицы.
#'
#' @returns Строка с определением колонки для `CREATE TABLE`.
#' @noRd
aa_pk_column <- function(conn, table) {
  switch(
    aa_dialect(conn),
    sqlite   = "id INTEGER PRIMARY KEY AUTOINCREMENT",
    mysql    = "id INT AUTO_INCREMENT PRIMARY KEY",
    postgres = "id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY",
    duckdb   = {
      seq <- paste0("aa_seq_", table)
      DBI::dbExecute(conn, paste0("CREATE SEQUENCE IF NOT EXISTS ", seq))
      paste0("id INTEGER PRIMARY KEY DEFAULT nextval('", seq, "')")
    }
  )
}

#' Создать индекс, если его ещё нет
#'
#' MySQL не поддерживает `CREATE INDEX IF NOT EXISTS`, поэтому наличие индекса
#' проверяется отдельно.
#'
#' @param conn Подключение к базе.
#' @param name Название индекса.
#' @param table Название таблицы.
#' @param columns Колонки индекса (строка, через запятую).
#' @param unique Сделать индекс уникальным.
#'
#' @returns Невидимо `NULL`.
#' @noRd
aa_create_index <- function(conn, name, table, columns, unique = FALSE) {
  kind <- if (unique) "UNIQUE INDEX" else "INDEX"

  if (identical(aa_dialect(conn), "mysql")) {
    exists <- aa_query(
      conn,
      "SELECT COUNT(*) AS n FROM information_schema.statistics
       WHERE table_schema = DATABASE() AND table_name = ? AND index_name = ?",
      params = list(table, name)
    )$n

    if (exists == 0) {
      DBI::dbExecute(conn, sprintf("CREATE %s %s ON %s (%s)", kind, name, table, columns))
    }
  } else {
    DBI::dbExecute(
      conn,
      sprintf("CREATE %s IF NOT EXISTS %s ON %s (%s)", kind, name, table, columns)
    )
  }

  invisible(NULL)
}

#' Запрос «вставить, если такой строки ещё нет»
#'
#' @param conn Подключение к базе.
#' @param table Название таблицы.
#' @param columns Названия колонок.
#'
#' @returns Текст `INSERT` с плейсхолдерами `?`.
#' @noRd
aa_insert_ignore_sql <- function(conn, table, columns) {
  base <- sprintf(
    "INTO %s (%s) VALUES (%s)",
    table, paste(columns, collapse = ", "),
    paste(rep("?", length(columns)), collapse = ", ")
  )

  if (identical(aa_dialect(conn), "mysql")) {
    paste("INSERT IGNORE", base)
  } else {
    paste("INSERT", base, "ON CONFLICT DO NOTHING")
  }
}

#' Явное приведение параметра к тексту
#'
#' PostgreSQL не может определить тип параметра в списке `SELECT` без `INSERT`
#' колонок, поэтому в запросах вида `INSERT ... SELECT ?` параметр приводится
#' явно. Для остальных баз возвращается просто `?`.
#'
#' @param conn Подключение к базе.
#'
#' @returns Фрагмент запроса.
#' @noRd
aa_text_param <- function(conn) {
  if (identical(aa_dialect(conn), "postgres")) "CAST(? AS TEXT)" else "?"
}

#' Блокировка на время миграций
#'
#' Если несколько экземпляров приложения стартуют одновременно, схему должен
#' достраивать только один. MySQL: именованная блокировка на подключение;
#' PostgreSQL: консультативная блокировка внутри транзакции миграций (снимается
#' вместе с ней). SQLite и DuckDB блокируют файл сами.
#'
#' @param conn Подключение к базе.
#'
#' @returns Функция без аргументов, снимающая блокировку (для SQLite, DuckDB и
#'   PostgreSQL ничего не делает).
#' @noRd
aa_migration_lock <- function(conn) {
  dialect <- aa_dialect(conn)

  if (dialect == "mysql") {
    got <- aa_query(conn, "SELECT GET_LOCK('appauth_migrations', 60) AS ok")$ok

    if (!isTRUE(as.numeric(got) == 1)) {
      rlang::abort("Не удалось получить блокировку на миграции схемы.", class = "appauth_error_migration")
    }

    return(function() {
      try(DBI::dbGetQuery(conn, "SELECT RELEASE_LOCK('appauth_migrations')"), silent = TRUE)
    })
  }

  if (dialect == "postgres") {
    DBI::dbGetQuery(conn, "SELECT pg_advisory_xact_lock(7272741)")
  }

  function() invisible(NULL)
}
