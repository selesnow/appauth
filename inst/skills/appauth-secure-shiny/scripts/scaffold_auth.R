#!/usr/bin/env Rscript
# Preparation for adopting appauth in an app (skill appauth-secure-shiny).
#
# Does only safe things and OVERWRITES NOTHING without --force:
#   * creates R/auth_setup.R (settings from config.yaml, event hook, permission wrappers);
#   * creates config.security.example.yaml (the security and access_matrix sections to move into config.yaml);
#   * with --with-tests adds tests/helper.R and tests/test_auth_smoke.R (end-to-end test template);
#   * inspects the app and prints a list of manual steps.
# app.R is NOT edited automatically: it differs too much between apps, the developer makes the edits following the recipes.
#
# Usage:
#   Rscript scaffold_auth.R <app folder> [--force] [--with-tests]

args <- commandArgs(trailingOnly = TRUE)
flags <- args[grepl("^--", args)]
paths <- args[!grepl("^--", args)]

if (length(paths) != 1 || !dir.exists(paths[1])) {
  cat("Usage: Rscript scaffold_auth.R <app folder> [--force] [--with-tests]\n")
  quit(save = "no", status = 2)
}

force <- "--force" %in% flags
with_tests <- "--with-tests" %in% flags
app_dir <- normalizePath(paths[1], winslash = "/")

script_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]), winslash = "/"))
skeleton <- normalizePath(file.path(script_dir, "..", "assets", "app-skeleton"), winslash = "/")
tests_tpl <- normalizePath(file.path(script_dir, "..", "assets", "tests"), winslash = "/")
stopifnot("the skill has no assets/app-skeleton" = dir.exists(skeleton))

created <- character(); skipped <- character()

put <- function(from, to) {
  dest <- file.path(app_dir, to)
  dir.create(dirname(dest), showWarnings = FALSE, recursive = TRUE)
  if (file.exists(dest) && !force) {
    skipped <<- c(skipped, to)
  } else {
    file.copy(from, dest, overwrite = TRUE)
    created <<- c(created, to)
  }
}

put(file.path(skeleton, "R", "auth_setup.R"), "R/auth_setup.R")

# example config sections: taken from the skeleton's create_config.R
example_path <- file.path(app_dir, "config.security.example.yaml")
if (!file.exists(example_path) || force) {
  writeLines(c(
    "# Sections for the app's config.yaml (move them into the production config.yaml, which is not kept in git).",
    "# Unset security values are taken from the appauth package (?aa_settings).",
    "security:",
    "  max_failed_logins: 5            # failures before a login is locked",
    "  lockout_minutes: 15             # counting window and lockout duration, minutes",
    "  max_failed_logins_per_minute: 30  # global limit of failures across all logins",
    "  must_change_default: true       # a password set by the administrator is temporary by default",
    "",
    "# Permission matrix: permission -> roles. Permission names are arbitrary but must match the app code.",
    "access_matrix:",
    "  Tasks: [admin, user, viewer]",
    "  Run: [admin, user]",
    "  Access: admin"
  ), example_path, useBytes = TRUE)
  created <- c(created, "config.security.example.yaml")
} else {
  skipped <- c(skipped, "config.security.example.yaml")
}

if (with_tests) {
  put(file.path(tests_tpl, "helper.R"), "tests/helper.R")
  put(file.path(tests_tpl, "test_auth_smoke.R"), "tests/test_auth_smoke.R")
}

cat("App:", app_dir, "\n\n")
if (length(created)) cat("Created:\n", paste0("  ", created, "\n"), sep = "")
if (length(skipped)) cat("Already exists, left untouched (--force overwrites):\n", paste0("  ", skipped, "\n"), sep = "")

# ---------------------------------------------------------------- app checks
rfiles <- list.files(app_dir, pattern = "[.]R$", recursive = TRUE, full.names = TRUE)
rfiles <- rfiles[!grepl("/(renv|tests|\\.git)/", rfiles) & !grepl("/R/auth_setup\\.R$", rfiles)]   # the file we created does not take part in the check
text <- paste(unlist(lapply(rfiles, function(f) tryCatch(readLines(f, encoding = "UTF-8", warn = FALSE), error = function(e) character()))), collapse = "\n")

notes <- character()
if (grepl("passwordInput\\s*\\(", text) && !grepl("appauth", text)) notes <- c(notes, "The app has a custom login form (passwordInput): run the audit (audit_shiny_app.R), migration follows recipes/legacy-migration.md.")
if (grepl("INSERT\\s+INTO\\s+users|FROM\\s+users", text)) notes <- c(notes, "The code has SQL on the users table: users must be managed with appauth functions, the schema is completed by aa_init_db() (recipes/legacy-migration.md).")
lock <- file.path(app_dir, "renv.lock")
if (file.exists(lock)) {
  has_pkg <- grepl("\"appauth\"\\s*:", paste(readLines(lock, warn = FALSE), collapse = "\n"))
  if (!has_pkg) notes <- c(notes, "The project has renv.lock but it does not contain appauth: add an entry (SKILL.md of the appauth skill, section \"renv\"; do NOT use snapshot(packages=) on the main lock file).")
}
gi <- file.path(app_dir, ".gitignore")
if (!file.exists(gi) || !any(grepl("config\\.yaml", readLines(gi, warn = FALSE)))) notes <- c(notes, "config.yaml is not in .gitignore: the production config is not kept in git (recipes/config-editor.md).")
if (dir.exists(file.path(app_dir, ".git")) && nzchar(Sys.which("git"))) {
  tracked <- suppressWarnings(tryCatch(system2("git", c("-C", shQuote(app_dir), "ls-files"), stdout = TRUE, stderr = FALSE), error = function(e) character()))
  if (any(grepl("\\.(db|sqlite3?)$|(^|/)\\.Renviron$", tracked))) notes <- c(notes, "A database file or .Renviron is tracked in git: remove it (git rm --cached) and add it to .gitignore.")
}
if (length(notes)) cat("\nNotes:\n", paste0("  - ", notes, "\n"), sep = "")

cat("
Manual steps (app.R is not changed automatically), order as in SKILL.md:
  1. app.R: library(appauth); source R/auth_setup.R; globally auth_settings <<- build_auth_settings(conf$security)
     (globally: functions from R/ look it up in the global environment, while runApp() loads app.R into its own).
  2. Move the sections from config.security.example.yaml into config.yaml (and into create_config.R, if there is one).
  3. Database: aa_prepare_db(con, auth_settings) at startup, in server: conn <- aa_session_connection(path_to_database).
  4. UI: aa_app_head(), aa_auth_ui(\"auth\"); server: auth <- aa_auth_server(\"auth\", conn, auth_settings,
     on_event = log_auth_event, cookie_name = \"<your own name>\"); aa_session_guard(auth, conn, auth_settings).
  5. Tabs by permission (user_can), server parts through aa_register_module(), require_permission() in EVERY handler.
  6. Users tab: aa_users_ui()/aa_users_server() (administrator only).
  7. Plaintext passwords: aa_migrate_plaintext_passwords() while the app is stopped (recipes/legacy-migration.md).
  8. Tests: Rscript scaffold_auth.R <folder> --with-tests, then adjust tests/test_auth_smoke.R.
  9. Audit and checklist: Rscript audit_shiny_app.R <folder>; references/security-checklist.md.
Complete example: assets/app-skeleton.
")
