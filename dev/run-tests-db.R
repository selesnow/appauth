# Запуск тестов пакета на выбранной базе данных.
#
# Использование (из корня пакета):
#   Rscript dev/run-tests-db.R sqlite            # по умолчанию, без настройки
#   Rscript dev/run-tests-db.R duckdb            # нужен пакет duckdb
#   Rscript dev/run-tests-db.R mysql [фильтр]    # тестовая схема appauth_test на сервере из конфига rpup
#   Rscript dev/run-tests-db.R postgres [фильтр] # нужны APPAUTH_TEST_PG_* (см. ниже)
#
# Необязательный второй аргумент - фильтр по имени файла тестов (например, users).
#
# mysql: доступ берётся из конфига rpup (config.cfg, пароль расшифровывает rpup),
#   схема appauth_test должна существовать; тесты создают и удаляют таблицы ТОЛЬКО
#   в ней. Пароль нигде не печатается. Свои значения можно задать переменными
#   APPAUTH_TEST_MYSQL_HOST / PORT / USER / PASSWORD / DBNAME.
# postgres: задайте APPAUTH_TEST_PG_HOST, PORT, USER, PASSWORD, DBNAME пустой
#   тестовой базы. ВНИМАНИЕ: перед каждым тестом схема public этой базы пересоздаётся.

args <- commandArgs(trailingOnly = TRUE)
backend <- if (length(args) >= 1) tolower(args[1]) else "sqlite"
filter <- if (length(args) >= 2) args[2] else NULL

stopifnot(backend %in% c("sqlite", "duckdb", "mysql", "postgres"))

if (backend == "mysql" && !nzchar(Sys.getenv("APPAUTH_TEST_MYSQL_HOST"))) {
  suppressMessages(loadNamespace("rpup"))
  cfg_path <- file.path(getOption("pup.config_dir"), "config.cfg")
  cfg <- utils::read.table(cfg_path, sep = "=", comment.char = "#", stringsAsFactors = FALSE)
  value <- function(key) gsub('"', "", cfg$V2[cfg$V1 == key], fixed = TRUE)

  Sys.setenv(
    APPAUTH_TEST_MYSQL_HOST     = value("mysql_host"),
    APPAUTH_TEST_MYSQL_PORT     = value("mysql_port"),
    APPAUTH_TEST_MYSQL_USER     = value("mysql_user"),
    APPAUTH_TEST_MYSQL_PASSWORD = rpup::pup_decrypt_string(cfg$V2[cfg$V1 == "mysql_password"]),
    APPAUTH_TEST_MYSQL_DBNAME   = "appauth_test"
  )
}

Sys.setenv(APPAUTH_TEST_DB = backend)
options(testthat.summary.max_reports = 200)

suppressMessages(pkgload::load_all(".", quiet = TRUE))

res <- testthat::test_dir(
  "tests/testthat",
  filter = filter,
  reporter = "summary",
  stop_on_failure = FALSE,
  load_package = "none"
)

df <- as.data.frame(res)
cat(
  "\nБаза:", backend,
  "| тестов:", nrow(df),
  "| провалено:", sum(df$failed),
  "| ошибок:", sum(df$error),
  "| пропущено:", sum(df$skipped), "\n"
)

if (sum(df$failed) + sum(df$error) > 0) quit(status = 1)
