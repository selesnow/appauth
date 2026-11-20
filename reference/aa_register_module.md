# Attach a module server only if the permission is granted

Calls `server()` once per session, when the signed-in user gets the
`permission` permission. For other users the module server is not
registered at all, and permissions still have to be checked inside
handlers
([`aa_require()`](https://alexey-seleznev.pro/appauth/reference/aa_require.md)):
registration protects against unnecessary work, not against forged
requests.

## Usage

``` r
aa_register_module(auth, permission, provider, server)
```

## Arguments

- auth:

  A result of
  [`aa_auth_server()`](https://alexey-seleznev.pro/appauth/reference/aa_auth_server.md).

- permission:

  Permission name.

- provider:

  Permission source, see
  [`aa_can()`](https://alexey-seleznev.pro/appauth/reference/aa_can.md).

- server:

  A function without arguments that registers the module, for example
  `function() mod_tasks_server("tasks")`.

## Value

Invisibly a Shiny observer.

## Details

Registered modules cannot be removed from a session, so on sign-out use
`auth$logout(reload = TRUE)`: the page reloads and the modules of the
previous user disappear.

## Examples

``` r
if (FALSE) { # \dontrun{
provider <- aa_permissions_from_matrix(conf$access_management)
aa_register_module(auth, "Tasks", provider, function()
mod_tasks_server("tasks"))
} # }
```
