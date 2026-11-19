#!/usr/bin/env Rscript
# Static security audit of a Shiny app (skill appauth-secure-shiny).
#
# Reads the app code and CHANGES NOTHING. Finds typical problems: custom authentication and plaintext
# passwords, SQL built by concatenation, commands run with user data, permissions enforced only in the UI,
# unescaped HTML, secrets in code and in git, unclosed connections and more.
# These are heuristics, not proof: every finding must be verified by eye (false positives are possible),
# and the absence of findings does not mean the app is secure.
#
# Usage:
#   Rscript audit_shiny_app.R <app folder> [--md] [--fail-on=critical|high|medium|none] [--include-tests]
#
#   --md              Markdown output (for a report)
#   --fail-on=LEVEL   exit code 1 if there are findings of this level or higher (default none: always 0)
#   --include-tests   also check the tests folder (skipped by default, like renv, .git, dev)
#
# Levels: critical (fix immediately), high (fix before release), medium (verify and fix),
# low and info (FYI).

args <- commandArgs(trailingOnly = TRUE)
flags <- args[grepl("^--", args)]
paths <- args[!grepl("^--", args)]

if (length(paths) != 1 || !dir.exists(paths[1])) {
  cat("Usage: Rscript audit_shiny_app.R <app folder> [--md] [--fail-on=critical|high|medium|none] [--include-tests]\n")
  quit(save = "no", status = 2)
}

app_dir <- normalizePath(paths[1], winslash = "/")
as_md <- "--md" %in% flags
include_tests <- "--include-tests" %in% flags
fail_on <- sub("^--fail-on=", "", flags[grepl("^--fail-on=", flags)])
fail_on <- if (length(fail_on)) fail_on[1] else "none"
levels_sev <- c("critical", "high", "medium", "low", "info")
stopifnot(fail_on %in% c(levels_sev, "none"))

# ---------------------------------------------------------------- files
skip_dirs <- c("renv", ".git", ".Rproj.user", "packrat", "node_modules", "dev", "doc", "Meta", "_snaps", "rsconnect")
if (!include_tests) skip_dirs <- c(skip_dirs, "tests")

all_files <- list.files(app_dir, pattern = "[.](R|r|Rmd|rmd|qmd)$", recursive = TRUE, full.names = TRUE)
rel <- substring(all_files, nchar(app_dir) + 2)
keep <- !vapply(strsplit(rel, "/", fixed = TRUE), function(p) any(p[-length(p)] %in% skip_dirs), logical(1))
files <- all_files[keep]
rel <- rel[keep]

if (length(files) == 0) {
  cat("No R files to audit in the folder:", app_dir, "\n")
  quit(save = "no", status = 2)
}

read_file <- function(f) {
  x <- tryCatch(readLines(f, encoding = "UTF-8", warn = FALSE), error = function(e) character())
  iconv(x, "UTF-8", "UTF-8", sub = "?")
}
code <- lapply(files, read_file)
names(code) <- rel
is_comment <- lapply(code, function(x) grepl("^\\s*#", x))

# ---------------------------------------------------------------- findings
findings <- list()
add <- function(severity, id, file, line, message, snippet = "") {
  snippet <- trimws(gsub("\\s+", " ", snippet))
  if (nchar(snippet) > 140) snippet <- paste0(substr(snippet, 1, 137), "...")
  findings[[length(findings) + 1]] <<- data.frame(
    severity = severity, id = id, file = file, line = line, message = message, snippet = snippet,
    stringsAsFactors = FALSE
  )
}

# iterate over code lines without comments: fn(line, index, window of N lines downward)
scan_lines <- function(pattern, fn, window = 0, perl = TRUE) {
  for (f in rel) {
    x <- code[[f]]
    hit <- which(grepl(pattern, x, perl = perl) & !is_comment[[f]])
    for (i in hit) {
      win <- paste(x[i:min(length(x), i + window)], collapse = "\n")
      fn(f, i, x[i], win)
    }
  }
}

# the whole statement text: from line i to the closing of parentheses (but no more than max_lines lines), so that unrelated lines do not enter the window
stmt_text <- function(x, i, max_lines = 12) {
  depth <- 0
  out <- character()
  for (k in i:min(length(x), i + max_lines - 1)) {
    out <- c(out, x[k])
    plain <- gsub("\"([^\"\\\\]|\\\\.)*\"|'([^'\\\\]|\\\\.)*'", "", x[k])
    depth <- depth + lengths(regmatches(plain, gregexpr("[(]", plain))) - lengths(regmatches(plain, gregexpr("[)]", plain)))
    if (depth <= 0) break
  }
  paste(out, collapse = "\n")
}

scan_stmt <- function(pattern, fn, max_lines = 12) {
  for (f in rel) {
    x <- code[[f]]
    for (i in which(grepl(pattern, x, perl = TRUE) & !is_comment[[f]])) fn(f, i, x[i], stmt_text(x, i, max_lines))
  }
}

has <- function(text, pattern) grepl(pattern, text, perl = TRUE, ignore.case = TRUE)

all_text <- paste(unlist(code), collapse = "\n")
uses_appauth <- has(all_text, "\\bappauth\\b|\\baa_auth_server\\b")
own_form <- has(all_text, "passwordInput\\s*\\(")

# 1. custom authentication instead of appauth
if (own_form && !uses_appauth) {
  scan_lines("passwordInput\\s*\\(", function(f, i, line, win) {
    add("high", "OWN_AUTH", f, i, "Custom login form (passwordInput) without the appauth package: passwords, lockouts and sessions should be handled by appauth (skill appauth-secure-shiny).", line)
  })
}
if (!own_form && !uses_appauth && !has(all_text, "shinyauthr|shinymanager|check_credentials|auth0|keycloak|ShinyProxy")) {
  add("info", "NO_AUTH", ".", 0, "No authentication found in the app. If the app must be closed to the public, add it through appauth (skill appauth-secure-shiny).", "")
}

# 2. SQL built by concatenation
sql_kw <- "\\b(SELECT|INSERT\\s+INTO|UPDATE|DELETE\\s+FROM|WHERE)\\b"
scan_stmt("(dbGetQuery|dbExecute|dbSendQuery|dbSendStatement)\\s*\\(", function(f, i, line, win) {
  safe <- has(win, "glue_sql|sqlInterpolate|dbQuoteString|dbQuoteIdentifier|dbBind")
  built <- has(win, "\\b(paste0?|sprintf|glue|str_glue|gsub)\\s*\\(") && has(win, sql_kw)
  if (built && !safe) {
    if (has(win, "input\\$")) {
      add("high", "SQL_CONCAT", f, i, "SQL is built by concatenation with a value from input: SQL injection. Use parameters: dbGetQuery(con, \"... WHERE x = ?\", params = list(value)).", win)
    } else {
      add("medium", "SQL_CONCAT", f, i, "SQL is built by concatenation (paste/sprintf/glue). Make sure the values do not come from the user, and switch to params = list(...).", win)
    }
  }
})
scan_lines("\\b(paste0?|sprintf|glue|str_glue)\\s*\\(\\s*[\"'](SELECT|INSERT|UPDATE|DELETE)\\b", function(f, i, line, win) {
  if (!has(win, "glue_sql|sqlInterpolate|dbQuote")) {
    add(if (has(win, "input\\$")) "high" else "medium", "SQL_CONCAT", f, i, "An SQL string is built by concatenation. Use parameterized queries (params = list(...)).", line)
  }
}, window = 4)

# 3. running commands
scan_stmt("\\b(system|system2|shell|shell\\.exec)\\s*\\(", function(f, i, line, win) {
  if (has(win, "input\\$")) {
    add("high", "SHELL_INPUT", f, i, "A command is built from an input value. Allow only whitelisted values and pass arguments as a vector (system2).", win)
  } else if (has(win, "\\b(paste0?|glue|sprintf|str_glue)\\s*\\(") && !has(line, "system2")) {
    add("medium", "SHELL_INPUT", f, i, "A command is built by string concatenation. Check the data source, use system2 with an argument vector and a whitelist of values.", win)
  }
})

# 4. plaintext passwords and weak hashing
scan_lines("(\\$password|\\[\\[\"password\"\\]\\]|\\bpassword_db\\b|\\bstored_pass\\w*)\\s*(==|!=)|(==|!=)\\s*[A-Za-z_.]+\\$password|identical\\s*\\([^)]*\\$password", function(f, i, line, win) {
  inputs <- lengths(regmatches(line, gregexpr("input\\$", line)))
  if (!has(line, "verify|sodium|scrypt|bcrypt|argon|aa_") && inputs < 2) {
    add("critical", "PLAINTEXT_PASSWORD", f, i, "The password is compared directly (plaintext password in the database). Store only hashes and verify through appauth::aa_verify_password() or aa_authenticate().", line)
  }
})
scan_lines("WHERE[^\"']*\\bpassword\\s*=", function(f, i, line, win) {
  add("critical", "PLAINTEXT_PASSWORD", f, i, "The password is compared in SQL (WHERE password = ...): it is therefore stored as plain text. Use hashes and appauth::aa_authenticate().", line)
})
scan_lines("INSERT\\s+INTO\\s+users", function(f, i, line, win) {
  if (has(win, "password") && !has(win, "hash|store|sodium|scrypt|bcrypt|argon|digest|\\baa_")) {
    add("high", "PLAINTEXT_PASSWORD", f, i, "A user is inserted into the users table with an unhashed password. Create users through appauth::aa_create_user().", win)
  }
}, window = 4)
scan_lines("\\b(md5|sha1|digest)\\s*\\(|digest::digest|openssl::(md5|sha1|sha256)\\s*\\(", function(f, i, line, win) {
  if (has(win, "password|passwd|\\bpwd\\b|\\bpass\\b") && !has(win, "scrypt|sodium::password_store|bcrypt|argon|token")) {
    add("high", "WEAK_HASH", f, i, "The password is hashed with a fast hash (md5, sha, digest): it is cracked in seconds. Use only scrypt (sodium) or appauth.", win)
  }
}, window = 3)

# 5. secrets in logs
scan_lines("\\b(message|print|cat|writeLines)\\s*\\([^#]*(input\\$(pw|pwd|pass[A-Za-z_.]*|[A-Za-z_.]*password[A-Za-z_.]*)\\b|\\bpassword\\b|\\btoken\\b|\\bsecret\\b|api_key)", function(f, i, line, win) {
  clean <- gsub("session\\$token|\"[^\"]*\"", "", line)    # session$token (the session identifier) and quoted texts do not count
  if (has(clean, "input\\$(pw|pwd|pass[A-Za-z_.]*|[A-Za-z_.]*password[A-Za-z_.]*)\\b|\\bpassword\\b|\\btoken\\b|\\bsecret\\b|api_key") && !has(line, "showNotification|passwordInput|textInput")) {
    add("medium", "SECRET_LOGGED", f, i, "A password, token or secret may end up in the console or a log. Do not print such values.", line)
  }
})

# 6. role from input
scan_lines("input\\$[A-Za-z_.]*role[^\\n]*(==|%in%)\\s*(c\\()?[\"'](admin|user|viewer|editor|owner)", function(f, i, line, win) {
  add("high", "ROLE_FROM_INPUT", f, i, "The role is compared against a value from input: it can be forged from the browser. Take the role from server-side state (auth$user()$role).", line)
})

# 7. global state for roles and users
scan_lines("^\\s*(user|role|login|logged|auth(?!_settings)|current_user|session_user|permission|is_admin)\\w*\\s*<<-", function(f, i, line, win) {
  add("medium", "GLOBAL_STATE", f, i, "A role or user is stored in a global variable (<<-): it is shared by all sessions, one session will see another's role. Use per-session state (auth$user()).", line)
})
scan_lines("assign\\s*\\([^)]*envir\\s*=\\s*(globalenv\\(\\)|\\.GlobalEnv)", function(f, i, line, win) {
  if (has(line, "role|user|login|auth|permission")) {
    add("medium", "GLOBAL_STATE", f, i, "User state is written to the global environment: shared by all sessions.", line)
  }
})

# 8. direct SQL on the users table
scan_lines("\\b(FROM|INTO|UPDATE|JOIN)\\s+users\\b|DELETE\\s+FROM\\s+users", function(f, i, line, win) {
  add(if (uses_appauth) "medium" else "high", "USERS_SQL", f, i,
      if (uses_appauth) "Direct SQL on the users table in an app that uses appauth: use the package functions (aa_get_user, aa_create_user, aa_set_role, ...), they enforce the rules and revoke tokens."
      else "Home-grown handling of the users table: move to appauth (passwords, lockouts, sessions, permissions).", line)
})

# 9. paths from input
scan_lines("\\b(readLines|readRDS|read\\.csv|read_csv|read_excel|file\\.remove|unlink|file\\.copy|file\\.rename|list\\.files|file\\.exists|writeLines|write\\.csv|saveRDS|dir\\.create|source)\\s*\\([^)]*input\\$", function(f, i, line, win) {
  if (!has(win, "normalizePath|safe_path|startsWith|basename\\s*\\(")) {
    add("medium", "PATH_FROM_INPUT", f, i, "A file path is taken from input without validation: `../` escapes the folder. Normalize the path and check that it is inside the allowed folder.", line)
  }
})

# 10. HTML and XSS
scan_lines("escape\\s*=\\s*FALSE", function(f, i, line, win) {
  add("high", "XSS_ESCAPE", f, i, "escape = FALSE outputs data as HTML: foreign text with markup will execute in the browser. Escape it or build tags through htmltools.", line)
})
scan_stmt("\\bHTML\\s*\\(\\s*(paste0?|glue|sprintf|str_glue)\\s*\\(", function(f, i, line, win) {
  if (has(win, "input\\$|\\$(login|username|user|name|comment|message|title|description|text)\\b")) {
    add(if (has(win, "input\\$")) "high" else "medium", "XSS_HTML", f, i, "HTML is built as a string from user data: XSS. Use tags$span()/tags$a() (they escape automatically) or htmltools::htmlEscape().", win)
  }
})

# 10b. user data in JavaScript
scan_stmt("\\b(runjs|shinyjs::runjs|evalq?)\\s*\\(|sendCustomMessage\\s*\\(", function(f, i, line, win) {
  if (has(line, "runjs") && has(win, "input\\$|\\b(paste0?|sprintf|glue)\\s*\\(") && has(win, "input\\$") ) {
    add("medium", "JS_INJECTION", f, i, "An input value is substituted into JavaScript (runjs): markup or quotes in the value will execute in the browser. Pass data through jsonlite::toJSON() or session$sendCustomMessage.", win)
  }
})
scan_lines("\\brunjs\\s*\\(\\s*(js_code|code|js|script)\\s*\\)", function(f, i, line, win) {
  prev <- code[[f]][max(1, i - 6):i]
  if (any(grepl("input\\$", prev)) && any(grepl("\\b(paste0?|sprintf|glue)\\s*\\(", prev))) {
    add("medium", "JS_INJECTION", f, i, "A JavaScript string is built from an input value and executed through runjs: escape the value (jsonlite::toJSON) or pass it through session$sendCustomMessage.", paste(prev, collapse = " "))
  }
})

# 11. eval(parse(text = ...))
scan_lines("\\beval\\s*\\(\\s*parse\\s*\\(\\s*text\\s*=", function(f, i, line, win) {
  add(if (has(win, "input\\$")) "critical" else "high", "EVAL_INPUT", f, i,
      "eval(parse(text = ...)) executes arbitrary code. With data from input this is remote code execution; avoid it without input too.", win)
}, window = 2)

# 12. database download
scan_lines("downloadHandler\\s*\\(", function(f, i, line, win) {
  if (has(win, "\\.(db|sqlite3?)\\b|dbname|app_data_base|database_settings") && has(win, "file\\.copy|readBin|file\\s*\\)")) {
    add("critical", "DB_DOWNLOAD", f, i, "The database file is downloadable from the UI: it contains the users, auth_sessions, login_attempts tables (hashes, tokens). Serve only the needed tables without authentication data.", win)
  }
}, window = 25)

# 13. secrets in code
secret_name <- "(password|passwd|pwd|secret|token|api[_.-]?key|apikey|private[_.-]?key|client[_.-]?secret|bot_token|_pat)"
scan_lines(paste0("\\b[A-Za-z_.]*", secret_name, "[A-Za-z_.]*\\s*(<-|=)\\s*[\"'][^\"']{8,}[\"']"), function(f, i, line, win) {
  name <- sub("^\\s*([A-Za-z_.]+).*", "\\1", line)
  value <- sub(".*(<-|=)\\s*[\"']([^\"']*)[\"'].*", "\\2", line)
  if (!has(name, "(_label|_text|_title|_hint|_message|_button|_placeholder|_field|_input|_name|_col|_column)$") &&
      !has(value, "\\s|^(Sys|input)") && grepl("^[A-Za-z0-9_+/=.:@!#$%^&*-]{8,}$", value) &&
      !has(line, "Sys\\.getenv|get_secret|keyring")) {
    add("high", "SECRET_IN_CODE", f, i, "Looks like a secret in code (password, token, key). Keep secrets in environment variables or outside the repository.", sub(value, "***", line, fixed = TRUE))
  }
})
scan_lines("glpat-[A-Za-z0-9_-]{15,}|ghp_[A-Za-z0-9]{30,}|xox[abpr]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|\"private_key\"\\s*:", function(f, i, line, win) {
  add("critical", "SECRET_IN_CODE", f, i, "The code contains a token or private key of a known format. Revoke it, replace it and remove it from git history.", "(value hidden)")
})

# 14. secret files in git
if (dir.exists(file.path(app_dir, ".git")) && nzchar(Sys.which("git"))) {
  tracked <- suppressWarnings(tryCatch(system2("git", c("-C", shQuote(app_dir), "ls-files"), stdout = TRUE, stderr = FALSE), error = function(e) character()))
  secret_re <- "(^|/)\\.Renviron$|(^|/)\\.env($|\\.)|\\.(pem|p12|pfx|key)$|id_rsa|(auth|service[_-]?account|credentials|client_secret)[^/]*\\.json$"
  for (t in tracked[grepl(secret_re, tracked, ignore.case = TRUE)]) {
    add("critical", "SECRET_FILE_IN_GIT", t, 0, "A file with secrets is in git. Remove it from the repository (git rm --cached), add it to .gitignore, and treat exposed secrets as compromised and rotate them: removal from history alone is not enough.", "")
  }
  for (t in tracked[grepl("\\.(db|sqlite3?)$", tracked, ignore.case = TRUE)]) {
    add("high", "SECRET_FILE_IN_GIT", t, 0, "A database file is in git: it may contain password hashes and tokens. Remove it from the repository and add it to .gitignore.", "")
  }
}

# 15. connections without closing
for (f in rel) {
  x <- code[[f]][!is_comment[[f]]]
  n_conn <- sum(grepl("\\bdbConnect\\s*\\(", x))
  n_close <- sum(grepl("\\bdbDisconnect\\s*\\(|onSessionEnded|on\\.exit|aa_session_connection|pool::|dbPool", x))
  if (n_conn > 0 && n_close == 0) {
    add("medium", "DB_NOT_CLOSED", f, which(grepl("\\bdbConnect\\s*\\(", code[[f]]) & !is_comment[[f]])[1],
        "dbConnect without closing: on Windows the connection holds the database file until the process stops. Use appauth::aa_session_connection() or onSessionEnded/on.exit.", "")
  } else if (n_conn > n_close && n_close > 0) {
    add("low", "DB_NOT_CLOSED", f, which(grepl("\\bdbConnect\\s*\\(", code[[f]]) & !is_comment[[f]])[1],
        sprintf("There are more dbConnect calls (%d) than places that close them (%d): check that every connection is closed.", n_conn, n_close), "")
  }
}

# 16. manual cookie, binding, SSL
scan_lines("document\\.cookie", function(f, i, line, win) {
  add("medium", "COOKIE_JS", f, i, "Manual cookie handling in JavaScript. For auto-login use aa_app_head() and aa_auth_server() (SameSite, Secure, token revocation).", line)
})
scan_lines("host\\s*=\\s*[\"']0\\.0\\.0\\.0[\"']", function(f, i, line, win) {
  add("low", "PUBLIC_BIND", f, i, "The app listens on all interfaces. Make sure an HTTPS proxy sits in front of it and the port is closed to the outside by a firewall.", line)
})
scan_lines("ssl_verifypeer\\s*=\\s*(0|FALSE)|verify\\s*=\\s*FALSE|ssl_verifyhost\\s*=\\s*(0|FALSE)", function(f, i, line, win) {
  add("medium", "INSECURE_SSL", f, i, "Certificate verification is disabled: server spoofing is possible.", line)
})

# 17. action handlers without a server-side permission check (syntax parsing)
action_name <- "(delete|remove|drop|save|update|run|start|stop|kill|restart|upload|reset|add|create|insert|execute|exec|submit|send|deploy|download|export|import|activate|deactivate|block|unblock|change|write|clear|apply|launch|trigger|install|commit|push|rename|move|copy)"
skip_name <- "(logout|login|theme|refresh|tab|search|filter|toggle|show|close|cancel|back|next|prev|help|info|sort|expand|collapse|open|view|select|modal|confirm_no)"
danger_op <- "\\b(dbExecute|dbWriteTable|dbSendStatement|dbAppendTable|dbRemoveTable|file\\.remove|unlink|file\\.copy|file\\.rename|writeLines|write\\.csv|write_csv|saveRDS|system2?|shell|shell\\.exec|source|POST|PUT|DELETE|PATCH|Sys\\.setenv|write_yaml|dir\\.create|download\\.file)\\s*\\("
check_re <- "aa_require|require_permission|require_access|require_[A-Za-z_]+\\s*\\(|aa_can|user_can|has_permission|check_permission|is_admin|can_[a-z_]+\\s*\\(|stopifnot\\([^)]*role|req\\([^)]*role|auth\\$user\\(\\)\\$role|\\$role\\s*(==|%in%)|admin_only"

walk <- function(e, f, depth = 0) {
  if (!is.call(e)) return(invisible())
  fn <- e[[1]]
  if (is.name(fn) && as.character(fn) == "observeEvent" && length(e) >= 3) {
    ev <- e[[2]]
    ev_txt <- paste(deparse(ev), collapse = " ")
    handler <- if (!is.null(names(e)) && "handlerExpr" %in% names(e)) e[["handlerExpr"]] else e[[3]]
    h_txt <- paste(deparse(handler), collapse = "\n")
    ids <- unique(regmatches(ev_txt, gregexpr("(?<=input\\$)[A-Za-z0-9_.]+|(?<=input\\[\\[\")[A-Za-z0-9_.]+", ev_txt, perl = TRUE))[[1]])
    for (id in ids) {
      if (has(id, skip_name)) next
      dangerous <- has(h_txt, danger_op)
      calls_action <- has(h_txt, "\\b(delete|remove|kill|start|stop|restart|create|update|set|run|exec)(_[A-Za-z_]+)?\\s*\\(")
      action_like <- has(id, paste0("(^|_|\\.)", action_name, "($|_|\\.)"))
      # a mutating operation in the handler body (or an action by name plus a call of an action function) without a permission check
      if ((dangerous || (action_like && calls_action)) && !has(h_txt, check_re)) {
        line <- which(grepl(paste0("observeEvent\\s*\\(\\s*input\\$", id, "\\b|observeEvent\\s*\\(\\s*input\\[\\[\"", id, "\"\\]\\]"), code[[f]]) & !is_comment[[f]])[1]
        add("medium", "HANDLER_NO_CHECK", f, if (is.na(line)) 0 else line,
            sprintf("The action handler input$%s performs mutating operations without a server-side permission check. It needs aa_require() as the first line (a hidden button is not protection).", id),
            paste0("observeEvent(input$", id, ", ...)"))
      }
    }
  }
  # empty arguments (x[, 1], switch(a, , b)) cannot be assigned to a variable, so access by index
  for (k in seq_along(e)) {
    if (is.call(e[[k]])) walk(e[[k]], f, depth + 1)
  }
}
for (k in seq_along(files)) {
  parsed <- tryCatch(parse(files[k], keep.source = FALSE, encoding = "UTF-8"), error = function(e) NULL)
  if (is.null(parsed)) {
    add("info", "PARSE_SKIPPED", rel[k], 0, "The file was not parsed (perhaps it is Rmd or code with a syntax error): the handler check is skipped for it.", "")
    next
  }
  for (e in parsed) walk(e, rel[k])
}

# ---------------------------------------------------------------- report
res <- if (length(findings)) do.call(rbind, findings) else
  data.frame(severity = character(), id = character(), file = character(), line = integer(), message = character(), snippet = character())
res <- res[!duplicated(res[, c("id", "file", "line")]), , drop = FALSE]
# collapse same-type findings in one file into one (with the number of places)
group_ids <- c("OWN_AUTH", "USERS_SQL", "COOKIE_JS", "SHELL_INPUT")
keep_rows <- rep(TRUE, nrow(res))
for (id in group_ids) for (f in unique(res$file[res$id == id])) {
  idx <- which(res$id == id & res$file == f & res$severity != "high" | res$id == id & res$file == f & id %in% c("OWN_AUTH", "USERS_SQL", "COOKIE_JS"))
  if (length(idx) > 1) {
    res$message[idx[1]] <- sprintf("%s (total places in the file: %d)", res$message[idx[1]], length(idx))
    keep_rows[idx[-1]] <- FALSE
  }
}
res <- res[keep_rows, , drop = FALSE]
res$severity <- factor(res$severity, levels = levels_sev)
res <- res[order(res$severity, res$file, res$line), , drop = FALSE]
counts <- table(res$severity)

title <- sprintf("Shiny app security audit: %s", app_dir)
note <- paste0("Files checked: ", length(files), ". Authentication: ",
               if (uses_appauth) "appauth found" else if (own_form) "custom login form" else "not found",
               ". These are heuristics: verify every finding, the absence of findings does not mean the app is secure.")

if (as_md) {
  cat("# ", title, "\n\n", note, "\n\n", sep = "")
  cat("| Level | Findings |\n| --- | --- |\n")
  for (s in levels_sev) cat(sprintf("| %s | %d |\n", s, counts[[s]]))
  cat("\n")
  for (s in levels_sev) {
    sub_res <- res[res$severity == s, , drop = FALSE]
    if (nrow(sub_res) == 0) next
    cat(sprintf("## %s (%d)\n\n", s, nrow(sub_res)))
    for (i in seq_len(nrow(sub_res))) {
      r <- sub_res[i, ]
      cat(sprintf("* **%s** `%s`%s: %s%s\n", r$id, r$file, if (r$line > 0) paste0(":", r$line) else "", r$message,
                  if (nzchar(r$snippet)) paste0("\n  `", gsub("`", "'", r$snippet), "`") else ""))
    }
    cat("\n")
  }
} else {
  cat(title, "\n", note, "\n\n", sep = "")
  cat(sprintf("Total: critical %d, high %d, medium %d, low %d, info %d\n\n", counts[["critical"]], counts[["high"]], counts[["medium"]], counts[["low"]], counts[["info"]]))
  for (i in seq_len(nrow(res))) {
    r <- res[i, ]
    cat(sprintf("[%s] %s  %s%s\n    %s\n", toupper(as.character(r$severity)), r$id, r$file, if (r$line > 0) paste0(":", r$line) else "", r$message))
    if (nzchar(r$snippet)) cat("    > ", r$snippet, "\n", sep = "")
  }
  if (nrow(res) == 0) cat("No findings.\n")
}

if (fail_on != "none") {
  limit <- match(fail_on, levels_sev)
  if (any(as.integer(res$severity) <= limit)) quit(save = "no", status = 1)
}
