// appauth: работа с cookie автовхода. Подключается через aa_app_head().
//
// Токен автовхода хранится в cookie. HttpOnly для cookie, которую пишет JS, не
// ставится, поэтому токен в базе хранится только в виде sha256 и отзывается при
// выходе, блокировке, удалении и смене пароля.
(function () {
  function secureFlag() {
    return window.location.protocol === 'https:' ? '; Secure' : '';
  }

  function register() {
    // {name, token, days}
    Shiny.addCustomMessageHandler('appauth_set_cookie', function (msg) {
      document.cookie = encodeURIComponent(msg.name) + '=' + encodeURIComponent(msg.token) +
        '; path=/; max-age=' + Math.round(msg.days * 86400) +
        '; SameSite=Lax' + secureFlag();
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
