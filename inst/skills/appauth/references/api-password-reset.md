# appauth reference: Password recovery by email

Package version: 0.11.0. This file is generated automatically from the package help (`dev/skills/build_reference.R`) and must not be edited by hand.

Functions in this section: 
`aa_set_email()`, `aa_get_email()`, `aa_request_password_reset()`, `aa_reset_token_login()`, `aa_reset_password_with_token()`

## Contents

- [aa_set_email](#aa_set_email)
- [aa_get_email](#aa_get_email)
- [aa_request_password_reset](#aa_request_password_reset)
- [aa_reset_token_login](#aa_reset_token_login)
- [aa_reset_password_with_token](#aa_reset_password_with_token)

## aa_set_email

```text
Set, change or remove a user's email

Description:

     The address is needed for password recovery ('aa_request_password_reset()'). It is
     stored in lower case, and two users cannot have the same address. An empty value
     ('NULL', 'NA' or '""') removes the address. Errors (invalid format, address taken,
     no such user) have the class 'appauth_error_user' and a text in the settings
     language.

Usage:

     aa_set_email(conn, login, email, settings = aa_settings())

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

   email: An address or an empty value to remove it.

settings: Settings, the result of 'aa_settings()'.

Value:

     'TRUE' if the address was saved and 'FALSE' if it was removed (invisibly).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       aa_set_email(conn, "boss", "boss@example.com")
       aa_set_email(conn, "boss", NULL)
       DBI::dbDisconnect(conn)
     }
```

## aa_get_email

```text
User email

Description:

     User email

Usage:

     aa_get_email(conn, login)

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   login: Login.

Value:

     The address in lower case or 'NA_character_' if no address is set or the user does
     not exist. If the schema is not upgraded to version 7, also 'NA_character_'.

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       aa_set_email(conn, "boss", "Boss@Example.com")
       aa_get_email(conn, "boss")
       DBI::dbDisconnect(conn)
     }
```

## aa_request_password_reset

```text
Request password recovery

Description:

     Finds a user by login or email, creates a one-time token and calls
     'settings$send_reset(email, link, login)' to send an email with the link. Only the
     token hash stays in the database. The user's previous unused links stop working.

Usage:

     aa_request_password_reset(conn, identifier, settings = aa_settings())

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

identifier: The login or email the user entered.

settings: Settings, the result of 'aa_settings()' with 'reset_enabled = TRUE'.

Details:

     No email is sent if the user does not exist, has no email, is blocked by an
     administrator, or a limit is exceeded ('reset_max_per_hour' per user,
     'reset_max_per_minute' overall). The function result is meant for the journal: the
     user should be shown the same answer in every case, so that it is impossible to find
     out which logins and addresses exist.

     An error in 'send_reset' does not abort the function but is returned as
     'send_failed': the token is consumed in that case.

Value:

     A list (invisibly): 'sent' ('TRUE' if the email was sent), 'reason' ('"sent"',
     '"disabled"', '"no_user"', '"no_email"', '"blocked"', '"throttled"' or
     '"send_failed"') and 'login' (the found login or 'NA').

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")
       aa_set_email(conn, "boss", "boss@example.com")

       settings <- aa_settings(
         reset_enabled  = TRUE,
         reset_base_url = "https://apps.example.com/my_app",
         send_reset = function(email, link, login) message("Link for ", login, ":
         ", link)
       )
       aa_request_password_reset(conn, "boss", settings)$reason
       aa_request_password_reset(conn, "nobody", settings)$reason
       DBI::dbDisconnect(conn)
     }
```

## aa_reset_token_login

```text
User who owns a recovery link

Description:

     Checks the token from the link without changing anything: it must exist, be unused
     and not expired, and the user must not be blocked or deleted. Needed to show the new
     password form only for a working link.

Usage:

     aa_reset_token_login(conn, token)

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   token: Token from the link (the 'reset' parameter of the address bar).

Value:

     The user login or 'NULL'.

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_reset_token_login(conn, "not-a-token")
       DBI::dbDisconnect(conn)
     }
```

## aa_reset_password_with_token

```text
Set a new password by the link from the email

Description:

     Checks the token ('aa_reset_token_login()'), checks the new password against the
     rules from the settings and writes it. The token is one-time: a weak password is
     rejected with an error and does not spend the token, and after a successful change
     the link stops working. Along with the password, all of the user's auto-login tokens
     are revoked, the other recovery links are consumed, and the password change
     requirement and the lock for failed login attempts are cleared.

Usage:

     aa_reset_password_with_token(conn, token, password, settings = aa_settings())

Arguments:

    conn: A connection to the SQLite database ('DBI::dbConnect(RSQLite::SQLite(), ...)').

   token: Token from the link (the 'reset' parameter of the address bar).

password: New password.

settings: Settings, the result of 'aa_settings()'.

Details:

     A wrong, expired or used link raises an error of class 'appauth_error_user' with
     'reason = "reset_link_invalid"', a weak password an error of the same class with a
     password reason.

Value:

     The login of the user whose password was changed (invisibly).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       tryCatch(
         aa_reset_password_with_token(conn, "not-a-token", "new-password"),
         appauth_error_user = function(e) conditionMessage(e)
       )
       DBI::dbDisconnect(conn)
     }
```

