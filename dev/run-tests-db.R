# Run the package tests against the selected database.
#
# Usage (from the package root):
#   Rscript dev/run-tests-db.R sqlite            # default, no setup
#   Rscript dev/run-tests-db.R duckdb            # needs the duckdb package
#   Rscript dev/run-tests-db.R mysql [filter]    # needs APPAUTH_TEST_MYSQL_* (see below)
#   Rscript dev/run-tests-db.R postgres [filter] # needs APPAUTH_TEST_PG_* (see below)
#
# The optional second argument is a filter on the test file name (for example, users).
#
# mysql: set APPAUTH_TEST_MYSQL_HOST / PORT / USER / PASSWORD / DBNAME. The schema
#   (default appauth_test) must exist; the tests create and drop tables ONLY in it.
#   The password is never printed.
# postgres: set APPAUTH_TEST_PG_HOST, PORT, USER, PASSWORD, DBNAME of an empty
#   test database. WARNING: the public schema of this database is recreated before
#   each test.

args <- commandArgs(trailingOnly = TRUE)
backend <- if (length(args) >= 1) tolower(args[1]) else "sqlite"
filter <- if (length(args) >= 2) args[2] else NULL

stopifnot(backend %in% c("sqlite", "duckdb", "mysql", "postgres"))

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
  "\nDatabase:",
  backend,
  "| tests:",
  nrow(df),
  "| failed:",
  sum(df$failed),
  "| errors:",
  sum(df$error),
  "| skipped:",
  sum(df$skipped),
  "\n"
)

if (sum(df$failed) + sum(df$error) > 0) {
  quit(status = 1)
}
