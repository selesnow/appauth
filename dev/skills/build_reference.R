# Generates the function reference for the package's AI agent skill.
#
# The reference is built from the installed package help (Rd), so it never diverges
# from the real signatures. Run after each package release:
#   Rscript dev/skills/build_reference.R <skill references folder>
#
# Output: api.md (index) and api-<topic>.md with the full help text of each function.

args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args) >= 1) args[1] else file.path(getwd(), "references")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

suppressMessages(library(appauth))
version <- as.character(packageVersion("appauth"))

groups <- list(
  list(
    file = "api-settings-texts.md",
    title = "Settings and texts",
    fns = c(
      "aa_settings",
      "aa_settings_from_list",
      "aa_texts",
      "aa_text",
      "aa_text_keys"
    )
  ),
  list(
    file = "api-database.md",
    title = "Database",
    fns = c(
      "aa_init_db",
      "aa_prepare_db",
      "aa_schema_version",
      "aa_cleanup",
      "aa_session_connection"
    )
  ),
  list(
    file = "api-passwords.md",
    title = "Passwords",
    fns = c(
      "aa_hash_password",
      "aa_verify_password",
      "aa_is_password_hash",
      "aa_validate_password",
      "aa_validate_login",
      "aa_migrate_plaintext_passwords",
      "aa_check_default_accounts",
      "aa_common_passwords",
      "aa_weak_password_warning"
    )
  ),
  list(
    file = "api-users.md",
    title = "Users",
    fns = c(
      "aa_get_user",
      "aa_list_users",
      "aa_users_exist",
      "aa_users_overview",
      "aa_create_user",
      "aa_create_first_admin",
      "aa_validate_new_user",
      "aa_authenticate",
      "aa_set_password",
      "aa_change_own_password",
      "aa_set_role",
      "aa_set_blocked",
      "aa_delete_user",
      "aa_check_can_block",
      "aa_check_can_delete",
      "aa_check_can_change_role"
    )
  ),
  list(
    file = "api-password-reset.md",
    title = "Password recovery by email",
    fns = c(
      "aa_set_email",
      "aa_get_email",
      "aa_request_password_reset",
      "aa_reset_token_login",
      "aa_reset_password_with_token"
    )
  ),
  list(
    file = "api-self-registration.md",
    title = "Self-registration",
    fns = c(
      "aa_register_user",
      "aa_registration_token_login",
      "aa_confirm_registration"
    )
  ),
  list(
    file = "api-two-factor.md",
    title = "Two-factor authentication (TOTP)",
    fns = c(
      "aa_totp_setup",
      "aa_totp_enable",
      "aa_totp_disable",
      "aa_totp_enabled",
      "aa_verify_second_factor",
      "aa_recovery_codes_left",
      "aa_totp_secret",
      "aa_totp_uri",
      "aa_totp_code"
    )
  ),
  list(
    file = "api-login-protection-sessions.md",
    title = "Login protection and sessions",
    fns = c(
      "aa_login_gate",
      "aa_record_attempt",
      "aa_login_lock_remaining",
      "aa_global_throttled",
      "aa_clear_attempts",
      "aa_issue_token",
      "aa_find_session_user",
      "aa_revoke_token",
      "aa_revoke_sessions",
      "aa_active_autologins",
      "aa_user_session_valid"
    )
  ),
  list(
    file = "api-permissions-events.md",
    title = "Permissions and events",
    fns = c(
      "aa_permissions_from_matrix",
      "aa_can",
      "aa_require",
      "aa_events",
      "aa_event_logger"
    )
  ),
  list(
    file = "api-modules.md",
    title = "UI modules and app helpers",
    fns = c(
      "aa_app_head",
      "aa_auth_ui",
      "aa_auth_server",
      "aa_users_ui",
      "aa_users_server",
      "aa_password_ui",
      "aa_password_server",
      "aa_totp_ui",
      "aa_totp_server",
      "aa_session_guard",
      "aa_register_module"
    )
  ),
  list(
    file = "api-skills.md",
    title = "AI agent skills",
    fns = c("aa_install_skills")
  )
)

exported <- sort(getNamespaceExports("appauth"))
listed <- unlist(lapply(groups, `[[`, "fns"))
stopifnot(
  "the reference lists functions that are not in the package" = all(
    listed %in% exported
  ),
  "the package exports functions missing from the reference" = all(
    exported %in% listed
  )
)

rd_db <- tools::Rd_db("appauth")

rd_text <- function(fn) {
  rd <- rd_db[[paste0(fn, ".Rd")]]
  stopifnot(!is.null(rd))
  tmp <- tempfile(fileext = ".txt")
  on.exit(unlink(tmp))
  tools::Rd2txt(
    rd,
    out = tmp,
    options = list(
      underline_titles = FALSE,
      width = 100,
      outputEncoding = "UTF-8"
    )
  )
  txt <- readLines(tmp, encoding = "UTF-8", warn = FALSE)
  txt[!nzchar(trimws(txt))] <- ""
  # drop trailing empty lines
  txt <- txt[nzchar(trimws(paste(txt, collapse = ""))) | TRUE]
  while (length(txt) && !nzchar(trimws(txt[length(txt)]))) {
    txt <- txt[-length(txt)]
  }
  txt
}

header <- function(title) {
  c(
    sprintf("# appauth reference: %s", title),
    "",
    sprintf(
      "Package version: %s. This file is generated automatically from the package help (`dev/skills/build_reference.R`) and must not be edited by hand.",
      version
    ),
    ""
  )
}

for (g in groups) {
  out <- header(g$title)
  out <- c(
    out,
    "Functions in this section: ",
    paste0("`", g$fns, "()`", collapse = ", "),
    "",
    "## Contents",
    "",
    vapply(
      g$fns,
      function(fn) sprintf("- [%s](#%s)", fn, fn),
      character(1)
    ),
    ""
  )
  for (fn in g$fns) {
    out <- c(out, sprintf("## %s", fn), "", "```text", rd_text(fn), "```", "")
  }
  writeLines(out, file.path(out_dir, g$file), useBytes = TRUE)
}

index <- c(
  "# appauth function reference (index)",
  "",
  sprintf(
    "Package version: %s. Read only the file you need for the task.",
    version
  ),
  "",
  "| Topic | File | Functions |",
  "| --- | --- | --- |",
  vapply(
    groups,
    function(g) {
      sprintf(
        "| %s | `%s` | %s |",
        g$title,
        g$file,
        paste0("`", g$fns, "`", collapse = ", ")
      )
    },
    character(1)
  )
)
writeLines(index, file.path(out_dir, "api.md"), useBytes = TRUE)

cat("reference created:", out_dir, "\n")
cat(
  "functions in the reference:",
  length(listed),
  " exported by the package:",
  length(exported),
  "\n"
)
