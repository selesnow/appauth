# Skeleton: per-user permissions from the database (no matrix and no config.yaml)

The second template of the `appauth-secure-shiny` skill, for apps where permissions are NOT defined by a "permission -> roles" matrix but stored per user in a database table (`user_permissions`). Roles `owner`, `editor`, `viewer`, English interface.

What it shows:

* custom roles and a custom administrator role (`aa_settings(roles =, admin_role =)`), a permanent password set by the owner (`must_change_default = FALSE`);
* a custom permission source `function(user)` (`make_permission_provider()` in `R/auth_setup.R`): the owner gets all permissions and user management;
* a user-card slot: the "Permissions" block, the owner grants permissions with checkboxes (the role check is inside the slot handler itself);
* the server part of the "Users" tab is registered only for the `users` permission (`aa_register_module()`);
* protection of the Export action with the first line of the handler (`aa_require()`);
* sign-out and sign-out on all devices buttons with confirmation.

What is NOT here: `config.yaml`, `create_config.R`, a role permission editor, log toggles (events are written to the console, replace `log_auth_event()` with writing to your own log, see `recipes/logging-toggles.md`).

Run from the app folder: `Rscript -e "shiny::runApp('.', host = '127.0.0.1', port = 8803)"`.
Database: `app.db` (the path can be overridden with the `REPORTS_PORTAL_DB` environment variable). The first start on an empty database offers to create the first owner: create it yourself and immediately add a spare one (`recipes/first-admin.md`).

Test: `tests/test_auth_light.R` (a lightweight template for apps without `config.yaml`: loads the app as `runApp`, checks the permission source, denial of Export without the permission, the "Users" tab only for the owner, and that a non-owner cannot grant permissions). Run from the root: `Rscript --no-init-file --no-site-file tests/test_auth_light.R`.
Audit: `Rscript --no-init-file --no-site-file <skill>/scripts/audit_shiny_app.R .`

What to substitute for your own app: permission names (`APP_PERMISSIONS`), tabs and handlers instead of "Reports"/"Export", the cookie name (`cookie_name`), the title.
