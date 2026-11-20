# Verify login and password (login)

Looks up the user by login (exact, case-sensitive) and verifies the
password against the hash. If the user does not exist, verification is
still run against a dummy hash so the response time does not reveal
whether the login exists. A plain-text password in the database is never
accepted.

## Usage

``` r
aa_authenticate(conn, login, password)
```

## Arguments

- conn:

  A connection to the SQLite database
  (`DBI::dbConnect(RSQLite::SQLite(), ...)`).

- login:

  Login.

- password:

  The entered password.

## Value

A one-row table with `login`, `role`, `blocked` and `must_change`
columns (the password is not included in the result), or `NULL` if the
login or password is wrong.

## Details

For a user blocked by an administrator, with a correct password a row
with `blocked = 1` is returned: what to do next is up to the calling
code (the login module reports the block only to someone who knows the
password). With a wrong password the result is always `NULL`.

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  aa_init_db(conn)
  aa_create_first_admin(conn, "boss", "boss-password")
  aa_authenticate(conn, "boss", "boss-password")
  aa_authenticate(conn, "boss", "wrong")
  DBI::dbDisconnect(conn)
}
```
