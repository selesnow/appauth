# appauth: Secure Authentication and User Management for Shiny

The package combines what must be the same in every Shiny application:
password storage as hashes, brute-force protection, blocking and
deletion of users, auto sign-in tokens, server-side permission checks
and versioned migrations of the database schema (SQLite, DuckDB, MySQL /
MariaDB, PostgreSQL). Everything that differs from application to
application (the matrix of roles and permissions, log switches, the
contents of the access tab) stays with the application and is attached
through extension points.

## Details

See the `architecture-and-security` vignette for details on the design
and the threat model.

## See also

Useful links:

- <https://alexey-seleznev.pro/appauth/>

- <https://github.com/selesnow/appauth>

- Report bugs at <https://github.com/selesnow/appauth/issues>

## Author

**Maintainer**: Alexey Seleznev <selesnow@gmail.com>
([ORCID](https://orcid.org/0000-0003-0410-7385))

Authors:

- Alexey Seleznev <selesnow@gmail.com>
  ([ORCID](https://orcid.org/0000-0003-0410-7385))

Other contributors:

- Netpeak \[copyright holder\]
