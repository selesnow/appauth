# Shared helper for tests in the tests folder (simple checks without testthat).
# Run from the project root: Rscript tests/test_auth_smoke.R
# The tests work with temporary copies of the project and databases, the working app.db and config.yaml are not changed.
# Exit code 0 if all checks passed, otherwise 1.

.test_state <- new.env()
.test_state$fails <- 0L
.test_state$checks <- 0L

chk <- function(name, cond) {
  ok <- isTRUE(cond)
  .test_state$checks <- .test_state$checks + 1L
  if (!ok) {
    .test_state$fails <- .test_state$fails + 1L
  }
  cat(sprintf("%-90s %s\n", name, if (ok) "OK" else "!!! FAIL"))
  invisible(ok)
}

finish_tests <- function() {
  cat(sprintf(
    "\nChecks: %d, failures: %d\n",
    .test_state$checks,
    .test_state$fails
  ))
  if (.test_state$fails > 0L) {
    quit(save = "no", status = 1L)
  }
  invisible(TRUE)
}

temp_path <- function(name) file.path(tempdir(), name)
quiet <- function(x) invisible(x)
