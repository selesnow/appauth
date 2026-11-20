aa_home_dir <- function() {
  path.expand("~")
}

#' Install skills for AI agents
#'
#' The package ships two skills for AI agents (Claude Code, Codex and others),
#' written in English: `appauth` (function reference, database schema, events,
#' interface identifiers) and `appauth-secure-shiny` (adopting `appauth`,
#' migrating hand-written authentication, security audit of an application).
#' The function copies them from the installed package into the skills
#' directory of a project or of the user.
#'
#' @param path Directory to copy to. Computed from `agent` by default.
#' @param agent Which agent to copy for: `"claude"` (`.claude/skills`, Claude
#'   Code) or `"agents"` (`.agents/skills`, Codex, Posit Assistant and others).
#'   Ignored if `path` is set.
#' @param global Copy to the user's home directory (`~`) rather than to the
#'   current project.
#' @param overwrite Overwrite skills that are already installed (for example,
#'   after a package update).
#'
#' @returns An invisible vector of paths to the installed skills.
#' @export
#'
#' @examples
#' \dontrun{
#' # into the current project for Claude Code
#' aa_install_skills()
#'
#' # for Codex and Posit Assistant, overwriting after a package update
#' aa_install_skills(agent = "agents", overwrite = TRUE)
#' }
aa_install_skills <- function(
  path = NULL,
  agent = c("claude", "agents"),
  global = FALSE,
  overwrite = FALSE
) {
  agent <- rlang::arg_match(agent)
  aa_check_flag(global, "global")
  aa_check_flag(overwrite, "overwrite")

  if (is.null(path)) {
    base <- if (global) aa_home_dir() else "."
    path <- file.path(
      base,
      if (agent == "claude") ".claude" else ".agents",
      "skills"
    )
  } else if (
    !(is.character(path) && length(path) == 1 && !is.na(path) && nzchar(path))
  ) {
    rlang::abort(
      "`path` must be a string with a directory path.",
      class = "appauth_error_settings"
    )
  }

  source_dir <- system.file("skills", package = "appauth")
  skills <- list.dirs(source_dir, full.names = TRUE, recursive = FALSE)

  if (!nzchar(source_dir) || length(skills) == 0) {
    rlang::abort(
      "No skills found in the installed package (`inst/skills`).",
      class = "appauth_error_settings"
    )
  }

  dir.create(path, recursive = TRUE, showWarnings = FALSE)

  targets <- file.path(path, basename(skills))
  exists <- dir.exists(targets)

  if (any(exists) && !overwrite) {
    rlang::abort(
      c(
        paste0(
          "Skill already installed: ",
          paste0("`", targets[exists], "`", collapse = ", "),
          "."
        ),
        i = "Pass `overwrite = TRUE` to replace it."
      ),
      class = "appauth_error_settings"
    )
  }

  unlink(targets[exists], recursive = TRUE)

  ok <- file.copy(skills, path, recursive = TRUE)
  if (!all(ok)) {
    rlang::abort(
      paste0("Could not copy the skills to `", path, "`."),
      class = "appauth_error_settings"
    )
  }

  cli_msg <- paste0(
    "Skills installed: ",
    paste(basename(skills), collapse = ", "),
    " -> ",
    path
  )
  rlang::inform(cli_msg)

  invisible(targets)
}
