# appauth reference: Passwords

Package version: 0.13.0. This file is generated automatically from the package help (`dev/skills/build_reference.R`) and must not be edited by hand.

Functions in this section:
`aa_hash_password()`, `aa_verify_password()`, `aa_is_password_hash()`, `aa_validate_password()`, `aa_validate_login()`, `aa_migrate_plaintext_passwords()`, `aa_check_default_accounts()`, `aa_common_passwords()`, `aa_weak_password_warning()`

## Contents

- [aa_hash_password](#aa_hash_password)
- [aa_verify_password](#aa_verify_password)
- [aa_is_password_hash](#aa_is_password_hash)
- [aa_validate_password](#aa_validate_password)
- [aa_validate_login](#aa_validate_login)
- [aa_migrate_plaintext_passwords](#aa_migrate_plaintext_passwords)
- [aa_check_default_accounts](#aa_check_default_accounts)
- [aa_common_passwords](#aa_common_passwords)
- [aa_weak_password_warning](#aa_weak_password_warning)

## aa_hash_password

```text
Hash a password

Description:

     Returns a scrypt hash ('sodium' package) for storing in the database. The hash
     contains the salt and parameters, so two calls with the same password give different
     strings, and verification is done by 'aa_verify_password()'. The hash is
     irreversible: the password cannot be recovered from it.

Usage:

     aa_hash_password(password)

Arguments:

password: The password, a non-empty string.

Details:

     The function does not check password length rules, use 'aa_validate_password()' for
     that.

Value:

     A string with the hash, starting with $7$.

Examples:

     hash <- aa_hash_password("secret-password")
     substr(hash, 1, 3)
     aa_verify_password("secret-password", hash)
```

## aa_verify_password

```text
Verify a password against a hash

Description:

     Compares the entered password with the stored hash. If the stored value is not a
     hash (for example, a plain-text password), the result is always 'FALSE': plain-text
     passwords are not compared. A corrupted hash and invalid arguments also give
     'FALSE'; the function does not throw errors.

Usage:

     aa_verify_password(password, stored)

Arguments:

password: The entered password.

  stored: The value from the 'password' column of the 'users' table.

Value:

     'TRUE' or 'FALSE'.

Examples:

     hash <- aa_hash_password("secret")
     aa_verify_password("secret", hash)
     aa_verify_password("other", hash)

     # a plain-text password does not pass verification, even if it matches
     aa_verify_password("root", "root")
```

## aa_is_password_hash

```text
Is the value a password hash

Description:

     Distinguishes a hash created by 'aa_hash_password()' from a plain-text password. The
     function is vectorized; 'NA' is not considered a hash.

Usage:

     aa_is_password_hash(x)

Arguments:

       x: A character vector, for example the 'password' column of the 'users' table.

Value:

     A logical vector of the same length.

Examples:

     aa_is_password_hash(c(aa_hash_password("secret"), "root", NA))
```

## aa_validate_password

```text
Validate a new password against the rules

Description:

     Checks a password being set for a user (on creation or reset). The rules come from
     the settings: minimum and maximum length are counted in characters, not bytes. The
     limits apply only to new passwords; existing passwords are not affected.

Usage:

     aa_validate_password(password, settings = aa_settings(), login = NULL)

Arguments:

password: The password to check.

settings: Settings, the result of 'aa_settings()'.

   login: User login, needed to check whether the password equals the login (optional).

Details:

     If the settings have 'password_policy = "reject"', weak passwords (from the
     'aa_common_passwords()' list, equal to the login, one repeated character) are also
     an error. The '"warn"' mode does not reject the password: a weak password is
     reported by 'aa_weak_password_warning()'.

Value:

     'NULL' if the password is fine, otherwise the error text (in the settings language).

Examples:

     aa_validate_password("abc")
     aa_validate_password("long-enough-password")
     aa_validate_password("long-enough-password", aa_settings(password_min = 30))
```

## aa_validate_login

```text
Validate a new user's login

Description:

     The login must not be empty, must not start or end with whitespace (login compares
     the login exactly, so such logins would cause confusion; the input field in the
     package UI trims edge whitespace itself) and must not be longer than 'login_max'
     characters from the settings.

Usage:

     aa_validate_login(login, settings = aa_settings())

Arguments:

   login: The login to check.

settings: Settings, the result of 'aa_settings()'.

Value:

     'NULL' if the login is fine, otherwise the error text (in the settings language).

Examples:

     aa_validate_login("alsey")
     aa_validate_login("   ")
     aa_validate_login(" alsey")
```

## aa_migrate_plaintext_passwords

```text
Migrate passwords from plain text to hashes

Description:

     A one-time migration for apps with legacy home-grown authentication, where passwords
     in the 'users' table are stored in plain text. All values of the 'password' column
     that are not hashes are replaced with scrypt hashes. Already hashed passwords are
     skipped, so the function can be run repeatedly.

Usage:

     aa_migrate_plaintext_passwords(db_path, backup = TRUE, dry_run = FALSE)

Arguments:

 db_path: Path to the SQLite database file.

  backup: 'TRUE' (default) - a copy next to the database named <database>.bak_<date>, a
          string - your own path for the copy, 'FALSE' - no copy (not recommended).

 dry_run: If 'TRUE', change nothing and only show whose passwords would be migrated.

Details:

     How it works: before any change a backup copy of the database file is made (if there
     is something to change and 'backup' is not 'FALSE'), all changes run in a single
     transaction, and every new hash is verified against the original password before
     being written. On any error the changes are rolled back. The function never prints
     passwords.

     *Run the function while the app is stopped.* The backup contains plain-text
     passwords: delete it after checking (and make sure it is not in synchronized folders
     or in git). After the migration, logging in with the old passwords still works,
     because the entered password is verified against the new hash.

Value:

     A list (invisibly): 'migrated' (logins whose passwords were or would be migrated),
     'skipped' (logins whose password is already a hash), 'backup' (path to the copy or
     'NA'), 'dry_run'.

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       db <- tempfile(fileext = ".db")
       conn <- DBI::dbConnect(RSQLite::SQLite(), db)
       DBI::dbExecute(conn, "CREATE TABLE users (login TEXT, password TEXT, role
       TEXT)")
       DBI::dbExecute(conn, "INSERT INTO users VALUES ('alsey', 'plain-secret',
       'admin')")
       DBI::dbDisconnect(conn)

       # what would be migrated
       aa_migrate_plaintext_passwords(db, dry_run = TRUE)

       # run without a backup (in this example only; keep the backup in real use)
       aa_migrate_plaintext_passwords(db, backup = FALSE)
     }
```

## aa_check_default_accounts

```text
Find accounts with weak passwords

Description:

     A hygiene check of the 'users' table: finds users whose password is stored in plain
     text, equals the login (lower and upper case too) or is in the list of common weak
     passwords. The check works on hashes; the function does not show plain-text
     passwords. The check can take a few seconds per user because of strong hashing.

Usage:

     aa_check_default_accounts(conn, common = aa_common_passwords())

Arguments:

    conn: A connection to the SQLite database that already has the 'users' table.

  common: List of weak passwords to check, by default 'aa_common_passwords()'.

Details:

     A single user can have several result rows, for example for the plain-text password
     'root' of the login 'root'.

Value:

     A table with 'login', 'role' and 'reason' columns: 'plaintext' (the password is
     stored in plain text), 'login_as_password' (the password equals the login) or
     'common_password' (a password from the weak list). If there are no such users, the
     table is empty.

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
       aa_init_db(conn)
       DBI::dbExecute(
         conn, "INSERT INTO users (login, password, role) VALUES (?, ?, 'user')",
         params = list("tester", aa_hash_password("tester"))
       )
       aa_check_default_accounts(conn)
       DBI::dbDisconnect(conn)
     }
```

## aa_common_passwords

```text
List of common weak passwords

Description:

     Used by 'aa_check_default_accounts()' by default.

Usage:

     aa_common_passwords()

Value:

     A character vector.

Examples:

     head(aa_common_passwords())
```

## aa_weak_password_warning

```text
Weak password warning

Description:

     In the 'password_policy = "warn"' mode (the default) a weak password is accepted,
     but the user should be told to choose a stronger one: the built-in modules show this
     as a notification after a successful password change. The function is for apps with
     their own interface. A password is weak if it is in the 'aa_common_passwords()'
     list, equals the login (case-insensitive) or consists of one repeated character.

Usage:

     aa_weak_password_warning(password, settings = aa_settings(), login = NULL)

Arguments:

password: The accepted password.

settings: Settings, the result of 'aa_settings()'.

   login: User login (optional).

Value:

     The warning text (in the settings language), or 'NULL' if the mode is not '"warn"'
     or there are no weaknesses.

Examples:

     aa_weak_password_warning("123456")
     aa_weak_password_warning("boss", login = "Boss")
     aa_weak_password_warning("long-and-unusual-phrase")
```

