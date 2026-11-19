# Recipe: auto-login cookie, HTTPS and nginx

## Auto-login cookie

The login module stores the auto-login token in a cookie (`aa_auth_server(cookie_name = "appauth_token")`). The `aa_app_head()` script writes the cookie with `SameSite=Lax`, and on HTTPS also with `Secure` (the browser will not send it over HTTP). `Secure` is set automatically when the page is opened over `https://`.

Limitation: the cookie is written by JavaScript, so it has no `HttpOnly`. XSS in the app can steal the token. Mitigations: the database holds only the sha256 of the token, the token is revoked on logout, lock, password change and "log out on all devices", and the app must never output unvalidated HTML (recipes/handler-guards.md).

Cookie name:

* every app on the same host has its own (`cookie_name`); cookies are not isolated by port, and apps with the same name overwrite each other's tokens;
* when migrating from a home-grown authentication, set the previous name (for example `auth_token`), so tokens issued earlier keep working and users stay logged in (the format is compatible: the sha256 of the token as text).

Auto-login can be turned off: `aa_settings(autologin = FALSE)`; then no tokens are issued, and "log out on all devices" only closes the current session.

## HTTPS

Passwords and tokens travel between the browser and the server: without HTTPS anyone who can see the traffic can intercept them.

* Publish the app only over `https://`. TLS is terminated at nginx, while Shiny itself listens on `127.0.0.1`.
* The Shiny port is closed from outside on the firewall, so nginx cannot be bypassed and the app cannot be opened over HTTP.
* Do not use `host = "0.0.0.0"` on a machine whose port is reachable from the network if there is no HTTPS proxy in front of the app.

## nginx template (for whoever configures the proxy)

Substitute your own paths, addresses and certificates. The key point: Shiny uses websockets, so they must be passed through.

```
server {
    listen 443 ssl;
    server_name apps.example.com;
    ssl_certificate     /etc/ssl/apps.crt;
    ssl_certificate_key /etc/ssl/apps.key;

    location /myapp/ {
        proxy_pass         http://127.0.0.1:3838/;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host $host;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 3600s;
    }
}
server {
    listen 80;
    server_name apps.example.com;
    return 301 https://$host$request_uri;
}
```

## Brute-force protection behind a proxy

Locking is counted per login, not per IP: behind nginx Shiny sees the proxy's address. An attacker cannot bypass the lock by changing address, but can deliberately lock someone else's login for `lockout_minutes`. The administrator removes such a lock in the user card; a spare administrator is always needed. The global limit `max_failed_logins_per_minute` stops mass guessing. Additionally limit the request rate in nginx (`limit_req`) if the app is reachable from the internet.

## Verification

* Open the app over `https://`; in DevTools (Application, Cookies) the auto-login cookie has `SameSite = Lax` and `Secure`.
* The Shiny port is unreachable from outside.
* Auto-login works after a page reload; after logout the cookie is deleted.
