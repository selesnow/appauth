# Package index

## Package

- [`appauth`](https://alexey-seleznev.pro/appauth/reference/appauth-package.md)
  [`appauth-package`](https://alexey-seleznev.pro/appauth/reference/appauth-package.md)
  : appauth: Secure Authentication and User Management for Shiny

## Settings and texts

- [`aa_settings()`](https://alexey-seleznev.pro/appauth/reference/aa_settings.md)
  : Authorization settings

- [`aa_settings_from_list()`](https://alexey-seleznev.pro/appauth/reference/aa_settings_from_list.md)
  :

  Settings from a list (for example, from a `config.yaml` section)

- [`aa_texts()`](https://alexey-seleznev.pro/appauth/reference/aa_texts.md)
  : Interface and message texts

- [`aa_text()`](https://alexey-seleznev.pro/appauth/reference/aa_text.md)
  : Get a text by key

- [`aa_text_keys()`](https://alexey-seleznev.pro/appauth/reference/aa_text_keys.md)
  : Interface text keys

## Database

- [`aa_init_db()`](https://alexey-seleznev.pro/appauth/reference/aa_init_db.md)
  : Create or update the authentication table schema
- [`aa_prepare_db()`](https://alexey-seleznev.pro/appauth/reference/aa_prepare_db.md)
  : Prepare the database on app start
- [`aa_schema_version()`](https://alexey-seleznev.pro/appauth/reference/aa_schema_version.md)
  : Current version of the authentication table schema
- [`aa_cleanup()`](https://alexey-seleznev.pro/appauth/reference/aa_cleanup.md)
  : Delete stale authentication data
- [`aa_session_connection()`](https://alexey-seleznev.pro/appauth/reference/aa_session_connection.md)
  : Database connection closed together with the session

## Passwords

- [`aa_hash_password()`](https://alexey-seleznev.pro/appauth/reference/aa_hash_password.md)
  : Hash a password
- [`aa_verify_password()`](https://alexey-seleznev.pro/appauth/reference/aa_verify_password.md)
  : Verify a password against a hash
- [`aa_is_password_hash()`](https://alexey-seleznev.pro/appauth/reference/aa_is_password_hash.md)
  : Is the value a password hash
- [`aa_validate_password()`](https://alexey-seleznev.pro/appauth/reference/aa_validate_password.md)
  : Validate a new password against the rules
- [`aa_validate_login()`](https://alexey-seleznev.pro/appauth/reference/aa_validate_login.md)
  : Validate a new user's login
- [`aa_migrate_plaintext_passwords()`](https://alexey-seleznev.pro/appauth/reference/aa_migrate_plaintext_passwords.md)
  : Migrate passwords from plain text to hashes
- [`aa_check_default_accounts()`](https://alexey-seleznev.pro/appauth/reference/aa_check_default_accounts.md)
  : Find accounts with weak passwords
- [`aa_common_passwords()`](https://alexey-seleznev.pro/appauth/reference/aa_common_passwords.md)
  : List of common weak passwords
- [`aa_weak_password_warning()`](https://alexey-seleznev.pro/appauth/reference/aa_weak_password_warning.md)
  : Weak password warning

## Users

- [`aa_get_user()`](https://alexey-seleznev.pro/appauth/reference/aa_get_user.md)
  : User by login
- [`aa_list_users()`](https://alexey-seleznev.pro/appauth/reference/aa_list_users.md)
  : List of users
- [`aa_users_exist()`](https://alexey-seleznev.pro/appauth/reference/aa_users_exist.md)
  : Does the database have at least one user
- [`aa_users_overview()`](https://alexey-seleznev.pro/appauth/reference/aa_users_overview.md)
  : Users with statuses for a table
- [`aa_active_autologins()`](https://alexey-seleznev.pro/appauth/reference/aa_active_autologins.md)
  : How many active autologins users have
- [`aa_create_user()`](https://alexey-seleznev.pro/appauth/reference/aa_create_user.md)
  : Create a user
- [`aa_create_first_admin()`](https://alexey-seleznev.pro/appauth/reference/aa_create_first_admin.md)
  : Create the first user (administrator)
- [`aa_validate_new_user()`](https://alexey-seleznev.pro/appauth/reference/aa_validate_new_user.md)
  : Validate a new user's data
- [`aa_authenticate()`](https://alexey-seleznev.pro/appauth/reference/aa_authenticate.md)
  : Verify login and password (login)
- [`aa_set_password()`](https://alexey-seleznev.pro/appauth/reference/aa_set_password.md)
  : Set a new password for a user
- [`aa_change_own_password()`](https://alexey-seleznev.pro/appauth/reference/aa_change_own_password.md)
  : Change your own password
- [`aa_set_role()`](https://alexey-seleznev.pro/appauth/reference/aa_set_role.md)
  : Change a user's role
- [`aa_set_blocked()`](https://alexey-seleznev.pro/appauth/reference/aa_set_blocked.md)
  : Block or unblock a user
- [`aa_delete_user()`](https://alexey-seleznev.pro/appauth/reference/aa_delete_user.md)
  : Delete a user
- [`aa_check_can_block()`](https://alexey-seleznev.pro/appauth/reference/aa_check_can_block.md)
  : Can a user be blocked
- [`aa_check_can_delete()`](https://alexey-seleznev.pro/appauth/reference/aa_check_can_delete.md)
  : Can a user be deleted
- [`aa_check_can_change_role()`](https://alexey-seleznev.pro/appauth/reference/aa_check_can_change_role.md)
  : Can a user's role be changed

## Password recovery

- [`aa_set_email()`](https://alexey-seleznev.pro/appauth/reference/aa_set_email.md)
  : Set, change or remove a user's email
- [`aa_get_email()`](https://alexey-seleznev.pro/appauth/reference/aa_get_email.md)
  : User email
- [`aa_request_password_reset()`](https://alexey-seleznev.pro/appauth/reference/aa_request_password_reset.md)
  : Request password recovery
- [`aa_reset_token_login()`](https://alexey-seleznev.pro/appauth/reference/aa_reset_token_login.md)
  : User who owns a recovery link
- [`aa_reset_password_with_token()`](https://alexey-seleznev.pro/appauth/reference/aa_reset_password_with_token.md)
  : Set a new password by the link from the email

## Two-factor authentication

- [`aa_totp_setup()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_setup.md)
  : Start setting up two-factor authentication
- [`aa_totp_enable()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_enable.md)
  : Enable two-factor authentication
- [`aa_totp_disable()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_disable.md)
  : Disable two-factor authentication
- [`aa_totp_enabled()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_enabled.md)
  : Whether two-factor authentication is enabled for a user
- [`aa_verify_second_factor()`](https://alexey-seleznev.pro/appauth/reference/aa_verify_second_factor.md)
  : Verify the second factor at sign-in
- [`aa_recovery_codes_left()`](https://alexey-seleznev.pro/appauth/reference/aa_recovery_codes_left.md)
  : How many recovery codes are left
- [`aa_totp_secret()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_secret.md)
  : Random secret for an authenticator app
- [`aa_totp_uri()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_uri.md)
  : otpauth link for an authenticator app
- [`aa_totp_code()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_code.md)
  : One-time TOTP code for a point in time
- [`aa_totp_ui()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_ui.md)
  : Two-factor authentication module: UI
- [`aa_totp_server()`](https://alexey-seleznev.pro/appauth/reference/aa_totp_server.md)
  : Two-factor authentication module: server

## Login protection and sessions

- [`aa_login_gate()`](https://alexey-seleznev.pro/appauth/reference/aa_login_gate.md)
  : Can a login be attempted right now
- [`aa_record_attempt()`](https://alexey-seleznev.pro/appauth/reference/aa_record_attempt.md)
  : Record a login attempt
- [`aa_login_lock_remaining()`](https://alexey-seleznev.pro/appauth/reference/aa_login_lock_remaining.md)
  : Seconds left until a login lockout ends
- [`aa_global_throttled()`](https://alexey-seleznev.pro/appauth/reference/aa_global_throttled.md)
  : Is the global failed login limit exceeded
- [`aa_clear_attempts()`](https://alexey-seleznev.pro/appauth/reference/aa_clear_attempts.md)
  : Clear a login lockout caused by failed attempts
- [`aa_issue_token()`](https://alexey-seleznev.pro/appauth/reference/aa_issue_token.md)
  : Issue an autologin token
- [`aa_find_session_user()`](https://alexey-seleznev.pro/appauth/reference/aa_find_session_user.md)
  : Find a user by autologin token
- [`aa_revoke_token()`](https://alexey-seleznev.pro/appauth/reference/aa_revoke_token.md)
  : Revoke an autologin token
- [`aa_revoke_sessions()`](https://alexey-seleznev.pro/appauth/reference/aa_revoke_sessions.md)
  : End all sessions of a user
- [`aa_user_session_valid()`](https://alexey-seleznev.pro/appauth/reference/aa_user_session_valid.md)
  : Check that an open session is still valid

## Permissions and events

- [`aa_permissions_from_matrix()`](https://alexey-seleznev.pro/appauth/reference/aa_permissions_from_matrix.md)
  : Permission provider from a "permission -\> roles" matrix
- [`aa_can()`](https://alexey-seleznev.pro/appauth/reference/aa_can.md)
  : Does the user have a permission
- [`aa_require()`](https://alexey-seleznev.pro/appauth/reference/aa_require.md)
  : Require a permission in an action handler
- [`aa_events()`](https://alexey-seleznev.pro/appauth/reference/aa_events.md)
  : Catalog of authorization events
- [`aa_event_logger()`](https://alexey-seleznev.pro/appauth/reference/aa_event_logger.md)
  : Ready-made event handler for writing to a log

## UI modules and app helpers

- [`aa_app_head()`](https://alexey-seleznev.pro/appauth/reference/aa_app_head.md)
  : Attach appauth styles and scripts
- [`aa_auth_ui()`](https://alexey-seleznev.pro/appauth/reference/aa_auth_ui.md)
  : Sign-in module: UI
- [`aa_auth_server()`](https://alexey-seleznev.pro/appauth/reference/aa_auth_server.md)
  : Sign-in module: server
- [`aa_users_ui()`](https://alexey-seleznev.pro/appauth/reference/aa_users_ui.md)
  : Users module: UI
- [`aa_users_server()`](https://alexey-seleznev.pro/appauth/reference/aa_users_server.md)
  : Users module: server
- [`aa_password_ui()`](https://alexey-seleznev.pro/appauth/reference/aa_password_ui.md)
  : Own password change module: UI
- [`aa_password_server()`](https://alexey-seleznev.pro/appauth/reference/aa_password_server.md)
  : Own password change module: server
- [`aa_session_guard()`](https://alexey-seleznev.pro/appauth/reference/aa_session_guard.md)
  : Forcibly end invalid sessions
- [`aa_register_module()`](https://alexey-seleznev.pro/appauth/reference/aa_register_module.md)
  : Attach a module server only if the permission is granted

## AI agent skills

- [`aa_install_skills()`](https://alexey-seleznev.pro/appauth/reference/aa_install_skills.md)
  : Install skills for AI agents
