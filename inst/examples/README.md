# Example applications

Two ready-made applications for getting to know the package. Open `app.R`: the comments at the top of the file explain what the example shows.

| Example | Model | What it shows |
| --- | --- | --- |
| `minimal-app` | A "permission -> roles" matrix from `config.yaml`, English interface, roles `admin`, `user`, `viewer` | The minimum an app needs: login, tabs by permission, handler protection, a users tab, password change, the events hook |
| `custom-permissions-app` | Per-user permissions from a database table, custom roles `owner`, `editor`, `viewer`, custom texts | The core is not tied to one permission scheme: a custom permission source, a slot in the user card, custom texts and cookie name, a permanent password set by the administrator, two-factor authentication (the Profile tab), password recovery by email (the example writes the link to the console; the app address is set by `APPAUTH_EXAMPLE_URL`) |

## Running

```r
shiny::runApp(system.file("examples/minimal-app", package = "appauth"))
shiny::runApp(system.file("examples/custom-permissions-app", package = "appauth"))
```

The default database is temporary (in `tempdir()`), so every run offers to create the first administrator. A permanent database is set with the `APPAUTH_EXAMPLE_DB` environment variable.

To use an example as a starting point, copy the folder, edit `config.yaml` (or the settings at the top of `app.R`) and replace the tab contents with your own modules.

## Verification

Both applications are run end to end in the package tests (`tests/testthat/test-example-apps.R`), and the package sources contain a real-browser check (`dev/e2e/run_examples.ps1`).
