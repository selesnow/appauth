# Recipe: a personal account area (changing your own password, log out on all devices)

The personal-area buttons are ordinary app buttons next to the user badge ("User: ... (role)", "Log out"). They are wired to ready-made package functions. A ready implementation: `assets/app-skeleton/app.R`, a live example `system.file("examples/minimal-app/app.R", package = "appauth")`, a detailed walkthrough in `references/extension-points.md` of the `appauth` skill.

## What is needed

| Button | What it does | Implemented with |
| --- | --- | --- |
| Change password | a window with a form (current password, new one, confirmation); the current session stays, the others are ended | `aa_password_ui()` in a `modalDialog` and `aa_password_server()`; close the window on `pw$changed()` |
| Log out on all devices | after CONFIRMATION ends all of the user's sessions, including the current one | `auth$logout_all(reload = TRUE)` |
| Log out | ends the current session | `auth$logout(reload = TRUE)` |

## Mandatory details

* **Confirmation before "log out everywhere"** is mandatory: the button also throws the user out on their work computer. A window with "Cancel" and "Log out everywhere" buttons.
* **`aa_session_guard()`** must be wired in: it is what closes open sessions on other devices after tokens are revoked (within `session_check_seconds`, 30 seconds by default). Without it "log out everywhere" closes only the current session.
* **Auto-login** must be enabled (`autologin = TRUE`): with auto-login off, sessions have no tokens, and "log out everywhere" closes only the current one.
* Changing the password checks the current password; the new one must differ from the current one and satisfy `password_min`/`password_max`; the tokens of the other sessions are revoked, `must_change` is cleared.
* The events `password_changed`, `sessions_revoked`, `logout` go to the `on_event` hook (in the log `Password change`, `Sessions revoke`).

## Styling the buttons

New buttons must look like the other control buttons in the header. If the app styles buttons by `id` (like `#logout_btn`, `#toggle_theme`), add the same rules for them: otherwise they get the standard Bootstrap look and stand out.

## Tests

```r
# changing the password in the app: the old password stops working, the session stays, the other device's token is revoked
session$setInputs(`password-old` = "oldpass1", `password-new` = "newpass-1", `password-confirm` = "newpass-1", `password-change` = 1)
expect_null(aa_find_session_user(con, other_device_token))
expect_true(auth$logged_in())

# log out on all devices: before confirmation we stay, after confirmation we log out, tokens are revoked
session$setInputs(logout_all = 1);          expect_true(auth$logged_in())
session$setInputs(logout_all_confirm = 1);  expect_false(auth$logged_in())
```

In an app test the input names are the same as in `app.R` (`logout_all`, `logout_all_confirm`, `password-old`...).

## When there are many buttons: the profile in one window

Changing the password, email, 2FA and "log out everywhere" are better kept not in the header but in a profile: the "User: login (role)" card becomes a button (an `actionLink` inside the badge block), and a click opens a single window. Only session actions remain in the header ("Refresh", "Log out", theme).

* **One window with tabs, not several windows.** Shiny shows one modal at a time: a button inside a window that opens another window closes the first. Inside the window a `tabsetPanel` with tabs "Password" (`aa_password_ui()`), "Email" (the app's own module), "2FA" (`aa_totp_ui()`, only if `totp_enabled`). The needed tab is opened by the `selected` parameter (a 2FA reminder opens the profile directly on "2FA"). Replace an unknown tab name with the first one.
* **Attach the package modules once inside the profile module**, and place their UI under `ns("password")`, `ns("totp")`: the identifiers of nested modules get a prefix (`profile-password-old`, `profile-totp-start`); account for this in tests and Playwright.
* **The summary on top** is assembled from `aa_get_user()` (dates), `aa_get_email()` (show it masked, for example `a***@domain`), `aa_totp_enabled()` and `aa_recovery_codes_left()`, `aa_active_autologins()` (remembered devices). Secrets and keys never go into the summary. Refresh the summary with `invalidateLater()` (4 seconds): after an email change or enabling 2FA it catches up by itself.
* **"Remembered devices" are auto-login tokens (cookies)**, not the number of open tabs: the app does not track those. Label it that way in the UI.
* "Log out on all devices" lives in the same window, and the confirmation stays (the second window closes the profile, which is fine).
* The backup-codes window shown by `aa_totp_server()` is also modal and replaces the profile; after "Close" the user returns to the page, and the profile is opened again.
* **Tests:** a `testServer()` of the profile module with `showModal` mocked (`testthat::with_mocked_bindings(showModal = ..., .package = "shiny")`) checks the tabs and the selected tab; in a whole-app test the identifiers carry the prefix (`profile_open`, `profile-logout_all_btn`, `profile-password-old`).

## Copy buttons (appauth 0.6.0)

Next to the manual-entry key and the backup codes the package itself shows "Copy" buttons (`button.aa-copy`, the text in `data-copy`); the copy script is attached by `aa_app_head()`. A button of your own with the same markup works the same way, for example for a secret the app shows once: `tags$button(type = "button", class = "btn btn-default btn-sm aa-copy", `data-copy` = text, `data-done` = "Copied", "Copy")`. Copying happens in the browser, so the value does not need to be stored on the server for this.
