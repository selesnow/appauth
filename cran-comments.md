## Submission

This is a new submission of appauth 0.11.0.

appauth provides login, user management and access control for 'shiny'
applications. It stores users in 'SQLite' (the default), 'DuckDB',
'MySQL' / 'MariaDB' or 'PostgreSQL'. Version 0.11.0 adds optional
self-registration by one-time email link and automatic creation of
non-admin accounts on the first verified Google sign-in; both are off
by default and require explicit settings.

## Test environments

* Local: Windows Server 2022, R 4.6.1
* win-builder: R-release (4.6.2) and R-devel (2026-11-17 r90926 ucrt)

## R CMD check results

0 errors | 0 warnings | 1 note

* NOTE: "New submission" (CRAN incoming feasibility).

## Notes for the reviewer

* The default language of the user interface texts and messages is English.
  Russian texts are available through `aa_texts("ru")`. They are stored in
  `R/texts-ru.R` as `\u` escapes, so the R code is pure ASCII.
* The test suite runs on 'SQLite' by default. The other supported databases
  ('DuckDB', 'MySQL' / 'MariaDB', 'PostgreSQL') are tested only when the
  corresponding driver and server are available (see `tests/testthat/helper-db.R`),
  so no external service is needed to check the package on CRAN.
* The tests do not write outside the temporary directory.
  `aa_install_skills()` copies files only to the directory given by the user
  (or the current project) and refuses to overwrite existing files by default.
