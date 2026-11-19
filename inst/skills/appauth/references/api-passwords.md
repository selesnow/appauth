# appauth reference: Passwords

Package version: 0.8.0. This file was generated automatically from the package help pages (`dev/skills/build_reference.R`) and is not edited by hand.

Functions in this section: 
`aa_hash_password()`, `aa_verify_password()`, `aa_is_password_hash()`, `aa_validate_password()`, `aa_validate_login()`, `aa_migrate_plaintext_passwords()`, `aa_check_default_accounts()`, `aa_common_passwords()`, `aa_weak_password_warning()`

## aa_hash_password

```text
Hash a password

Description:

     Returns a scrypt hash (package 'sodium') for storing in the database. The hash
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

     Compares the entered password with the stored hash. If the stored value is not a hash
     (for example, a plaintext password), the result is always 'FALSE': plaintext
     passwords are not compared. A corrupted hash and invalid arguments also give 'FALSE';
     the function does not throw errors.

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
     
     # a plaintext password fails verification even if it matches
     aa_verify_password("root", "root")
```

## aa_is_password_hash

```text
Is the value a password hash

Description:

     Distinguishes a hash created by 'aa_hash_password()' from a plaintext password. The
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

     Validates a password that is being set for a user (on creation or reset). The rules
     come from the settings: the minimum and maximum length are counted in characters, not
     bytes. The restrictions apply only to new passwords; existing passwords are not
     affected.

Usage:

     aa_validate_password(password, settings = aa_settings(), login = NULL)
     
Arguments:

password: The password to validate.

settings: Settings, the result of 'aa_settings()'.

   login: The user's login, needed to check whether the password matches the login
          (optional).

Details:

     If the settings have 'password_policy = "reject"', weak passwords (from the
     'aa_common_passwords()' list, equal to the login, or consisting of a single repeated
     character) are also treated as errors. The '"warn"' mode does not reject the
     password: a weak password is reported by 'aa_weak_password_warning()'.

Value:

     'NULL' if the password is acceptable, otherwise the error text (in the settings
     language).

Examples:

     aa_validate_password("abc")
     aa_validate_password("long-enough-password")
     aa_validate_password("abc", aa_settings(texts = aa_texts("en")))
```

## aa_validate_login

```text
Validate the login of a new user

Description:

     The login must not be empty, must not start or end with a space (sign-in compares the
     login exactly, so such logins would cause confusion; the package's input field trims
     spaces at the edges by itself) and must not be longer than 'login_max' characters
     from the settings.

Usage:

     aa_validate_login(login, settings = aa_settings())
     
Arguments:

   login: The login to validate.

settings: Settings, the result of 'aa_settings()'.

Value:

     'NULL' if the login is acceptable, otherwise the error text (in the settings
     language).

Examples:

     aa_validate_login("alsey")
     aa_validate_login("   ")
     aa_validate_login(" alsey")
```

## aa_migrate_plaintext_passwords

```text
Migrate passwords from plaintext to hashes

Description:

     A one-time migration for applications with legacy home-grown authentication where
     passwords in the 'users' table are stored in plaintext. All values of the 'password'
     column that are not hashes are replaced with scrypt hashes. Already hashed passwords
     are skipped, so the function can be run repeatedly.

Usage:

     aa_migrate_plaintext_passwords(db_path, backup = TRUE, dry_run = FALSE)
     
Arguments:

 db_path: Path to the SQLite database file.

  backup: 'TRUE' (default) - a copy next to the database named <database>.bak_<date>, a
          string - your own path for the copy, 'FALSE' - no copy (not recommended).

 dry_run: If 'TRUE', change nothing and only show whose passwords would be migrated.

Details:

     Order of operations: before any changes a backup copy of the database file is made
     (if there is anything to change and 'backup' is not 'FALSE'), all changes are made in
     a single transaction, and each new hash is verified against the original password
     before being written. On any error the changes are rolled back. The function never
     prints passwords.

     *Run the function while the application is stopped.* The backup contains plaintext
     passwords: delete it after checking (and make sure it is not in synchronized folders
     or in git). After the migration, signing in with the old passwords still works,
     because the entered password is verified against the new hash.

Value:

     A list (invisibly): 'migrated' (logins whose passwords were migrated or would be
     migrated), 'skipped' (logins whose password is already a hash), 'backup' (path to the
     copy or 'NA'), 'dry_run'.

Examples:

     if (requireNamespace("RSQLite", quietly = TRUE)) {
       db <- tempfile(fileext = ".db")
       conn <- DBI::dbConnect(RSQLite::SQLite(), db)
       DBI::dbExecute(conn, "CREATE TABLE users (login TEXT, password TEXT, role TEXT)")
       DBI::dbExecute(conn, "INSERT INTO users VALUES ('alsey', 'plain-secret', 'admin')")
       DBI::dbDisconnect(conn)
     
       # what would be migrated
       aa_migrate_plaintext_passwords(db, dry_run = TRUE)
     
       # run without a backup (in the example; in real work keep the backup)
       aa_migrate_plaintext_passwords(db, backup = FALSE)
     }
```

## aa_check_default_accounts

```text
Find accounts with weak passwords

Description:

     A hygiene check of the 'users' table: finds users whose password is stored in
     plaintext, equals the login (in lower and upper case too) or is in the list of common
     weak passwords. The check works on hashes; the function does not show plaintext
     passwords. The check can take several seconds per user because of the strong
     hashing.

Usage:

     aa_check_default_accounts(conn, common = aa_common_passwords())
     
Arguments:

    conn: A connection to the SQLite database that already has the 'users' table.

  common: The list of weak passwords to check, 'aa_common_passwords()' by default.

Details:

     There can be several result rows for one user, for example for the plaintext
     password 'root' of the login 'root'.

Value:

     A table with the columns 'login', 'role' and 'reason': 'plaintext' (the password is
     stored in plaintext), 'login_as_password' (the password equals the login) or
     'common_password' (the password is from the weak list). If there are no such users,
     the table is empty.

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

     In the 'password_policy = "warn"' mode (default) a weak password is accepted, but the
     user should be told that a stronger one is better: the built-in modules show this as
     a notification after a successful password change. The function is needed by
     applications with their own interface. A password is considered weak if it is in the
     'aa_common_passwords()' list, equals the login (case-insensitive) or consists of a
     single repeated character.

Usage:

     aa_weak_password_warning(password, settings = aa_settings(), login = NULL)
     
Arguments:

password: The accepted password.

settings: Settings, the result of 'aa_settings()'.

   login: The user's login (optional).

Value:

     The warning text (in the settings language), or 'NULL' if the mode is not '"warn"' or
     there are no weaknesses.

Examples:

     aa_weak_password_warning("123456")
     aa_weak_password_warning("boss", login = "Boss")
     aa_weak_password_warning("long-and-unusual-phrase")
```

