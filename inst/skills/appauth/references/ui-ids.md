# appauth module element identifiers (for tests and browser checks)

Input and output identifiers of the modules are built as `<module id>-<name>`. The table lists names without the prefix; the prefix is set by the application: `aa_auth_ui("auth")` gives `auth-login`, `aa_users_ui("users")` gives `users-add`, and if a module is nested in another one (`mod_access_ui` with `ns("users")`), it is `access-users-add`. In a test of a single module via `testServer` there is no prefix (`login`, `login_btn`); in a test of the whole app it is needed (`auth-login`).

The list was checked against the package source code (version 0.10.1, identifiers have not changed since 0.7.1). Browser selector: `#<prefix>-<name>`, for example `page.fill("#auth-login", "ivan")`.

Visible labels below are the package defaults for `aa_texts("en")`.

## Sign-in module `aa_auth_ui()` / `aa_auth_server()`

| Name | What it is |
| --- | --- |
| `login`, `password` | login and password fields of the sign-in form |
| `login_btn` | the "Sign in" button (Enter in a field also submits) |
| `message` | message text under the form (sign-in error, lockout) |
| `setup_login`, `setup_password`, `setup_confirm`, `setup_btn` | the form for creating the first administrator on an empty database |
| `change_password`, `change_confirm`, `change_btn` | the form for the mandatory change of a temporary password after sign-in |
| `forgot_link` | the "Forgot your password?" link under the sign-in form (only with `reset_enabled = TRUE`) |
| `forgot_identifier`, `forgot_btn` | the link request form: the "Login or email" field and the "Send link" button; the response in `message` is always the same |
| `reset_password`, `reset_confirm`, `reset_btn` | the new password form, opened by the `?reset=<token>` link from the email |
| `back_link` | the "Back to sign in" link on the link request form and on the new password form |
| `totp_code`, `totp_btn` | the second factor code form: appears after a correct password if the user has 2FA enabled (a code from the app or a backup code; in a test `session$setInputs(totp_code = ..., totp_btn = 1)`) |
| `google_btn` | the "Sign in with Google" button (only with `google_enabled = TRUE`; with `password_login = FALSE` the `login`, `password` fields and the `login_btn` button are absent). Classes: `.aa-google-button`, the "or" separator `.aa-login-or`. The redirect to Google itself cannot be automated in a browser: test the return via `testServer` with the Google functions mocked. On a page whose address is not in `google_redirect_uri`, the button redirects to the return address (`?google=1` starts the sign-in by itself; in tests mock `aa_page_origin` and `aa_redirect`) |
| `oauth_cookie` | an internal input with the value of the browser cookie of the browser that started the Google sign-in (in a test `session$setInputs(oauth_cookie = state)` after mocking `aa_url_search` to `"?code=...&state=..."`; it must match `state`) |
| `cookie` | an internal input with the token from the cookie (in a test `session$setInputs(cookie = token)`) |
| `form` (output) | the whole form: `output[["auth-form"]]$html` |

## Users module `aa_users_ui()` / `aa_users_server()`

| Name | What it is |
| --- | --- |
| `main` (output) | the whole module UI; empty for a non-administrator (the server part is not registered) |
| `table` | the users table (DT, server-side) with the columns "Login", "Role", "Status", "Created", "Last sign-in", "Email" (a check mark if an address is set), "2FA" (a check mark, the column exists only with `totp_enabled = TRUE`) and "Auto-logins" (the number of valid auto-login tokens, i.e. remembered devices; in a test look at the table values in `overview()`, and at the columns in the table JSON `<th>Email<`); a double click on a row opens the card |
| `add` | the "Add user" button |
| `new_login`, `new_user_password`, `new_user_confirm`, `new_user_role`, `new_user_email`, `new_user_must_change`, `add_confirm`, `add_message` | the add dialog: fields, role (selectize), the temporary password checkbox, the button, the error text |
| `open` | the "open user card" input: in a test `session$setInputs(open = "ivan")`, in a browser a double click on a row |
| `email`, `save_email` | the email field in the card and the "Save email" button (an empty value removes the address) |
| `reset_totp` | the "Reset 2FA" button in the card (visible if the user has 2FA enabled); in a test `session$setInputs(reset_totp = 1)` |
| `block`, `unblock`, `unlock` | card buttons: block, unblock, remove the sign-in lockout |
| `role`, `change_role` | the role selector (selectize) and the "Change role" button |
| `new_password`, `new_password_confirm`, `reset_must_change`, `reset_password` | password reset: fields, the temporary password checkbox, the button |
| `revoke` | the "End all sessions" button |
| `delete` | the "Delete account" button: only opens the confirmation dialog, deletes nothing by itself |
| `delete_confirm`, `delete_cancel` | the confirmation dialog buttons "Yes, delete" and "Cancel"; in a test `session$setInputs(delete = 1)`, then `session$setInputs(delete_confirm = 1)`. Only the user the dialog is shown for is deleted |

## Two-factor authentication module `aa_totp_ui()` / `aa_totp_server()`

| Name | What it is |
| --- | --- |
| `main` (output) | the whole block; empty while the settings have no `totp_enabled` |
| `start` | the "Enable" button (creates a secret, shows the QR code and the key) |
| `code`, `confirm`, `cancel` | the code field from the app, the "Confirm and enable" and "Cancel" buttons |
| `disable_password`, `disable_code`, `disable_btn` | disabling: password, code (or a backup code), button |
| `message` | message text (wrong code, lockout) |

Copy buttons (since 0.6.0): `button.aa-copy` with the text in the `data-copy` attribute, next to the key for manual entry (the secret is copied without spaces) and under the backup codes in the dialog after enabling (`pre.aa-totp-codes + .aa-copy`, one code per line). Copying is done by the `appauth.js` script from `aa_app_head()`: over HTTPS via the browser clipboard, otherwise via a hidden field; after copying the button shows "Copied" for 1.5 seconds. You can make your own copy button with the same markup: `tags$button(type = "button", class = "btn btn-default btn-sm aa-copy", `data-copy` = text, `data-done` = "Copied", "Copy")`.

In a browser the key for manual entry is in `.aa-totp code`, the QR code in `.aa-totp-qr svg`, and the backup codes after enabling in the `pre.aa-totp-codes` dialog. For a Playwright test, compute the code as TOTP (RFC 6238, HMAC-SHA1, 30 seconds) from the key.

The identifiers of the card slot are set by the application (`ns("permissions")` in `extra_card_ui()` gives `users-permissions`).

## Password change module `aa_password_ui()` / `aa_password_server()`

| Name | What it is |
| --- | --- |
| `old`, `new`, `confirm` | the fields for the current password, the new password and the confirmation |
| `change` | the "Change password" button |
| `message` | the error text under the form |
| `form` (output) | the form (not built when there is no user) |

## Playwright techniques

* **Choosing a role in `selectInput`** (`new_user_role`, `role`): the original `<select>` is hidden by selectize, and a plain `select_option` fails with a timeout. Set the value through selectize: `page.evaluate("document.querySelector('#users-new_user_role').selectize.setValue('editor')")`, or click the field `#users-new_user_role-selectized` and choose `.selectize-dropdown-content .option[data-value="editor"]`.
* **Double click on a card row**: `page.locator("#users-table tbody tr", has_text="ivan").dblclick()`, then `page.wait_for_selector("#users-block")`.
* **Closing a dialog** (`modalDialog`): the button `.modal-footer button[data-dismiss='modal']` (or `data-bs-dismiss`), then wait with `page.wait_for_selector("#shiny-modal", state="detached")`; the Escape key does not always work.
* **Forging a request from the browser** (checking server-side protection): `page.evaluate("Shiny.setInputValue('tasks-run', 1, {priority: 'event'})")`. For a user without the permission the handler must refuse (no changes in the database, `Access denied` in the log).
* **The server part of the users module** is registered only for those who have the permission, so forging `users-block` from an ordinary user is harmless: there is no handler in the session.
