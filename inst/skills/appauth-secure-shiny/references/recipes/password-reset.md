# Recipe: password reset by email

Needed if users forget their passwords themselves and have working addresses. Requires `appauth` version 0.4.0 or newer. Off by default: without this setting the app's behaviour does not change. Full reference: the `appauth` skill (`references/extension-points.md`, `references/api-password-reset.md`).

## When to enable it, when not

* Enable it if the mail addresses can be trusted: an email with a link equals a key to the account, and whoever controls the mailbox can change the password.
* For administrators it is better not to set an address and to keep manual password reset (the user card, "Reset password"): then a compromised mailbox does not give access to management.
* If there are no addresses or the app has no mail, leave it off: the administrator does the reset.

## Steps

1. **The sending function.** Send emails through any mail transport you have (the example uses the `emayili` package with credentials from environment variables, here `SMTP_EMAIL` and `SMTP_EMAIL_PWD`). The function receives the address, the link and the login:

```r
library(emayili)

send_reset <- function(email, link, login) {
  msg <- envelope() %>%
    from("My App <noreply@example.com>") %>%
    to(email) %>%
    subject("Password reset") %>%
    html(paste0(
      "<p>Hello, ", htmltools::htmlEscape(login), "!</p>",
      "<p>To set a new password, follow this <a href='", link, "'>link</a>. ",
      "It is valid for 60 minutes and works only once.</p>",
      "<p>If you did not request a reset, just ignore this email.</p>"
    ))

  smtp <- gmail(Sys.getenv("SMTP_EMAIL"), Sys.getenv("SMTP_EMAIL_PWD"))
  smtp(msg)
}
```

2. **Settings.** If settings are read from `config.yaml` (`aa_settings_from_list()`), pass the `send_reset` function as an argument, not from the config:

```r
settings <- aa_settings_from_list(
  conf$security,
  reset_enabled  = TRUE,
  send_reset     = send_reset,
  reset_base_url = "https://apps.example.com/my_app"
)
```

`reset_base_url` is the app address the way users open it: the `https://` scheme, the host and the nginx prefix. The link is built as `<reset_base_url>/?reset=<token>`. Other parameters: `reset_ttl_minutes` (60), `reset_max_per_hour` (3), `reset_max_per_minute` (10).

3. **Nothing else needs wiring.** `aa_auth_server()` itself shows "Forgot password?", reads the `reset` parameter from the page address and shows the new-password form. If the app overrides the login interface, leave `aa_auth_ui()` as is.

4. **User addresses.** The administrator enters the email in the user card or when adding a user; for existing users the addresses are empty. Programmatically: `aa_set_email(conn, login, email, settings)` and `aa_create_user(..., email = )`.

5. **Log.** The events `password_reset_requested` (the reason in `value`), `password_reset_done`, `password_reset_failed`, `email_changed` arrive in the `on_event` hook together with the others. In `aa_event_logger()` add them to `actions` if your log uses its own names.

6. **nginx.** The token is visible in the access log (`$request_uri`) until the link is used: restrict access to the logs or write `$uri`. Add `limit_req` for a public app.

## Verification

* The "Forgot password?" form answers identically for an existing and a non-existent login (otherwise it leaks the list of users).
* The link from the email opens the new-password form, and after the change the same address shows "link is invalid".
* A password set via the link passes the password policy (`password_policy`); with `"reject"` a weak password does not consume the link.
* After a password change the user's open sessions on other devices are ended.
* In `testServer` tests substitute the address bar with `testthat::local_mocked_bindings(aa_url_search = function(session) "?reset=<token>", .package = "appauth")`: the address of a mock Shiny session cannot be configured. Intercept emails with your own `send_reset`, collecting the links in an environment.
