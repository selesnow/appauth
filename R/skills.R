#' Установка навыков для ИИ-агентов
#'
#' В пакет входят два навыка для ИИ-агентов (Claude Code, Codex и других) на
#' английском языке: `appauth` (справочник функций, схема базы, события,
#' идентификаторы интерфейса) и `appauth-secure-shiny` (внедрение `appauth`,
#' перенос самописной авторизации, аудит безопасности приложения). Функция
#' копирует их из установленного пакета в каталог навыков проекта или
#' пользователя.
#'
#' @param path Каталог, куда копировать. По умолчанию рассчитывается по
#'   `agent`.
#' @param agent Для какого агента копировать: `"claude"` (`.claude/skills`,
#'   Claude Code) или `"agents"` (`.agents/skills`, Codex, Posit Assistant и
#'   другие). Игнорируется, если задан `path`.
#' @param global Копировать в домашний каталог пользователя (`~`), а не в
#'   текущий проект.
#' @param overwrite Перезаписывать уже установленные навыки (например, после
#'   обновления пакета).
#'
#' @returns Невидимый вектор путей к установленным навыкам.
#' @export
#'
#' @examples
#' \dontrun{
#' # в текущий проект для Claude Code
#' aa_install_skills()
#'
#' # для Codex и Posit Assistant, с обновлением после апдейта пакета
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
    base <- if (global) path.expand("~") else "."
    path <- file.path(base, if (agent == "claude") ".claude" else ".agents", "skills")
  } else if (!(is.character(path) && length(path) == 1 && !is.na(path) && nzchar(path))) {
    rlang::abort(
      "Параметр `path` должен быть строкой с путём к каталогу.",
      class = "appauth_error_settings"
    )
  }

  source_dir <- system.file("skills", package = "appauth")
  skills <- list.dirs(source_dir, full.names = TRUE, recursive = FALSE)

  if (!nzchar(source_dir) || length(skills) == 0) {
    rlang::abort(
      "В установленном пакете не найдены навыки (`inst/skills`).",
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
          "Навык уже установлен: ",
          paste0("`", targets[exists], "`", collapse = ", "), "."
        ),
        i = "Передайте `overwrite = TRUE`, чтобы заменить его."
      ),
      class = "appauth_error_settings"
    )
  }

  unlink(targets[exists], recursive = TRUE)

  ok <- file.copy(skills, path, recursive = TRUE)
  if (!all(ok)) {
    rlang::abort(
      paste0("Не удалось скопировать навыки в `", path, "`."),
      class = "appauth_error_settings"
    )
  }

  cli_msg <- paste0("Установлены навыки: ", paste(basename(skills), collapse = ", "), " -> ", path)
  rlang::inform(cli_msg)

  invisible(targets)
}
