# Test layout

Tests for `R/{name}.R` normally live in `tests/testthat/test-{name}.R`.
A few historical files cover several source files or a whole release; the
mapping is kept here so that new tests can be placed next to similar ones.

| Source files | Test file |
| --- | --- |
| `R/mod-auth.R` | `test-mod-auth.R` |
| `R/mod-users.R`, card helpers | `test-mod-users.R`, `test-mod-card.R` |
| `R/mod-password.R`, `R/reset.R` | `test-password-change.R`, `test-password-reset.R` |
| `R/event-logger.R`, `R/events.R` | `test-events.R`, `test-release-0-3.R` |
| `R/appauth-package.R`, bundled skills | `test-package.R`, `test-skills.R` |
| `R/helpers.R`, `R/sessions.R` | `test-helpers.R`, `test-sessions.R` |
| `R/settings.R`, `R/texts.R`, `R/texts-ru.R` | `test-settings.R`, `test-texts.R` |
| `R/internal-db.R`, `R/utils.R`, `R/dialect.R` | `test-schema.R`, `test-dialect.R` |
| `R/passwords.R`, `R/protection.R`, `R/users.R` | `test-passwords.R`, `test-protection.R`, `test-users.R` |
| `R/google.R`, `R/totp.R` | `test-google.R`, `test-totp.R` |
| `R/skills.R` | `test-skills.R` |

Public API error texts are snapshotted in `test-error-messages.R`.
