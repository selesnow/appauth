# appauth reference: Two-factor authentication (TOTP)

Package version: 0.11.2. This file is generated automatically from the package help (`dev/skills/build_reference.R`) and must not be edited by hand.

Functions in this section:
`aa_totp_setup()`, `aa_totp_enable()`, `aa_totp_disable()`, `aa_totp_enabled()`, `aa_verify_second_factor()`, `aa_recovery_codes_left()`, `aa_totp_secret()`, `aa_totp_uri()`, `aa_totp_code()`

## Contents

- [aa_totp_setup](#aa_totp_setup)
- [aa_totp_enable](#aa_totp_enable)
- [aa_totp_disable](#aa_totp_disable)
- [aa_totp_enabled](#aa_totp_enabled)
- [aa_verify_second_factor](#aa_verify_second_factor)
- [aa_recovery_codes_left](#aa_recovery_codes_left)
- [aa_totp_secret](#aa_totp_secret)
- [aa_totp_uri](#aa_totp_uri)
- [aa_totp_code](#aa_totp_code)

## aa_totp_setup

```text
Start setting up two-factor authentication

Description:

     Creates a new secret and stores it in the database in encrypted form, but *does not
     enable* 2FA: it is enabled only after 'aa_totp_enable()' with a correct code from
     the app. A repeated call replaces the pending secret. If 2FA is already enabled, an
     error of class 'appauth_error_user' is raised.

Usage:

     aa_totp_setup(conn, login, settings = aa_settings())

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

settings: Settings, the result of 'aa_settings()' with 'totp_enabled = TRUE'.

Value:

     A list: 'secret' (base32, for manual entry) and 'uri' (an otpauth:// link, the QR
     code is built from it).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       settings <- aa_settings(totp_enabled = TRUE, totp_key =
       "a-long-random-key-for-the-example")
       setup <- aa_totp_setup(conn, "boss", settings)
       setup$uri
       DBI::dbDisconnect(conn)
     }
```

## aa_totp_enable

```text
Enable two-factor authentication

Description:

     Checks the app code against the pending secret ('aa_totp_setup()') and enables 2FA.
     Creates 10 recovery codes: *they are returned once*, only hashes stay in the
     database. A wrong code raises an error of class 'appauth_error_user' ('reason =
     "totp_wrong"').

Usage:

     aa_totp_enable(conn, login, code, settings = aa_settings())

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

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
       settings <- aa_settings(totp_enabled = TRUE, totp_key =
       "a-long-random-key-for-the-example")
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
     'aa_totp_server()' module requires a password and a code before calling it, and
     reset by an administrator ('aa_users_server()') is allowed only to an administrator.

Usage:

     aa_totp_disable(conn, login)

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

Value:

     'TRUE' if something was reset for the user, otherwise 'FALSE' (invisibly).

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

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

Value:

     'TRUE' or 'FALSE' ('FALSE' both for a nonexistent user and if the schema is not
     upgraded to version 8).

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
Verify the second factor at sign-in

Description:

     Accepts a code from the app (6 digits) or a recovery code. An app code is accepted
     once: a repeat of the same code (time step) is rejected. A recovery code is
     one-time. The function *does not limit the number of attempts itself*: call
     'aa_login_gate()' before it and 'aa_record_attempt()' after a wrong code, as the
     sign-in module does.

Usage:

     aa_verify_second_factor(conn, login, code, settings = aa_settings())

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

    code: Entered code.

settings: Settings, the result of 'aa_settings()' with 'totp_enabled = TRUE'.

Value:

     A list: 'ok' ('TRUE' or 'FALSE') and 'method' ('"totp"', '"recovery"' or 'NA').

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       settings <- aa_settings(totp_enabled = TRUE, totp_key =
       "a-long-random-key-for-the-example")
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

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

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

     A base32 string of 32 characters (160 bits), the way it is entered into the app
     manually.

Examples:

     nchar(aa_totp_secret())
```

## aa_totp_uri

```text
otpauth link for an authenticator app

Description:

     The QR code is built from this link, and apps also understand it on manual entry.

Usage:

     aa_totp_uri(secret, login, issuer = "appauth")

Arguments:

  secret: Secret in base32.

   login: User login.

  issuer: Service name the app will show.

Value:

     A string like otpauth://totp/....

Examples:

     aa_totp_uri("JBSWY3DPEHPK3PXP", "ivan", "Reports portal")
```

## aa_totp_code

```text
One-time TOTP code for a point in time

Description:

     The RFC 6238 algorithm (HMAC-SHA1, 30-second step). Needed in tests and for
     comparing with an authenticator app.

Usage:

     aa_totp_code(secret, time = Sys.time(), digits = 6, period = 30)

Arguments:

  secret: Secret in base32.

    time: Point in time (now by default).

  digits: Number of digits in the code.

  period: Step length, seconds.

Value:

     A string of 'digits' digits or 'NA' if the secret is invalid.

Examples:

     aa_totp_code("JBSWY3DPEHPK3PXP")
```

