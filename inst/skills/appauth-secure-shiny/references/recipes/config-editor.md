# Recipe: config.yaml outside git, appending missing settings, a config editor

The app's `config.yaml` holds settings that differ between copies (dev and prod): database paths, log toggles, the permission matrix, the `security` section. Rules:

* the production `config.yaml` is NOT kept in git (it is in `.gitignore`) and is not overwritten on deploy;
* secrets (tokens, passwords, keys) do not go into `config.yaml`; they live in environment variables or in separate files outside the repository;
* new app versions introduce new settings and permissions: they must appear in the existing config automatically without overwriting the owner's values.

## 1. Default settings and appending what is missing

```r
# create_config.R
default_config <- function() list(
  database_settings = list(app_data_base = "app.db"),
  logging = list(session_log = TRUE, action_log = TRUE, error_log = TRUE),
  security = list(                      # section for appauth::aa_settings_from_list(); anything unset comes from the package
    max_failed_logins = 5, lockout_minutes = 15, max_failed_logins_per_minute = 30,
    must_change_default = TRUE),
  access_matrix = list(Tasks = c("admin", "user", "viewer"), Run = c("admin", "user"), Access = "admin")
)

# appends to `current` the settings from `defaults` that are missing there; existing values are not changed
merge_missing_config <- function(current, defaults) {
  for (key in names(defaults)) {
    if (is.null(current[[key]])) {
      current[[key]] <- defaults[[key]]
    } else if (is.list(current[[key]]) && !is.null(names(current[[key]])) &&
               is.list(defaults[[key]]) && !is.null(names(defaults[[key]]))) {
      current[[key]] <- merge_missing_config(current[[key]], defaults[[key]])
    }
  }
  current
}

ensure_config <- function(path = "config.yaml") {
  defaults <- default_config()
  if (!file.exists(path)) {
    yaml::write_yaml(defaults, path, fileEncoding = "UTF-8"); return(defaults)
  }
  current <- yaml::read_yaml(path)
  merged <- merge_missing_config(current, defaults)
  if (!identical(current, merged)) yaml::write_yaml(merged, path, fileEncoding = "UTF-8")
  merged
}
```

In `app.R`: `source("create_config.R"); ensure_config("config.yaml"); conf <<- yaml::read_yaml("config.yaml")`.

## 2. Authentication settings from the config

Functions from `R/` look up `auth_settings` globally, so the assignment is global (`<<-`), and the build is tolerant of typos:

```r
build_auth_settings <- function(security) {
  tryCatch(
    aa_settings_from_list(security, texts = aa_texts("en")),
    error = function(e) {
      message("WARNING: invalid security section in config.yaml (", conditionMessage(e), "), defaults used")
      aa_settings(texts = aa_texts("en"))
    })
}
auth_settings <<- build_auth_settings(conf$security)
```

Roles can also be set in this section: `security: {roles: [owner, editor, viewer], admin_role: owner}`. A zero limit or text instead of a number makes `aa_settings()` raise an error: the app must not crash because of a typo, hence the fallback to default settings.

## 3. A config editor in the UI (administrator only)

The permission and log-toggle editors: recipes/permissions-matrix.md and recipes/logging-toggles.md. General editor rules:

* every save starts with `require_access_admin()` (the tab permission AND the administrator role);
* only known keys are changed (iterate over the names in the current config, not over `input`); new keys from the browser are not accepted;
* after a change, update the `reactiveVal` holding the config (`conf_rv(new_conf)`) and write the file (`yaml::write_yaml`);
* the change is written to the log (`Access config change`, `Logging config change`, `Database config change`);
* database paths in an editor are a risk: an administrator can point to any file. If you do not need a path editor, do not provide one.

## 4. Tests

```r
d <- default_config()
p <- tempfile(fileext = ".yaml"); ensure_config(p)
cur <- yaml::read_yaml(p); cur$access_matrix$Run <- "admin"; cur$security$max_failed_logins <- 3
yaml::write_yaml(cur, p)
out <- ensure_config(p)
expect_identical(out$access_matrix$Run, "admin")                  # custom values are not overwritten
expect_identical(out$security$max_failed_logins, 3)

old <- cur; old$security <- NULL; old$access_matrix$Access <- NULL; yaml::write_yaml(old, p)
out <- ensure_config(p)
expect_identical(out$security, d$security)                        # missing settings were appended
expect_identical(out$access_matrix$Access, d$access_matrix$Access)
```

Plus a consistency test: every permission used in the code (`user_can(...)`, `require_permission(...)`, `access_matrix$...`) is present in `default_config()$access_matrix`.
