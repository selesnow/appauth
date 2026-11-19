# appauth reference: UI modules and app helpers

Reference built from appauth 0.8.0. The file was generated automatically from the package help pages and is not edited by hand.

Functions in this section:
`aa_app_head()`, `aa_auth_ui()`, `aa_auth_server()`, `aa_users_ui()`, `aa_users_server()`, `aa_password_ui()`, `aa_password_server()`, `aa_totp_ui()`, `aa_totp_server()`, `aa_session_guard()`, `aa_register_module()`

## aa_app_head

```text
Include appauth styles and scripts

Description:

     Call once in the app UI (inside 'fluidPage()' or 'tagList()'). Adds the CSS of the
     login form and the users tab, and the JS that reads, writes and deletes the
     auto-login cookie.

Usage:

     aa_app_head()
     
Details:

     The look is controlled by --aa-* CSS variables (for example '--aa-primary'), which
     you override in your own CSS placed after 'aa_app_head()'. The light theme is enabled
     by the 'aa-theme-light' class on <body> or on a parent element.

     The cookie is written with 'SameSite=Lax', and on HTTPS also with 'Secure'.

Value:

     A 'shiny.tag.list' object that attaches the 'appauth' dependency.

Examples:

     ui <- shiny::fluidPage(
       aa_app_head()
       # ... the rest of the app UI
     )
```

## aa_auth_ui

```text
Login module: UI

Description:

     The login form (or the form for creating the first administrator when there are no
     users yet). When the user is logged in, the module shows nothing. Styles are
     included via 'aa_app_head()'.

Usage:

     aa_auth_ui(id)
     
Arguments:

      id: Module id.

Value:

     A Shiny UI element.

See Also:

     'aa_auth_server()'

Examples:

     ui <- shiny::fluidPage(aa_app_head(), aa_auth_ui("auth"))
```

## aa_auth_server

```text
Login module: server

Description:

     Login by username and password with brute-force protection ('aa_login_gate()'),
     creation of the first administrator on an empty database, auto-login by cookie (if
     enabled in the settings) and logout. The module reports all events to the 'on_event'
     hook (catalog in 'aa_events()') and writes nothing to logs itself.

Usage:

     aa_auth_server(
       id,
       conn,
       settings = aa_settings(),
       on_event = NULL,
       title = NULL,
       logo = NULL,
       cookie_name = "appauth_token"
     )
     
Arguments:

      id: Module id, the same as in 'aa_auth_ui()'.

    conn: Database connection with the 'aa_init_db()' schema.

settings: Settings, the result of 'aa_settings()'.

on_event: Event hook function(event, user, session_id, value) or 'NULL'.

   title: Login form title. Defaults to the 'login_title' text.

    logo: URL of an image above the title (for example '"logo.png"' from the 'www'
          folder) or 'NULL'.

cookie_name: Name of the auto-login cookie. Cookies are not isolated by port, so apps on
          the same host need different names.

Details:

     If the password was set for the user by an administrator ('must_change'), after the
     correct password is entered the password change form is shown, and the user gets
     into the app only after changing it.

Value:

     A list: 'user' (reactive value, a list with 'login' and 'role', or 'NULL'),
     'logged_in' (reactive logical), 'role' (reactive role or 'NULL'), the function
     'token()' (auto-login token of this session or 'NULL', needed by
     'aa_session_guard()'), the function 'logout(reason = NULL, reload = FALSE)' and the
     function 'logout_all(reload = TRUE)'. Without 'reason' this is a regular logout
     (event 'logout'); with 'reason' ('"blocked"', '"deleted"', '"role_changed"',
     '"token_revoked"') it is a forced one ('session_forced_logout'). With
     'reload = TRUE' the page is reloaded so that the modules of the previous user
     disappear.

     'logout_all()' is "log out on all devices": it revokes all the user's tokens (event
     'sessions_revoked') and logs out immediately; open sessions on other devices are
     closed by 'aa_session_guard()' at its next check. Show the user a confirmation
     dialog before calling it: the button throws them out everywhere.

Two-factor authentication:

     With 'totp_enabled = TRUE' in the settings ('aa_settings()'), a user who has 2FA
     enabled ('aa_totp_server()') enters, after the correct password, a code from the
     authenticator app or a recovery code. Until then no auto-login token is issued and
     the successful login attempt is not recorded: wrong codes count as failed login
     attempts, and the login is locked by the same rules as for password guessing.
     Login by the auto-login cookie does not ask for the second factor (the cookie was
     issued after it was passed). The module reports the events 'totp_failed' and
     'recovery_code_used'.

Password recovery by email:

     With 'reset_enabled = TRUE' in the settings ('aa_settings()'), a "Forgot password?"
     link appears on the login form (default text 'forgot_link'). The user enters a
     username or email and receives an email with the link
     <reset_base_url>/?reset=<token>, and the on-screen answer is always the same,
     regardless of whether the user was found. The module itself reads the 'reset'
     parameter from the address bar, removes it from the address and shows the new
     password form if the link is valid. After the password change the user logs in as
     usual: they are not let in automatically. The module reports the events
     'password_reset_requested', 'password_reset_done' and 'password_reset_failed'.
     UI-free logic: 'aa_request_password_reset()' and 'aa_reset_password_with_token()'.

Google login:

     With 'google_enabled = TRUE' in the settings ('aa_settings()'), a "Sign in with
     Google" button appears on the login form. The user confirms the login at Google and
     returns to 'google_redirect_uri'; the package verifies the signature and contents of
     the Google token, the organization domain ('google_domains') and finds the user *by
     email among already created users*: the login does not create new users, the role is
     taken from the database, and a blocked user does not get in. The app's two-factor
     code is not requested in this case (Google performs the confirmation). The 'state'
     from the address is compared with a short-lived cookie of the browser that started
     the login, so a foreign return link cannot be substituted. With
     'password_login = FALSE' the password form is hidden and password login attempts are
     rejected on the server. The module reports 'login_success' with the value 'google'
     and 'google_login_failed' (reason and email in 'value'); on failure the user is shown
     a generic text. If the page is open not at the 'google_redirect_uri' address (for
     example the app is opened by IP while the return is configured for a domain), the
     button sends the user to the return address, and the login starts there on its own
     (parameter '?google=1'): 'state' is stored in the cookie of the site address, and
     cookies by IP and by domain are different. Password login and cookie auto-login work
     independently on each address.

     The role and login are taken from the database, not from the entered string. The
     'conn' connection belongs to the app: close it when the session ends.

See Also:

     'aa_auth_ui()'

Examples:

     ## Not run:
     
     server <- function(input, output, session) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), "app.db")
       aa_init_db(conn)
       session$onSessionEnded(function() DBI::dbDisconnect(conn))
     
       auth <- aa_auth_server("auth", conn, on_event = log_event)
       output$app <- shiny::renderUI(if (auth$logged_in()) main_ui())
     }
     ## End(Not run)
```

## aa_users_ui

```text
Users module: UI

Description:

     A table of users with statuses and an add button. Double-clicking a row opens the
     user card. The module is visible only to an administrator and shows nothing to
     others. Styles are included via 'aa_app_head()'.

Usage:

     aa_users_ui(id)
     
Arguments:

      id: Module id.

Details:

     The rest of the contents of the "Access" tab (permissions editor, log toggles) is
     assembled by the app, for example 'tabPanel("Access", aa_users_ui("users"),
     my_permissions_editor())'.

Value:

     A Shiny UI element.

See Also:

     'aa_users_server()'

Examples:

     ui <- shiny::fluidPage(aa_app_head(), aa_users_ui("users"))
```

## aa_users_server

```text
Users module: server

Description:

     User management for an administrator: adding, changing the role, resetting the
     password, blocking and unblocking, clearing the login lockout, deleting. The rules
     (you cannot block or delete yourself, you cannot be left without an active
     administrator) are checked on the server by the package functions; the UI merely
     does not show the disallowed buttons.

Usage:

     aa_users_server(
       id,
       conn,
       auth,
       settings = aa_settings(),
       on_event = NULL,
       extra_card_ui = NULL,
       extra_card_server = NULL
     )
     
Arguments:

      id: Module id, the same as in 'aa_users_ui()'.

    conn: Database connection.

    auth: Authorization object, the result of 'aa_auth_server()'.

settings: Settings, the result of 'aa_settings()'.

on_event: Event hook function(event, user, session_id, value) or 'NULL'.

extra_card_ui, extra_card_server: Card extension slots, see the "Extension slots"
          section.

Details:

     The module does not depend on the app's permission matrix: users can be managed only
     by a user with the role 'settings$admin_role', which is additionally checked against
     the database on every action. The target of an action is taken from the server-side
     state of the open card, not from a value sent by the browser.

Value:

     A list with the function 'refresh()', which redraws the table (for example after
     changes made not through the module).

Extension slots:

     The app can add its own block to the user card.

        * 'extra_card_ui(login, ns)' returns the UI of the block. Element ids must be
          wrapped in 'ns()'.

        * 'extra_card_server(input, output, session, login)' is called once at module
          start inside its namespace; 'login' is a reactive value with the login of the
          open card. The block handlers are registered here.

See Also:

     'aa_users_ui()', 'aa_auth_server()'

Examples:

     ## Not run:
     
     auth <- aa_auth_server("auth", conn)
     shiny::observe({
       if (auth$logged_in()) aa_users_server("users", conn, auth, on_event = log_event)
     })
     ## End(Not run)
```

## aa_password_ui

```text
Own password change module: UI

Description:

     A form "current password, new password, confirmation". Shown only to a logged-in
     user. Place it where the app has a personal account or settings (on a tab or in a
     modal window). Styles are included via 'aa_app_head()'.

Usage:

     aa_password_ui(id)
     
Arguments:

      id: Module id.

Value:

     A Shiny UI element.

See Also:

     'aa_password_server()'

Examples:

     ui <- shiny::fluidPage(aa_app_head(), aa_password_ui("password"))
```

## aa_password_server

```text
Own password change module: server

Description:

     The user confirms the current password and sets a new one
     ('aa_change_own_password()'). Auto-login tokens of the other sessions are revoked,
     the current session keeps working. The module reports the change to the 'on_event'
     hook with the event 'password_changed'.

Usage:

     aa_password_server(id, conn, auth, settings = aa_settings(), on_event = NULL)
     
Arguments:

      id: Module id, the same as in 'aa_password_ui()'.

    conn: Database connection.

    auth: Authorization object, the result of 'aa_auth_server()'.

settings: Settings, the result of 'aa_settings()'.

on_event: Event hook function(event, user, session_id, value) or 'NULL'.

Value:

     A list with the reactive value 'changed': the number of successful password changes
     in this session (can be used to close a window or show a message).

See Also:

     'aa_password_ui()'

Examples:

     ## Not run:
     
     auth <- aa_auth_server("auth", conn)
     aa_password_server("password", conn, auth, on_event = log_event)
     ## End(Not run)
```

## aa_totp_ui

```text
Two-factor authentication module: UI

Description:

     A block for the personal account: two-factor authentication status, setup (secret,
     QR code and confirmation by code) and disabling. Shows nothing until 'totp_enabled'
     is turned on in the settings. Styles are included via 'aa_app_head()'.

Usage:

     aa_totp_ui(id)
     
Arguments:

      id: Module id.

Value:

     A Shiny UI element.

See Also:

     'aa_totp_server()'

Examples:

     ui <- shiny::fluidPage(aa_app_head(), aa_totp_ui("totp"))
```

## aa_totp_server

```text
Two-factor authentication module: server

Description:

     The user enables and disables two-factor authentication (TOTP) on their own:

Usage:

     aa_totp_server(id, conn, auth, settings = aa_settings(), on_event = NULL)
     
Arguments:

      id: Module id, the same as in 'aa_totp_ui()'.

    conn: Database connection.

    auth: Authorization object, the result of 'aa_auth_server()'.

settings: Settings, the result of 'aa_settings()' with 'totp_enabled = TRUE'.

on_event: Event hook function(event, user, session_id, value) or 'NULL'.

Details:

        * *enabling*: the button creates a secret ('aa_totp_setup()'), shows a QR code (if
          the 'qrcode' package is installed) and a key for manual entry, and after a code
          from the app is entered ('aa_totp_enable()') turns the protection on and shows
          10 recovery codes *once*. The user's other sessions are terminated on enabling;

        * *disabling*: requires the password and a code (or a recovery code), otherwise
          someone who took over an open session could remove the protection.

     Wrong codes count as failed login attempts ('aa_record_attempt()'), so guessing a
     code in the personal account locks the login just like guessing a password. Events:
     'totp_enabled', 'totp_disabled', 'totp_failed'.

Value:

     A list with the function 'refresh()', which redraws the block.

See Also:

     'aa_totp_ui()', 'aa_auth_server()'

Examples:

     ## Not run:
     
     auth <- aa_auth_server("auth", conn, settings)
     shiny::observe({
       if (auth$logged_in()) aa_totp_server("totp", conn, auth, settings, on_event = log_event)
     })
     ## End(Not run)
```

## aa_session_guard

```text
Forcibly terminate invalid sessions

Description:

     Every 'session_check_seconds' (from 'aa_settings()') checks the open session
     ('aa_user_session_valid()'). If the user was blocked, deleted or had their role
     changed, the session is terminated via 'auth$logout()': the 'on_event' hook receives
     'session_forced_logout' with the reason, and tokens are revoked. Thanks to this,
     blocking and role downgrade take effect within the check interval rather than at the
     next login.

Usage:

     aa_session_guard(
       auth,
       conn,
       settings = aa_settings(),
       reload = TRUE,
       cleanup_minutes = 60
     )
     
Arguments:

    auth: The result of 'aa_auth_server()'.

    conn: Database connection.

settings: Settings, the result of 'aa_settings()'.

  reload: Reload the page after logout so that the modules of the previous user
          disappear. 'TRUE' is recommended.

cleanup_minutes: How often to clean up stale records, in minutes.

Details:

     If the database cannot be read, the session is not terminated.

     The session token ('auth$token()') is checked too: a password reset of the user or
     "terminate all sessions" also terminates open sessions. Every 'cleanup_minutes' the
     guard also deletes stale login attempts and tokens ('aa_cleanup()').

Value:

     Invisibly, a Shiny observer (it can be stopped with $destroy()).

Examples:

     ## Not run:
     
     auth <- aa_auth_server("auth", conn)
     aa_session_guard(auth, conn)
     ## End(Not run)
```

## aa_register_module

```text
Register a module's server part only if the permission is granted

Description:

     Calls 'server()' once per session when the logged-in user gets the permission
     'permission'. For other users the module's server part is not registered at all, and
     permissions still have to be checked inside handlers ('aa_require()'): registration
     protects against unnecessary work, not against forged requests.

Usage:

     aa_register_module(auth, permission, provider, server)
     
Arguments:

    auth: The result of 'aa_auth_server()'.

permission: Permission name.

provider: Permission source, see 'aa_can()'.

  server: A function without arguments that registers the module, for example
          'function() mod_tasks_server("tasks")'.

Details:

     Registered modules cannot be removed from a session, so on logout use
     'auth$logout(reload = TRUE)': the page will reload and the modules of the previous
     user will disappear.

Value:

     Invisibly, a Shiny observer.

Examples:

     ## Not run:
     
     provider <- aa_permissions_from_matrix(conf$access_managemet)
     aa_register_module(auth, "Tasks", provider, function() mod_tasks_server("tasks"))
     ## End(Not run)
```
