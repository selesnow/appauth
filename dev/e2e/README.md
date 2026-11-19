# Checking the modules in a real browser

A one-off check before a package release (the `aa_auth_*` and `aa_users_*` modules, styles, cookies).

* `prepare_db.R` - a temporary database `%TEMP%\aa_e2e\e2e.db` with test users;
* `app.R` - a small application with the login and users modules;
* `e2e.py` - Playwright scenarios (Chrome, Python), screenshots in `%TEMP%\aa_e2e\shots`;
* `run_e2e.ps1` - runs everything together: stops the previous app, prepares the database, starts the app on port 8765 and runs the scenarios.

Copy the folder to `%TEMP%\aa_e2e` (the app into the `app` subfolder), set the `AA_PKG` environment variable to the package source folder and run `run_e2e.ps1`.
After the check, stop the app process and delete the folder.
