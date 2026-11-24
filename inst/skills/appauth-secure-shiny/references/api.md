# appauth function reference (index)

Package version: 0.13.0. Read only the file you need for the task.

| Topic | File | Functions |
| --- | --- | --- |
| Settings and texts | `api-settings-texts.md` | `aa_settings`, `aa_settings_from_list`, `aa_texts`, `aa_text`, `aa_text_keys` |
| Database | `api-database.md` | `aa_init_db`, `aa_prepare_db`, `aa_schema_version`, `aa_cleanup`, `aa_session_connection` |
| Passwords | `api-passwords.md` | `aa_hash_password`, `aa_verify_password`, `aa_is_password_hash`, `aa_validate_password`, `aa_validate_login`, `aa_migrate_plaintext_passwords`, `aa_check_default_accounts`, `aa_common_passwords`, `aa_weak_password_warning` |
| Users | `api-users.md` | `aa_get_user`, `aa_list_users`, `aa_users_exist`, `aa_users_overview`, `aa_create_user`, `aa_create_first_admin`, `aa_validate_new_user`, `aa_authenticate`, `aa_set_password`, `aa_change_own_password`, `aa_set_role`, `aa_set_blocked`, `aa_delete_user`, `aa_check_can_block`, `aa_check_can_delete`, `aa_check_can_change_role` |
| Password recovery by email | `api-password-reset.md` | `aa_set_email`, `aa_get_email`, `aa_request_password_reset`, `aa_reset_token_login`, `aa_reset_password_with_token` |
| Self-registration | `api-self-registration.md` | `aa_register_user`, `aa_registration_token_login`, `aa_confirm_registration` |
| Two-factor authentication (TOTP) | `api-two-factor.md` | `aa_totp_setup`, `aa_totp_enable`, `aa_totp_disable`, `aa_totp_enabled`, `aa_verify_second_factor`, `aa_recovery_codes_left`, `aa_totp_secret`, `aa_totp_uri`, `aa_totp_code` |
| Login protection and sessions | `api-login-protection-sessions.md` | `aa_login_gate`, `aa_record_attempt`, `aa_login_lock_remaining`, `aa_global_throttled`, `aa_clear_attempts`, `aa_issue_token`, `aa_find_session_user`, `aa_revoke_token`, `aa_revoke_sessions`, `aa_active_autologins`, `aa_user_session_valid` |
| Permissions and events | `api-permissions-events.md` | `aa_permissions_from_matrix`, `aa_can`, `aa_require`, `aa_events`, `aa_event_logger` |
| UI modules and app helpers | `api-modules.md` | `aa_app_head`, `aa_auth_ui`, `aa_auth_server`, `aa_users_ui`, `aa_users_server`, `aa_password_ui`, `aa_password_server`, `aa_totp_ui`, `aa_totp_server`, `aa_session_guard`, `aa_register_module` |
| AI agent skills | `api-skills.md` | `aa_install_skills` |
