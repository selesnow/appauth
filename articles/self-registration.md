# Self-registration

By default `appauth` is a closed system: an administrator creates every
user. Since 0.11.0 an application can also allow visitors to create
their own accounts. All related settings are off by default, so
upgrading an application or a database does not open registration by
itself.

## When to use it

Self-registration is appropriate when everyone with an approved email
address may enter the application. If access must be granted one by one,
keep the default and create users with
[`aa_create_user()`](https://alexey-seleznev.pro/appauth/reference/aa_create_user.md).

Two paths are supported:

- a **Create an account** link on the login form, with email
  confirmation;
- **Google sign-up**: an account is created automatically after a Google
  sign-in if the verified email is not in the database.

The link appears only when the database already has users. On an empty
database the first administrator is still created with the usual form,
so registration cannot create the first administrator.

## Settings

``` r

settings <- aa_settings(
  registration_enabled = TRUE,
  registration_verify_email = TRUE,
  registration_role = "viewer",
  registration_domains = c("example.com"),
  registration_max_per_hour = 10,
  reset_enabled = TRUE,
  reset_base_url = "https://apps.example.com/my_app",
  send_reset = function(email, link, login) {
    # the application sends the email with emayili, telegram.bot, etc.
    message("Registration link for ", login, ": ", link)
  }
)
settings$registration_role
#> [1] "viewer"
```

`registration_role` must be one of `roles` and cannot be `admin_role`,
so a visitor can never grant themselves administrative rights.
`registration_domains` is optional; when set, only addresses in those
domains can register. The hourly limit counts all pending requests,
including requests that were never confirmed.

With `registration_verify_email = TRUE` (the default), `send_reset` and
`reset_base_url` are required. The app calls
`send_reset(email, link, login)`; the link contains `?register=<token>`
and must be forwarded to the visitor. With `FALSE` the account is
created immediately, which is sensible only in a controlled environment.

The confirmation token is one-time, has the same lifetime as a password
reset link and is stored only as sha256. The password is hashed before
it is stored in the pending registration. If someone creates the same
login or email while the link is unused, confirmation fails instead of
taking over the existing account.

## The form response

The package deliberately returns the same answer whether or not the
login and email were available. A request with an existing account does
not reveal that fact on screen; the reason is written only to the
`on_event` hook. This prevents enumerating users through the
registration form.

## Google sign-up

``` r

settings <- aa_settings(
  google_enabled = TRUE,
  google_client_id = Sys.getenv("GOOGLE_CLIENT_ID"),
  google_client_secret = Sys.getenv("GOOGLE_CLIENT_SECRET"),
  google_redirect_uri = "https://apps.example.com/",
  google_domains = c("example.com"),
  google_signup = TRUE,
  registration_role = "viewer"
)
```

`google_signup = TRUE` requires `google_enabled = TRUE`. By default
`google_signup_require_domains = TRUE` also requires a non-empty
`google_domains` list: without it any Google account could create an
account. Set that option to `FALSE` only for an intentionally open
application.

The email is taken from the verified Google token. The login is the
local part of the address with unsupported characters replaced by dots;
a numeric suffix is added if the login is already taken. The new account
gets a random password hash, so it can only be used through Google until
an administrator sets a password. `registration_domains` does not apply
here: the relevant domain check for Google sign-in is `google_domains`.

## Events and cleanup

The hook receives `registration_requested`, `registration_confirmed`,
`registration_failed` and `google_user_created`. A successful
registration also emits `login_success` with the value `registration`,
because the module signs the new user in. Tokens and passwords are never
written to events. See
[`aa_events()`](https://alexey-seleznev.pro/appauth/reference/aa_events.md)
and the `extension-points` vignette.

[`aa_cleanup()`](https://alexey-seleznev.pro/appauth/reference/aa_cleanup.md)
removes expired and used registrations together with other stale tokens.
It is called automatically by `aa_session_connection(prepare = TRUE)`.

## Logic without the module

Applications with a custom interface can call the exported functions
directly:

``` r

result <- aa_register_user(
  conn, "ivan", "a-long-password", "ivan@example.com", settings
)
result$reason # "sent" or "created"

# after the visitor follows the link from the email
aa_registration_token_login(conn, token) # login or NULL
aa_confirm_registration(conn, token, settings) # creates the account
```

[`aa_register_user()`](https://alexey-seleznev.pro/appauth/reference/aa_register_user.md)
returns the reason in a list; do not show `user_exists` or
`email_exists` to a visitor.
[`aa_confirm_registration()`](https://alexey-seleznev.pro/appauth/reference/aa_confirm_registration.md)
raises an `appauth_error_user` error when the link is invalid or the
account data changed meanwhile.
