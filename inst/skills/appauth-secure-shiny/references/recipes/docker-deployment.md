# Recipe: Docker and Linux

The `appauth` package is cross-platform: it does not call Windows commands and works on Linux. This recipe is a TEMPLATE for apps deployed in Docker. Substitute your own image and package versions and be sure to test the build on your own infrastructure: the template is not covered by automated tests.

## What is needed

* The system library `libsodium` (for the R package `sodium`) and headers for building packages (`libsodium-dev`, `libssl-dev`, `libsqlite3-dev`).
* For MySQL / MariaDB or PostgreSQL instead of SQLite (`appauth` 0.8.0+) add a driver: the R package `RMariaDB` (system `libmariadb-dev` at build time, `libmariadb3` in the runtime image) or `RPostgres` (`libpq-dev` at build time, `libpq5` in the runtime image); pass the database password via an environment variable. See `recipes/other-databases.md`.
* R packages: `appauth` (installed from the source your project uses; if it is a private repository, a token is needed at build time, `GITLAB_PAT` in the example below), `shiny`, `DBI`, `RSQLite`, `DT`, `openssl`, `sodium` and the remaining dependencies are installed through `renv`.
* The SQLite database file and `config.yaml` on mounted volumes, NOT inside the image: otherwise users and settings disappear when the container is recreated.
* Secrets (the repository token at build time, passwords, keys) must not end up in the image or in git history.

## Dockerfile skeleton (multi-stage build, token only at the build stage)

```dockerfile
FROM rocker/r-ver:4.4 AS build
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsodium-dev libssl-dev libsqlite3-dev libcurl4-openssl-dev libxml2-dev git \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY renv.lock renv.lock
COPY renv/activate.R renv/activate.R
COPY .Rprofile .Rprofile
# the token is passed as a build secret and does not end up in image layers
RUN --mount=type=secret,id=gitlab_pat \
    GITLAB_PAT="$(cat /run/secrets/gitlab_pat)" R -e 'renv::restore(prompt = FALSE)'

FROM rocker/r-ver:4.4
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsodium23 libssl3 libsqlite3-0 libcurl4 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/renv /app/renv
COPY --from=build /app/.Rprofile /app/.Rprofile
COPY . /app
RUN useradd -m app && mkdir -p /data && chown -R app:app /data
USER app
EXPOSE 3838
VOLUME ["/data"]
ENV APP_DB=/data/app.db
CMD ["R", "-e", "shiny::runApp('/app', host = '0.0.0.0', port = 3838)"]
```

Build: `docker build --secret id=gitlab_pat,env=GITLAB_PAT -t myapp .`. The names of system library packages depend on the image's distribution (pick your own for another database). If `appauth` is installed from a public source, the secret is not needed.

## renv and appauth

`appauth` must be in `renv.lock` (SKILL.md of the `appauth` skill, the section on renv: how to add the entry without truncating the lock file). If the `appauth` entry in the lock file uses a private remote (for example `RemoteType: gitlab`), `renv::restore()` downloads the package using the token (`GITLAB_PAT`).

## Volumes and the database

```yaml
# compose.yml
services:
  app:
    build: .
    ports: ["127.0.0.1:3838:3838"]      # exposed externally only through an HTTPS proxy
    volumes:
      - app-data:/data                   # app.db
      - ./config.yaml:/app/config.yaml   # the owner's settings outside the image
    environment:
      APP_DB: /data/app.db
volumes:
  app-data:
```

In the app, take the database path from an environment variable: `Sys.getenv("APP_DB", "app.db")`.

## The first administrator in the container

Create it before the app is opened to outsiders (recipes/first-admin.md):

```
docker compose run --rm app Rscript -e 'library(appauth); con <- DBI::dbConnect(RSQLite::SQLite(), Sys.getenv("APP_DB")); aa_init_db(con); aa_create_first_admin(con, "admin", Sys.getenv("APP_ADMIN_PASSWORD"))'
```

The password is passed through an environment variable when running the command, not baked into the image.

## HTTPS and proxy

The container listens only on the host's `127.0.0.1`, TLS is terminated at the proxy (recipes/cookie-and-https.md). The auto-login cookie gets `Secure` automatically when the page is opened over `https://`.

## Backups

Copy the volume with `app.db` while the app is stopped, or with SQLite tools (`VACUUM INTO`). Make a copy of the volume before updating the image.

## Verification

* The container is recreated, users and settings are preserved (volume).
* The image contains no token: `docker history` and the layer contents are free of `GITLAB_PAT`.
* The app works over HTTPS through the proxy, the container port is unreachable from outside.
