# Migrate passwords from plain text to hashes

A one-time migration for apps with legacy home-grown authentication,
where passwords in the `users` table are stored in plain text. All
values of the `password` column that are not hashes are replaced with
scrypt hashes. Already hashed passwords are skipped, so the function can
be run repeatedly.

## Usage

``` r
aa_migrate_plaintext_passwords(db_path, backup = TRUE, dry_run = FALSE)
```

## Arguments

- db_path:

  Path to the SQLite database file.

- backup:

  `TRUE` (default) - a copy next to the database named
  `<database>.bak_<date>`, a string - your own path for the copy,
  `FALSE` - no copy (not recommended).

- dry_run:

  If `TRUE`, change nothing and only show whose passwords would be
  migrated.

## Value

A list (invisibly): `migrated` (logins whose passwords were or would be
migrated), `skipped` (logins whose password is already a hash), `backup`
(path to the copy or `NA`), `dry_run`.

## Details

How it works: before any change a backup copy of the database file is
made (if there is something to change and `backup` is not `FALSE`), all
changes run in a single transaction, and every new hash is verified
against the original password before being written. On any error the
changes are rolled back. The function never prints passwords.

**Run the function while the app is stopped.** The backup contains
plain-text passwords: delete it after checking (and make sure it is not
in synchronized folders or in git). After the migration, logging in with
the old passwords still works, because the entered password is verified
against the new hash.

## Examples

``` r
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
