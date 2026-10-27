// appauth: работа с cookie автовхода. Подключается через aa_app_head().
//
// Токен автовхода хранится в cookie. HttpOnly для cookie, которую пишет JS, не
// ставится, поэтому токен в базе хранится только в виде sha256 и отзывается при
// выходе, блокировке, удалении и смене пароля.
(function () {
  function secureFlag() {
    return window.location.protocol === 'https:' ? '; Secure' : '';
  }

  // Enter в поле формы входа нажимает кнопку формы
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Enter' || e.isComposing) return;
    var field = e.target;
    if (!field || field.tagName !== 'INPUT') return;
    var card = field.closest('.aa-login-card');
    if (!card) return;
    var button = card.querySelector('.aa-login-button');
    if (button) {
      // значение поля доходит до Shiny по событию change, поэтому сначала снимаем фокус
      field.blur();
      button.click();
      e.preventDefault();
    }
  });

  // Кнопки копирования: .aa-copy, текст в атрибуте data-copy. По HTTPS работает буфер
  // браузера, иначе (и в окнах Bootstrap с ловушкой фокуса) копируем через скрытое поле
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

    // {url}: переход на страницу согласия Google (другие адреса игнорируются)
    Shiny.addCustomMessageHandler('appauth_redirect', function (msg) {
      if (typeof msg.url === 'string' && msg.url.indexOf('https://accounts.google.com/') === 0) {
        window.location.assign(msg.url);
      }
    });

    // {name}
    Shiny.addCustomMessageHandler('appauth_clear_cookie', function (msg) {
      document.cookie = encodeURIComponent(msg.name) + '=; path=/; max-age=0; SameSite=Lax' + secureFlag();
    });

    // {name, input}: значение cookie (или null) уходит в input модуля
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

  // Скрипт из <head> может загрузиться раньше shiny.js, поэтому ждём появления
  // Shiny. Подключение к серверу происходит позже, обработчики успевают.
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
