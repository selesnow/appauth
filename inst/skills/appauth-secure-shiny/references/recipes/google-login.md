# Recipe: sign-in with Google (single sign-on, SSO)

Needed when employees already work under corporate Google Workspace accounts and should not create yet another password. Requires `appauth` version 0.7.0 or newer. Off by default; password login remains.

## When to enable it, when not

* Enable it if all users of the app have Google Workspace accounts of your organisation and the app has a domain with HTTPS.
* Do not enable it if the app is opened by IP address: Google does not allow such an address as a redirect address. First you need a domain and a certificate (step 1).
* By default sign-in with Google creates nothing: the user must be created in the app in advance, with an email equal to the Google address. Since 0.11.0 `google_signup = TRUE` may create a new account from a verified email. Roles and permissions stay in `appauth` in either case; Google only confirms identity.

## Steps

1. **Domain and HTTPS.**
   * In the domain's DNS (for example at the registrar) add an `A` record: a subdomain (`sm`) pointing to the server's public IP. A main site on other hosting (for example GitHub Pages) is not affected.
   * A Let's Encrypt certificate for nginx: `certbot` on Linux, or `win-acme` (`wacs.exe`) on Windows, with HTTP validation. In the port 80 block add `location /.well-known/acme-challenge/ { root /var/www/acme-webroot; }`, and redirect all other traffic to HTTPS (`return 301 https://$host$request_uri;`). Automatic renewal is set up by a scheduled job; after renewal nginx must re-read its config (`nginx -s reload`) as the same user the service runs under (otherwise `Access is denied` / permission errors).
   * Add to nginx a `server` block on 443 with the domain's `server_name`, the same `proxy_pass` and WebSocket headers as the old block (example: `recipes/cookie-and-https.md`). The block by IP can be kept for a transition period.
   * Update `reset_base_url` (the app address used in password-reset links) to the new address.
2. **OAuth client in Google Cloud Console** (a project inside the Workspace organisation; you need permission to create clients).
   * Consent screen: **Internal**. Then only accounts of your organisation can sign in, and no review on Google's side is needed. For accounts from other organisations (a holding with several Workspaces) you need **External**; the restriction is then the list of domains and the presence of the user in the database.
   * Client: type **Web application**. Authorized redirect URI: the app address exactly as users open it, for example `https://sm.example.com/` (with or without trailing slash, it must match `google_redirect_uri` character for character). Authorized JavaScript origins: `https://sm.example.com`.
   * The client ID and secret (the JSON from the console) must **not be committed or pasted into a chat**. The secret is shown once; if lost, create a new one.
3. **Secrets in the service environment.** `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET` in the project's `.Renviron` (the file is not in git, readable only by the app's account). Restart the service: `.Renviron` is read at start.
4. **Settings.**

```r
settings <- aa_settings_from_list(
  conf$security,
  google_enabled       = TRUE,
  google_client_id     = Sys.getenv("GOOGLE_OAUTH_CLIENT_ID"),
  google_client_secret = Sys.getenv("GOOGLE_OAUTH_CLIENT_SECRET"),
  google_redirect_uri  = "https://sm.example.com/",
  google_domains       = c("example.com", "example.net")
)
```

   The app does not need to wire anything else: `aa_auth_ui()` and `aa_auth_server()` themselves show the "Sign in with Google" button and accept the return from Google.
5. **Domains.** `google_domains` is checked against both the token's `hd` (this is the **primary** domain of the Workspace organisation) and the email domain. If the organisation has secondary domains (an employee with email `@example.net` while the primary is `example.com`), list both. An empty list disables the domain check: then only the match of the email with a user decides, and any Google account fits, Gmail included. A non-empty list does not let personal accounts (without `hd`) through. If the app already has a list of allowed email domains, use the same one so that domains are edited in a single place.
6. **Email of users.** Sign-in is closed to a user without an email (`no_user`). Fill in the addresses in the user card (`aa_set_email()`); the email must match the Google address, case does not matter. With `google_signup = TRUE` an unknown verified address creates an account automatically, with the login derived from the email local part (a numeric suffix is added on collision) and the role from `registration_role`.
7. **Events.** `login_success` arrives with the value `google`; failures arrive as `google_login_failed` with the reason and email in `value`. A created account also emits `google_user_created` with the login. In `aa_event_logger()` add `google_login_failed` to `actions` if your log uses its own names. Series of `no_user`, `domain`, `bad_browser` and `signup_login_taken` are worth showing the same way as `login_failed` series.
8. **Disabling the password** (optional): `password_login = FALSE`. The password form and "Forgot password?" are hidden, password login attempts are rejected on the server. Allowed only together with `google_enabled = TRUE`. **Before disabling**, make sure at least one administrator has an email and sign-in with Google works, otherwise there will be no way to log in. A fallback in case Google is unavailable: set `password_login = TRUE` back in the settings (with password login off this cannot be done from the UI; you need access to the config on the server).

## The app is opened both by IP and by domain

Often the app stays reachable by the server's IP address too, while sign-in with Google is configured for the domain. Google returns the user only to `google_redirect_uri`, and the login `state` lies in a cookie of the site address from which login was started (cookies for the IP and for the domain are different). Since `appauth` 0.7.1 this is handled: on a page with a different address the "Sign in with Google" button sends the user to the return address, and login starts there by itself (`?google=1`), no second click needed. Password login and cookie auto-login work independently on each address, nothing needs configuring. In 0.7.0 a login from another address ended with a `bad_browser` rejection: update the package. A forced redirect from the IP to the domain in nginx is not needed for this, but you can add it if IP access is no longer needed.

## Email assigned by the administrator

The administrator sets the email in the user card with no domain restrictions, no password and no emailed code: only the format and uniqueness of the address are checked (one address cannot belong to two users, otherwise sign-in by email would be ambiguous). A domain restriction and code confirmation exist only when a user changes the address by themselves in the profile (that is app logic, not the package's).

## Automatic account creation (since 0.11.0)

Add `google_signup = TRUE` to `aa_settings()` when new employees should get an account on their first corporate Google sign-in. Requirements: `google_enabled = TRUE`, a valid `registration_role` (any role except `admin_role`, default `viewer`), and a non-empty `google_domains` unless you deliberately set `google_signup_require_domains = FALSE`. Only a verified Google email is used; the package validates the token exactly as for an existing user. `registration_domains` does not apply to this path.

* Keep `google_signup = FALSE` for a closed app: then only pre-created users can sign in.
* The new user gets a random password hash, so password login can be left enabled without a known default password; the user can reset it by email if `reset_enabled` is on.
* A login collision is resolved with a numeric suffix (`ivan.ivanov.2`, `ivan.ivanov.3`, ...). Exhaustion fails with `signup_login_taken`; the visitor sees a generic message and the reason goes to `google_login_failed`.
* A blocked user is never created or admitted. A creation emits `google_user_created`, followed by `login_success` with the value `google`.

## How it is protected (for checking during an audit)

* Authorization code flow with PKCE. `state`, `nonce` and the PKCE check are single-use and live 10 minutes; in the database `state` is stored only as sha256 (table `oauth_states`), and it is not accepted a second time.
* The `state` from the return address is compared with a short cookie of the browser that started the login: someone else's return link cannot be slipped into another browser (protection against login substitution, login CSRF).
* The client secret stays on the server: the code is exchanged for a token by the app's server.
* The Google token is validated in full: signature against Google's public keys (RS256 only), issuer, audience, expiry, `nonce`, verified email, domain. Token fields are read by exact access (`[["email"]]`), without partial name matching.
* By default sign-in creates no new users and the role comes from the database; with `google_signup = TRUE` only a verified email from `google_domains` creates a non-admin account with a random password hash, and a login collision gets a numeric suffix reported as `signup_login_taken`. A blocked user cannot sign in, and cookie auto-login works as before.
* The package's own 2FA code is not asked for on Google sign-in from a user who has already enrolled: confirmation is done by Google (its sign-in protection and 2FA are determined by the Workspace policy). Since 0.13.0 a role in `totp_required_roles` without enabled 2FA is sent to the enrollment wizard before entering the application.
* The user is shown a generic text on any rejection; the reason goes only into the event.

## Diagnosing rejections

| Reason in the `google_login_failed` event | What it means and what to do |
| --- | --- |
| `no_user` | the Google account has no user with that email: create the user or fix the email in the card |
| `blocked` | the user is blocked by the administrator |
| `domain` | `hd` or the email domain is not in `google_domains` (check primary and secondary domains), or the account is personal while the list is non-empty |
| `bad_browser` | the login-start cookie did not match the return address: login was started in another browser, cookies are blocked, or more than 10 minutes passed |
| `bad_state` | `state` is unknown, expired or already used (pressing "back" again, refreshing the return page) |
| `exchange_failed` | Google rejected the code exchange: wrong client secret or ID, the redirect URI does not match the OAuth client; details are in the app log (the line saying Google rejected the code exchange, `appauth: Google ...`) |
| `bad_token`, `bad_nonce`, `email_unverified` | the token failed validation: Google's keys are unavailable, the server clock is far off (check NTP), or the account's email is not verified |
| `cancelled` | the user declined on the Google page |

The Google error `redirect_uri_mismatch` on the sign-in page means the address in `google_redirect_uri` did not match "Authorized redirect URIs" (scheme, domain, slash).

## Verification

* The button is on the form, clicking it leads to the Google page; on return, a user with an email from the database enters the app with the role from the database.
* A Google account without a user in the app cannot sign in and sees the generic text; event `google_login_failed` with `no_user`.
* A blocked user cannot sign in. An account from a foreign domain (with a non-empty `google_domains`) cannot sign in.
* With `password_login = FALSE` there is no password form, and a password login attempt (in a test, `session$setInputs(login = ..., password = ..., login_btn = 1)`) is rejected.
* Tests do not call Google: `testthat::local_mocked_bindings(aa_google_exchange_code = ..., aa_google_fetch_jwks = ..., aa_url_search = ..., .package = "appauth")`, the token is signed with a test key `jose::jwt_encode_sig(..., header = list(kid = "K1"))`, and the `nonce` is taken from the `oauth_states` table. The return in `testServer` is simulated with `session$setInputs(oauth_cookie = state)`. The redirect to Google itself cannot be automated in Playwright: check it manually.

## Limitations

* Google only; there are no other providers (Microsoft, Okta, SAML).
* Sign-in with Google equals access to the employee's Google account: it is protected by the organisation (Workspace policies). If an employee was dismissed in Workspace but remains in the app, access is closed by Google ceasing to confirm the account, but password login remains if it is not disabled: disable the password when that is acceptable.
* Email addresses in the app must be kept up to date: changing an address in Workspace without editing it in the app closes sign-in, and handing an address to another person opens someone else's account to them.
