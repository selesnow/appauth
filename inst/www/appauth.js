// appauth: auto-login cookie handling. Included through aa_app_head().
//
// The auto-login token is stored in a cookie. HttpOnly cannot be set on a cookie
// written by JS, so the token is stored in the database only as a sha256 hash and
// is revoked on sign-out, blocking, deletion and password change.
(function () {
  function secureFlag() {
    return window.location.protocol === 'https:' ? '; Secure' : '';
  }

  // Enter in a login form field presses the form button
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Enter' || e.isComposing) return;
    var field = e.target;
    if (!field || field.tagName !== 'INPUT') return;
    var card = field.closest('.aa-login-card');
    if (!card) return;
    var button = card.querySelector('.aa-login-button');
    if (button) {
      // the field value reaches Shiny on the change event, so blur the field first
      field.blur();
      button.click();
      e.preventDefault();
    }
  });

  // Copy buttons: .aa-copy, the text is in the data-copy attribute. Over HTTPS the browser
  // clipboard is used; otherwise (and in Bootstrap modals with a focus trap) copy via a hidden field
  function copyText(text, host) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text);
    }
    return new Promise(function (resolve, reject) {
      var area = document.createElement('textarea');
      area.value = text;
      area.setAttribute('readonly', '');
      area.style.position = 'fixed';
      area.style.opacity = '0';
      (host || document.body).appendChild(area);
      area.select();
      var ok = false;
      try { ok = document.execCommand('copy'); } catch (err) { ok = false; }
      (host || document.body).removeChild(area);
      if (ok) { resolve(); } else { reject(new Error('copy failed')); }
    });
  }

  document.addEventListener('click', function (e) {
    var button = e.target && e.target.closest ? e.target.closest('.aa-copy') : null;
    if (!button) return;
    var text = button.getAttribute('data-copy');
    if (text === null) return;
    copyText(text, button.parentNode).then(function () {
      if (button.getAttribute('data-copied') === '1') return;
      var original = button.innerHTML;
      button.setAttribute('data-copied', '1');
      button.textContent = '\u2713 ' + (button.getAttribute('data-done') || '');
      setTimeout(function () {
        button.innerHTML = original;
        button.removeAttribute('data-copied');
      }, 1500);
    });
  });

  function register() {
    // {name, token, days}
    Shiny.addCustomMessageHandler('appauth_set_cookie', function (msg) {
      document.cookie = encodeURIComponent(msg.name) + '=' + encodeURIComponent(msg.token) +
        '; path=/; max-age=' + Math.round(msg.days * 86400) +
        '; SameSite=Lax' + secureFlag();
    });

    // {url, origin}: redirect to the Google consent page or to the site address origin
    // sent by the server (other addresses are ignored)
    Shiny.addCustomMessageHandler('appauth_redirect', function (msg) {
      if (typeof msg.url !== 'string') return;
      var toGoogle = msg.url.indexOf('https://accounts.google.com/') === 0;
      var toOrigin = typeof msg.origin === 'string' && msg.origin.length > 0 &&
        msg.url.indexOf(msg.origin + '/') === 0;
      if (toGoogle || toOrigin) {
        window.location.assign(msg.url);
      }
    });

    // {name}
    Shiny.addCustomMessageHandler('appauth_clear_cookie', function (msg) {
      document.cookie = encodeURIComponent(msg.name) + '=; path=/; max-age=0; SameSite=Lax' + secureFlag();
    });

    // {name, input}: the cookie value (or null) is sent to the module input
    Shiny.addCustomMessageHandler('appauth_read_cookie', function (msg) {
      var wanted = encodeURIComponent(msg.name) + '=';
      var value = null;
      document.cookie.split(';').forEach(function (part) {
        part = part.trim();
        if (part.indexOf(wanted) === 0) {
          value = decodeURIComponent(part.substring(wanted.length));
        }
      });
      Shiny.setInputValue(msg.input, value, { priority: 'event' });
    });
  }

  // A script in <head> can load before shiny.js, so wait for Shiny to appear.
  // The server connection happens later, so the handlers are registered in time.
  function tryRegister() {
    if (window.Shiny && Shiny.addCustomMessageHandler) {
      register();
      return true;
    }
    return false;
  }

  if (!tryRegister()) {
    var timer = setInterval(function () {
      if (tryRegister()) clearInterval(timer);
    }, 10);
  }
})();
