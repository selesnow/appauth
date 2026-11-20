# Find accounts with weak passwords

A hygiene check of the `users` table: finds users whose password is
stored in plain text, equals the login (lower and upper case too) or is
in the list of common weak passwords. The check works on hashes; the
function does not show plain-text passwords. The check can take a few
seconds per user because of strong hashing.

## Usage

``` r
aa_check_default_accounts(conn, common = aa_common_passwords())
```

## Arguments

- conn:

  A connection to the SQLite database that already has the `users`
  table.

- common:

  List of weak passwords to check, by default
  [`aa_common_passwords()`](https://alexey-seleznev.pro/appauth/reference/aa_common_passwords.md).

## Value

A table with `login`, `role` and `reason` columns: `plaintext` (the
password is stored in plain text), `login_as_password` (the password
equals the login) or `common_password` (a password from the weak list).
If there are no such users, the table is empty.

## Details

A single user can have several result rows, for example for the
plain-text password `root` of the login `root`.

## Examples

``` r
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
