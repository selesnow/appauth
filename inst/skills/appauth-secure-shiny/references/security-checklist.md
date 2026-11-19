# Security checklist for a Shiny app using appauth

Each item states HOW to verify it. Go through the checklist after implementation and before release; items that reference the script are checked with `Rscript <skill>/scripts/audit_shiny_app.R <app folder>` (static audit, changes nothing).

Contents: A. Passwords and login, B. Sessions, C. Permissions and handlers, D. Users, E. Data and input, F. Secrets and configuration, G. Deployment, H. Tests.

## A. Passwords and login

| # | Criterion | How to verify |
| --- | --- | --- |
| A1 | No plaintext passwords in the database | `appauth::aa_check_default_accounts(conn)` does not report the `plaintext` reason; in the `users` table every `password` starts with `$7$` |
| A2 | No weak passwords or passwords equal to the login (`root/root`, `tester/tester`) | `aa_check_default_accounts(conn)` returns an empty table |
| A3 | The login form and password check come from the package, nothing home-grown | audit: no `PLAINTEXT_PASSWORD`, `WEAK_HASH` findings; `app.R` contains `aa_auth_server()` |
| A4 | After a series of failures the login is locked, and the correct password does not let the user in while locked | `testServer` test or manually: 5 wrong passwords, then the correct one |
| A5 | The same message for a wrong password and a non-existent login | manually: login `ghost` and a wrong password of an existing user show the same text |
| A6 | Password and tokens do not reach logs or the console | audit: no `SECRET_LOGGED` findings; review `app.Rout` after login |
| A7 | If Google sign-in is enabled: the client secret is not in the repository, the redirect address is `https://` only, there is a `google_domains` list (or it is deliberately empty), incoming users have an email set | `.Renviron` is not in git; `aa_settings()` raises no errors; sign-in with an account from a foreign domain and with an account that has no user in the app is rejected |
| A8 | If password login is disabled (`password_login = FALSE`): it is rejected on the server, not just hidden, and the administrator's Google sign-in has been verified | `testServer` test: `login_btn` does not sign in; manual administrator sign-in through Google |

## B. Sessions

| # | Criterion | How to verify |
| --- | --- | --- |
| B1 | `aa_session_guard()` is wired in | the call is in `server`; after a user is blocked, their open session closes within 30 seconds |
| B2 | Sign-out revokes the token and clears the cookie | manually: sign out, reload the page: login form, no `appauth_token` cookie (or your own name) |
| B3 | Blocking, deletion, role change and password reset affect open sessions | `testServer` test with `session$elapse(35000)` or manually in two browsers |
| B4 | The auto-login cookie has `SameSite=Lax`, `Secure` on HTTPS, and every app on the host has its own name | DevTools: Application, Cookies; the `cookie_name` parameter |
| B5 | The role comes from `auth$user()`, not from `input` | audit: no `ROLE_FROM_INPUT` findings |

## C. Permissions and handlers

| # | Criterion | How to verify |
| --- | --- | --- |
| C1 | In EVERY action handler the first line is `aa_require()` (or a wrapper around it) | audit: no `HANDLER_NO_CHECK` findings; manual review of the `observeEvent` list |
| C2 | Server parts of tabs are registered only when the permission is held (`aa_register_module()`) | audit and review of `server`; under a role without the permission the tab has no server part |
| C3 | Permissions are read from a server-side source, not from `input` and not from browser state | code review |
| C4 | Test: without the permission the handler does not run (for every role lacking it) | `expect_error(aa_require(...), class = "shiny.silent.error")` and a check that there is no side effect |
| C5 | No global state for roles and users | audit: no `GLOBAL_STATE` findings |

## D. Users

| # | Criterion | How to verify |
| --- | --- | --- |
| D1 | User management only through `aa_users_server()` or package functions | audit: no SQL on the `users` table in app code (`USERS_SQL`) |
| D2 | A spare administrator exists | `aa_list_users(conn)`: at least two active users with the `admin_role` role |
| D3 | The first administrator is created by the owner right after deployment | `aa_users_exist(conn)` is `TRUE` before the app is opened to outsiders |
| D4 | Temporary passwords: the administrator sets the password with the "require change" checkbox (`must_change_default`) | manually: a new user sees the password-change form at first login |

## E. Data and input

| # | Criterion | How to verify |
| --- | --- | --- |
| E1 | App SQL is parameterized only (`params = list(...)`), with no `paste`/`glue` using user data | audit: no `SQL_CONCAT` findings |
| E2 | Commands run only from a whitelist and after validation (`system2` with an argument vector, names checked) | audit: no `SHELL_INPUT` findings |
| E3 | File paths from the user are normalized and checked against escaping the allowed folder | audit: no `PATH_FROM_INPUT` findings; recipes/handler-guards.md |
| E4 | No `escape = FALSE` in tables and no `HTML(paste(...))` with foreign data | audit: no `XSS_ESCAPE`, `XSS_HTML` findings |
| E5 | No `eval(parse(text = ...))` with user data | audit: no `EVAL_INPUT` findings |
| E6 | Database download from the UI does not serve the authentication tables | audit: no `DB_DOWNLOAD` findings; recipes/database-download.md |

## F. Secrets and configuration

| # | Criterion | How to verify |
| --- | --- | --- |
| F1 | The repository has no `.Renviron`, keys, `*.pem`, service-account json files, passwords or tokens in code | audit: no `SECRET_IN_CODE`, `SECRET_FILE_IN_GIT` findings |
| F2 | `config.yaml` with production values is not in git (or has no secrets), missing settings are appended at startup | recipes/config-editor.md; `git ls-files` |
| F3 | The database file is not in git nor in a synchronized folder, and only the app's account has rights to it | `git ls-files | grep .db`, review permissions |

## G. Deployment

| # | Criterion | How to verify |
| --- | --- | --- |
| G1 | The app is reachable only over HTTPS, the Shiny port is closed from outside | open via `https://`, firewall; recipes/cookie-and-https.md |
| G2 | Database connections are closed together with the session | audit: no `DB_NOT_CLOSED` findings; after sessions stop the database file can be renamed |
| G3 | Dependencies are pinned (`renv.lock` contains `appauth`), CI runs `renv::restore()` | `renv::status()`, the CI configuration |
| G4 | A database backup is set up and tested by restoring | manually |

## H. Tests

| # | Criterion | How to verify |
| --- | --- | --- |
| H1 | There is an end-to-end app test: the app loads INTO ITS OWN ENVIRONMENT (like `runApp`), the first administrator is created, the administrator tab is rendered | `eval(parse(text = app_code), envir = new.env(parent = globalenv()))`, check the tab contents as an administrator |
| H2 | Permission tests: every role sees its own tabs, a handler without the permission is rejected, the `access_denied` event is emitted | assets/tests/test_auth_smoke.R |
| H3 | A check in a real browser at least once before release (login, administrator tab, lockout, sign-out) | Playwright, see recipes/testing.md |

## Final decision

The app is ready for release if all "critical" items are closed (A1, A3, B1, B5, C1, C2, E1, E2, F1, G1) and there is a conscious decision on the rest (an accepted risk is recorded in the app's README).
