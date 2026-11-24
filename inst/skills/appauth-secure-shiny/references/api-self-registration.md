# appauth reference: Self-registration

Package version: 0.13.0. This file is generated automatically from the package help (`dev/skills/build_reference.R`) and must not be edited by hand.

Functions in this section:
`aa_register_user()`, `aa_registration_token_login()`, `aa_confirm_registration()`

## Contents

- [aa_register_user](#aa_register_user)
- [aa_registration_token_login](#aa_registration_token_login)
- [aa_confirm_registration](#aa_confirm_registration)

## aa_register_user

```text
Request self-registration

Description:

     Checks the login, password, email and the domain and rate limits from the settings,
     and stores a pending registration with the password hash. With
     'registration_verify_email = TRUE' a one-time confirmation link is sent with
     'settings$send_reset(email, link, login)'; with 'FALSE' the account is created
     immediately. Only the token hash is stored in the database.

Usage:

     aa_register_user(conn, login, password, email, settings = aa_settings())

Arguments:

    conn: Connection with the 'aa_init_db()' schema.

   login: Desired login.

password: Desired password (only the hash is stored).

   email: Email address of the visitor.

settings: Settings, the result of 'aa_settings()' with 'registration_enabled = TRUE'.

Details:

     The result is meant for the journal and for choosing a generic on-screen answer: the
     reason 'user_exists' or 'email_exists' must not be shown to a visitor, because that
     would reveal which accounts exist.

Value:

     A list (invisibly): 'sent', 'reason' and 'login'. Reasons: 'created', 'sent',
     'disabled', 'user_exists', 'email_exists', 'email_invalid', 'registration_domain',
     'registration_throttled', 'send_failed' or a login or password validation reason.

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_create_first_admin(conn, "boss", "boss-password")

       settings <- aa_settings(
         registration_enabled = TRUE,
         registration_verify_email = FALSE,
         registration_role = "viewer"
       )
       aa_register_user(conn, "worker", "worker-password", "worker@example.com",
                        settings)$reason
       aa_list_users(conn)
       DBI::dbDisconnect(conn)
     }
```

## aa_registration_token_login

```text
User who owns a registration link

Description:

     Checks the confirmation token without changing anything: the token must be unused,
     not expired, and the login and address must still be available. The new password
     form is shown only for a working link.

Usage:

     aa_registration_token_login(conn, token)

Arguments:

    conn: Connection with the 'aa_init_db()' schema.

   token: Token from the ?register=<token> link.

Value:

     The login or 'NULL'.

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       aa_registration_token_login(conn, "not-a-token")
       DBI::dbDisconnect(conn)
     }
```

## aa_confirm_registration

```text
Create an account from a registration link

Description:

     Checks the token again, consumes it atomically and creates the user with the hashed
     password stored in the pending registration. A weak password has already been
     rejected when the registration was requested; a conflict with an account created
     meanwhile leaves the token unused and raises an error of class 'appauth_error_user'.

Usage:

     aa_confirm_registration(conn, token, settings = aa_settings())

Arguments:

    conn: Connection with the 'aa_init_db()' schema.

   token: Token from the address.

settings: Settings, the result of 'aa_settings()'.

Value:

     The login of the created user (invisibly).

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       settings <- aa_settings(
         registration_enabled = TRUE,
         registration_verify_email = FALSE
       )
       tryCatch(
         aa_confirm_registration(conn, "not-a-token", settings),
         appauth_error_user = function(e) conditionMessage(e)
       )
       DBI::dbDisconnect(conn)
     }
```

