# appauth reference: Two-factor authentication (TOTP)

Reference built from appauth 0.8.0. Generated automatically from the package help pages; do not edit by hand.

Functions in this section:
`aa_totp_setup()`, `aa_totp_enable()`, `aa_totp_disable()`, `aa_totp_enabled()`, `aa_verify_second_factor()`, `aa_recovery_codes_left()`, `aa_totp_secret()`, `aa_totp_uri()`, `aa_totp_code()`

## aa_totp_setup

```text
Start enrolling two-factor authentication

Description:

     Creates a new secret and stores it in the database in encrypted form, but does
     *not enable* 2FA: it is enabled only after 'aa_totp_enable()' with a valid code
     from the app. Calling it again replaces the pending secret. If 2FA is already
     enabled, raises an error of class 'appauth_error_user'.

Usage:

     aa_totp_setup(conn, login, settings = aa_settings())
     
Arguments:

    conn: SQLite database connection ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

settings: Settings, the result of 'aa_settings()' with 'totp_enabled = TRUE'.

Value:

     A list: 'secret' (base32, for manual entry) and 'uri' (an otpauth:// link used to
     build the QR code).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       settings <- aa_settings(totp_enabled = TRUE, totp_key = "a-long-random-key-for-the-example")
       setup <- aa_totp_setup(conn, "boss", settings)
       setup$uri
       DBI::dbDisconnect(conn)
     }
```

## aa_totp_enable

```text
Enable two-factor authentication

Description:

     Verifies the code from the app against the pending secret ('aa_totp_setup()') and
     enables 2FA. Creates 10 recovery codes: *they are returned once*, only hashes
     remain in the database. A wrong code raises an error of class
     'appauth_error_user' ('reason = "totp_wrong"').

Usage:

     aa_totp_enable(conn, login, code, settings = aa_settings())
     
Arguments:

    conn: SQLite database connection ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

    code: Code from the authenticator app.

settings: Settings, the result of 'aa_settings()' with 'totp_enabled = TRUE'.

Value:

     A vector of recovery codes (invisibly).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       settings <- aa_settings(totp_enabled = TRUE, totp_key = "a-long-random-key-for-the-example")
       setup <- aa_totp_setup(conn, "boss", settings)
       codes <- aa_totp_enable(conn, "boss", aa_totp_code(setup$secret), settings)
       length(codes)
       DBI::dbDisconnect(conn)
     }
```

## aa_totp_disable

```text
Disable two-factor authentication

Description:

     Erases the user's secret and recovery codes. The function *checks nothing*: the
     'aa_totp_server()' module requires the password and a code before calling it,
     and a reset by an administrator ('aa_users_server()') is allowed only for an
     administrator.

Usage:

     aa_totp_disable(conn, login)
     
Arguments:

    conn: SQLite database connection ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

Value:

     'TRUE' if anything was reset for the user, otherwise 'FALSE' (invisibly).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       aa_totp_disable(conn, "boss")
       DBI::dbDisconnect(conn)
     }
```

## aa_totp_enabled

```text
Whether two-factor authentication is enabled for a user

Description:

     Whether two-factor authentication is enabled for a user

Usage:

     aa_totp_enabled(conn, login)
     
Arguments:

    conn: SQLite database connection ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

Value:

     'TRUE' or 'FALSE' ('FALSE' both for a non-existent user and if the schema has not
     been upgraded to version 8).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       aa_totp_enabled(conn, "boss")
       DBI::dbDisconnect(conn)
     }
```

## aa_verify_second_factor

```text
Verify the second factor at login

Description:

     Accepts a code from the app (6 digits) or a recovery code. An app code is
     accepted once: reusing the same code (time step) is rejected. A recovery code is
     single-use. The function *does not limit the number of attempts itself*: call
     'aa_login_gate()' before it and 'aa_record_attempt()' after a wrong code, as the
     login module does.

Usage:

     aa_verify_second_factor(conn, login, code, settings = aa_settings())
     
Arguments:

    conn: SQLite database connection ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

    code: The entered code.

settings: Settings, the result of 'aa_settings()' with 'totp_enabled = TRUE'.

Value:

     A list: 'ok' ('TRUE' or 'FALSE') and 'method' ('"totp"', '"recovery"' or 'NA').

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       settings <- aa_settings(totp_enabled = TRUE, totp_key = "a-long-random-key-for-the-example")
       aa_verify_second_factor(conn, "boss", "123456", settings)$ok
       DBI::dbDisconnect(conn)
     }
```

## aa_recovery_codes_left

```text
How many recovery codes are left

Description:

     How many recovery codes are left

Usage:

     aa_recovery_codes_left(conn, login)
     
Arguments:

    conn: SQLite database connection ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

Value:

     An integer: the number of unused recovery codes.

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_recovery_codes_left(conn, "boss")
       DBI::dbDisconnect(conn)
     }
```

## aa_totp_secret

```text
Random secret for an authenticator app

Description:

     Random secret for an authenticator app

Usage:

     aa_totp_secret()
     
Value:

     A base32 string of 32 characters (160 bits), which is how it is entered manually
     into the app.

Examples:

     nchar(aa_totp_secret())
```

## aa_totp_uri

```text
otpauth link for an authenticator app

Description:

     The QR code is built from this link, and apps also understand it when entered
     manually.

Usage:

     aa_totp_uri(secret, login, issuer = "appauth")
     
Arguments:

  secret: Secret in base32.

   login: The user's login.

  issuer: Service name that the app will show.

Value:

     A string of the form otpauth://totp/....

Examples:

     aa_totp_uri("JBSWY3DPEHPK3PXP", "ivan", "Reports portal")
```

## aa_totp_code

```text
One-time TOTP code for a point in time

Description:

     RFC 6238 algorithm (HMAC-SHA1, 30-second step). Needed in tests and for
     cross-checking against an authenticator app.

Usage:

     aa_totp_code(secret, time = Sys.time(), digits = 6, period = 30)
     
Arguments:

  secret: Secret in base32.

    time: Point in time (now by default).

  digits: Number of digits in the code.

  period: Step length, seconds.

Value:

     A string of 'digits' digits, or 'NA' if the secret is invalid.

Examples:

     aa_totp_code("JBSWY3DPEHPK3PXP")
```

