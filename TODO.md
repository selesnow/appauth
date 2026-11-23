# TODO appauth

Planned improvements, in priority order. A finished item is moved to
`NEWS.md` and removed from here.

## 1. `HttpOnly` cookie

The auto-login cookie is currently written by JavaScript, so `HttpOnly`
cannot be set. Mitigation: only the token hash is stored in the
database, and the token is revoked on logout, blocking and password
change. The real fix is to issue the cookie from the server, which is a
significant rework.

## 2. Two-factor authentication follow-ups (after 0.5.0)

- Mandatory enrolment for roles (`totp_required_roles`): when logging in
  without 2FA, show the setup wizard first, like the forced password
  change.
- Issue new recovery codes without disabling 2FA (password and code
  required).
- Other factors: WebAuthn and hardware keys.
- Ask for a code when logging in via cookie for sensitive actions
  (re-confirmation).

## 3. Password recovery follow-ups (after 0.4.0)

- Send the email in the background, so the form response time does not
  reveal whether a user exists.
- Email notification that the password was changed (via the link or by
  an administrator).
- Email address confirmation (a link in an email) before it is used for
  recovery.
- Self-service: users set and change their own email in the
  [`aa_password_ui()`](https://alexey-seleznev.pro/appauth/reference/aa_password_ui.md)
  module.

## Postponed

- IP-based restrictions (the client IP is not visible behind nginx).
