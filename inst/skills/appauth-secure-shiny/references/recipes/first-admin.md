# Recipe: the first administrator

On an empty database (a `users` table with no records) the login module offers to create the first administrator. Whoever opens the app first gets the `admin_role` role: after deployment you must close this window yourself.

## How it works

* `aa_auth_server()` checks `aa_users_exist(conn)`. If there are no users, a "Create administrator" form (login, password, confirmation) is shown instead of the login.
* Creation is done by `aa_create_first_admin()`: a single SQL statement that inserts a record only if the table is empty. If two people submit the form at the same time, exactly one administrator is created.
* After creation the user is signed in immediately, event `first_admin_created`.

## How to close the window

Option 1 (recommended for production deployment): create the administrator with a script before the app is opened to outsiders.

```r
library(appauth)
conn <- DBI::dbConnect(RSQLite::SQLite(), "app.db")
aa_init_db(conn)
aa_create_first_admin(conn, "admin", Sys.getenv("APP_ADMIN_PASSWORD"))   # password from an environment variable, not from code
DBI::dbDisconnect(conn)
```

Do not write the password into code or into command history: take it from an environment variable or enter it interactively (`askpass`/`readline`), then change it through the app.

Option 2: open the app yourself right after launch and create the administrator through the form while it is not reachable by outsiders (closed port, VPN).

## Spare administrator

Locking per login allows someone to deliberately lock another person's login, administrators included, so a second active administrator is needed: create one on the "Access" tab right after the first. The package will not let you lock, delete or demote the last active administrator.

## Existing user database

If the database already contains users (a migration from an old app), the window is not shown. Make sure at least one user has the administrator role (`aa_list_users(conn)`), otherwise nobody will be able to manage users: in that case assign the role with a script, `aa_set_role(conn, "login", "admin")`.

## Test

```r
con <- new_db()                                  # empty database
run_auth(con, {
  session$setInputs(setup_login = "boss", setup_password = "secret123", setup_confirm = "secret123", setup_btn = 1)
  expect_equal(session$returned$user(), list(login = "boss", role = "admin"))
})
```

Login after creation must not ask for the password a second time, and an attempt to create a "first administrator" when a user already exists does nothing.
