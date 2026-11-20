#!/usr/bin/env Rscript
# Self-check of the audit script: creates a deliberately bad app in a temporary folder and verifies
# that audit_shiny_app.R finds all problem types, while the skeleton from assets/app-skeleton finds nothing serious.
# Usage: Rscript audit_selftest.R   (exit code 0 if everything is fine)

script_dir <- dirname(normalizePath(
  sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]),
  winslash = "/"
))
audit <- file.path(script_dir, "audit_shiny_app.R")
skeleton <- normalizePath(
  file.path(script_dir, "..", "assets", "app-skeleton"),
  winslash = "/"
)
rscript <- file.path(R.home("bin"), "Rscript")

run_audit <- function(dir, ...) {
  out <- suppressWarnings(system2(
    rscript,
    c("--vanilla", shQuote(audit), shQuote(dir), ...),
    stdout = TRUE,
    stderr = TRUE
  ))
  list(out = out, status = attr(out, "status") %||% 0L)
}
`%||%` <- function(a, b) if (is.null(a)) b else a

fails <- 0L
chk <- function(name, cond) {
  ok <- isTRUE(cond)
  if (!ok) {
    fails <<- fails + 1L
  }
  cat(sprintf("%-92s %s\n", name, if (ok) "OK" else "!!! FAIL"))
}

# ----------------------------------------------------------------- bad app
bad <- file.path(tempdir(), "bad_app")
dir.create(bad, recursive = TRUE)
writeLines(
  c(
    'library(shiny); library(DBI)',
    'ui <- fluidPage(passwordInput("pw", "Password"), actionButton("login", "Sign in"), actionButton("delete_user", "Delete"))',
    'token <- "abcd1234efgh5678"',
    'gl <- "glpat-aaaaaaaaaaaaaaaaaaaaaaaa"',
    'server <- function(input, output, session) {',
    '  con <- dbConnect(RSQLite::SQLite(), "app.db")',
    '  user_role <<- "admin"',
    '  observeEvent(input$login, {',
    '    res <- dbGetQuery(con, paste0("SELECT * FROM users WHERE login = \'", input$user, "\' AND password = \'", input$pw, "\'"))',
    '    if (res$password == input$pw) showNotification("ok")',
    '    print(input$pw)',
    '  })',
    '  observeEvent(input$delete_user, { dbExecute(con, "DELETE FROM users WHERE login = ?", params = list(input$who)) })',
    '  observeEvent(input$run_cmd, { system(paste("cmd /c", input$cmd)) })',
    '  output$t <- DT::renderDataTable(DT::datatable(df, escape = FALSE))',
    '  output$dl <- downloadHandler(filename = function() "app.db", content = function(file) file.copy("app.db", file))',
    '  output$html <- renderUI(HTML(paste0("<b>", input$name, "</b>")))',
    '  x <- eval(parse(text = input$code))',
    '  if (input$user_role == "admin") 1',
    '  txt <- readLines(input$path)',
    '  h <- digest::digest(input$pw, algo = "md5")',
    '  dbExecute(con, "INSERT INTO users (login, password) VALUES (?, ?)", params = list(input$u, input$pw))',
    '}',
    'runApp(shinyApp(ui, server), host = "0.0.0.0")'
  ),
  file.path(bad, "app.R"),
  useBytes = TRUE
)
writeLines("PASSWORD=secret", file.path(bad, ".Renviron"))
writeLines("{}", file.path(bad, "auth_sa.json"))
writeLines("x", file.path(bad, "app.db"))
git <- Sys.which("git")
if (nzchar(git)) {
  system2(
    git,
    c("-C", shQuote(bad), "init", "-q"),
    stdout = FALSE,
    stderr = FALSE
  )
  system2(
    git,
    c("-C", shQuote(bad), "add", "-A"),
    stdout = FALSE,
    stderr = FALSE
  )
}

res <- run_audit(bad)
txt <- paste(res$out, collapse = "\n")
expected <- c(
  "OWN_AUTH",
  "SQL_CONCAT",
  "PLAINTEXT_PASSWORD",
  "SECRET_LOGGED",
  "GLOBAL_STATE",
  "USERS_SQL",
  "HANDLER_NO_CHECK",
  "SHELL_INPUT",
  "XSS_ESCAPE",
  "XSS_HTML",
  "DB_DOWNLOAD",
  "EVAL_INPUT",
  "ROLE_FROM_INPUT",
  "PATH_FROM_INPUT",
  "WEAK_HASH",
  "SECRET_IN_CODE",
  "DB_NOT_CLOSED",
  "PUBLIC_BIND"
)
if (nzchar(git)) {
  expected <- c(expected, "SECRET_FILE_IN_GIT")
}
for (id in expected) {
  chk(sprintf("bad app: found %s", id), grepl(paste0("\\] ", id, "\\b"), txt))
}
chk(
  "the secrets finding does not print the token value",
  !grepl("abcd1234efgh5678|glpat-aaaaaaaa", txt)
)
chk("the bad app has critical-level findings", grepl("\\[CRITICAL\\]", txt))
chk(
  "--fail-on=high exits with code 1 on the bad app",
  run_audit(bad, "--fail-on=high")$status == 1
)
chk(
  "--md prints Markdown",
  any(grepl("^# Shiny app security audit", run_audit(bad, "--md")$out))
)

# ----------------------------------------------------------------- good app (skeleton)
good <- run_audit(skeleton)
gtxt <- paste(good$out, collapse = "\n")
chk(
  "app-skeleton: no critical and high findings",
  !grepl("\\[(CRITICAL|HIGH)\\]", gtxt)
)
chk(
  "app-skeleton: appauth recognized, no custom authentication",
  grepl("appauth found", gtxt) && !grepl("OWN_AUTH", gtxt)
)
chk(
  "app-skeleton: --fail-on=high exits with code 0",
  run_audit(skeleton, "--fail-on=high")$status == 0
)

unlink(bad, recursive = TRUE)
cat(sprintf("\nSelf-check result: failures %d\n", fails))
if (fails > 0) {
  quit(save = "no", status = 1)
}
