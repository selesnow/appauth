import os, sys, re
from playwright.sync_api import sync_playwright

BASE = "http://127.0.0.1:8765"
SHOTS = os.path.join(os.environ["TEMP"], "aa_e2e", "shots")
os.makedirs(SHOTS, exist_ok=True)
results = []


def check(name, cond, extra=""):
    results.append((name, bool(cond)))
    print(("OK   " if cond else "FAIL ") + name + (("  [" + str(extra) + "]") if extra and not cond else ""), flush=True)


def shot(page, name):
    page.screenshot(path=os.path.join(SHOTS, name + ".png"), full_page=True)


def login(page, user, password):
    page.fill("#auth-login", user)
    page.fill("#auth-password", password)
    page.click("#auth-login_btn")


def msg(page):
    page.wait_for_timeout(700)
    return page.inner_text("#auth-message").strip()


with sync_playwright() as p:
    browser = p.chromium.launch(executable_path=r"C:\Program Files\Google\Chrome\Application\chrome.exe", headless=True)
    ctx = browser.new_context(viewport={"width": 1280, "height": 900})
    page = ctx.new_page()
    errors = []
    page.on("pageerror", lambda e: errors.append(str(e)))

    # --- вход ---------------------------------------------------------
    page.goto(BASE)
    page.wait_for_selector("#auth-login_btn", timeout=30000)
    check("форма входа показана с заголовком приложения", "E2E App" in page.inner_text(".aa-login-title"))
    shot(page, "01_login_dark")
    bg = page.evaluate("getComputedStyle(document.querySelector('.aa-login')).backgroundImage")
    check("тёмный фон формы входа применён", "gradient" in bg, bg)

    login(page, "lockme", "wrong")
    check("неверный пароль: сообщение", msg(page) == "Неверный логин или пароль", msg(page))
    shot(page, "02_login_error")

    login(page, "lockme", "wrong")
    login(page, "lockme", "wrong")
    m = msg(page)
    check("после 3 неудач: блокировка", "Слишком много неудачных попыток" in m, m)
    login(page, "lockme", "secret123")
    m = msg(page)
    check("верный пароль при блокировке не пускает", "Слишком много" in m and page.locator("#whoami").count() == 0, m)
    shot(page, "03_login_locked")
    mcol = page.evaluate("getComputedStyle(document.querySelector('.aa-login-message')).color")
    check("сообщение об ошибке красное", mcol.startswith("rgb(239, 68, 68"), mcol)

    # --- светлая тема -----------------------------------------------
    page.evaluate("document.body.classList.add('aa-theme-light')")
    page.wait_for_timeout(300)
    bg_light = page.evaluate("getComputedStyle(document.querySelector('.aa-login-card')).backgroundColor")
    title_color = page.evaluate("getComputedStyle(document.querySelector('.aa-login-title')).color")
    check("светлая тема: карточка светлая, заголовок тёмный", "255, 255, 255" in bg_light and "15, 23, 42" in title_color, (bg_light, title_color))
    shot(page, "04_login_light")
    page.evaluate("document.body.classList.remove('aa-theme-light')")

    # --- вход администратора -----------------------------------------
    login(page, "alsey", "secret123")
    page.wait_for_selector("#whoami", timeout=15000)
    check("вход администратора", page.inner_text("#whoami") == "alsey / admin")
    check("форма входа исчезла", page.locator("#auth-login_btn").count() == 0)

    cookies = ctx.cookies()
    tok = [c for c in cookies if c["name"] == "appauth_token"]
    check("cookie автовхода выдана с SameSite=Lax, без HttpOnly (JS)", len(tok) == 1 and tok[0]["sameSite"] == "Lax" and not tok[0]["httpOnly"], tok)

    page.wait_for_selector("#users-table tbody tr", timeout=15000)
    page.wait_for_timeout(800)
    rows = page.locator("#users-table tbody tr")
    check("таблица пользователей: 9 строк", rows.count() == 9, rows.count())
    lrow = page.locator("#users-table tbody tr", has_text="lockme")
    lcls = lrow.get_attribute("class") or ""
    lbg = lrow.locator("td").first.evaluate("e => getComputedStyle(e).backgroundColor")
    check("строка с блокировкой по попыткам: класс aa-row-locked и оранжевый фон", "aa-row-locked" in lcls and lbg.startswith("rgba(245, 158, 11"), (lcls, lbg))
    heads = [h.strip() for h in page.locator("#users-table thead th").all_inner_texts()]
    check("колонка state скрыта, колонки дат показаны", heads == ["Логин", "Роль", "Статус", "Создан", "Последний вход"], heads)
    alsey_row = page.locator("#users-table tbody tr", has_text="alsey").inner_text()
    ivan_row = page.locator("#users-table tbody tr", has_text="ivan").inner_text()
    check("у вошедшего администратора указана дата последнего входа", re.search(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}.*\d{4}-\d{2}-\d{2} \d{2}:\d{2}", alsey_row.replace("\n", " ").replace("\t", " ")), alsey_row)
    check("у не входившего пользователя «не входил», дата создания есть", "не входил" in ivan_row and re.search(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}", ivan_row), ivan_row)
    shot(page, "05_users_table")

    # --- карточка и блокировка ivan -------------------------------------
    page.locator("#users-table tbody tr", has_text="ivan").dblclick()
    page.wait_for_selector("#users-block", timeout=10000)
    check("карточка открыта с заголовком", "ivan" in page.inner_text(".modal-title"))
    shot(page, "06_card")
    page.click("#users-block")
    page.wait_for_selector("#users-unblock", timeout=10000)
    check("после блокировки в карточке кнопка Разблокировать", True)
    page.keyboard.press("Escape")
    page.wait_for_timeout(800)
    row = page.locator("#users-table tbody tr", has_text="ivan")
    cls = row.get_attribute("class") or ""
    bgc = row.locator("td").first.evaluate("e => getComputedStyle(e).backgroundColor")
    check("строка заблокированного подсвечена классом aa-row-blocked", "aa-row-blocked" in cls, cls)
    check("подсветка красная (фон ячейки)", bgc.startswith("rgba(239, 68, 68") or bgc.startswith("rgb(239, 68, 68"), bgc)
    shot(page, "07_blocked_row")

    # --- блокировка по попыткам: строка locked -----------------------------
    # (olga заблокирована неудачными попытками из другого контекста ниже)

    # --- автовход и выход ------------------------------------------------
    page.reload()
    page.wait_for_selector("#whoami", timeout=20000)
    check("автовход по cookie после перезагрузки", page.inner_text("#whoami") == "alsey / admin")

    page.click("#logout")
    page.wait_for_selector("#auth-login_btn", timeout=20000)
    check("после выхода снова форма входа", True)
    tok = [c for c in ctx.cookies() if c["name"] == "appauth_token"]
    check("cookie удалена при выходе", len(tok) == 0, tok)
    page.reload()
    page.wait_for_selector("#auth-login_btn", timeout=20000)
    page.wait_for_timeout(1000)
    check("после выхода перезагрузка не входит автоматически", page.locator("#whoami").count() == 0)

    # --- заблокированный администратором ----------------------------------
    login(page, "ivan", "wrong")
    check("заблокированному с неверным паролем: обычное сообщение", msg(page) == "Неверный логин или пароль")
    login(page, "ivan", "secret123")
    m = msg(page)
    check("заблокированному с верным паролем: сообщение о блокировке", "заблокирована администратором" in m, m)
    shot(page, "08_blocked_user_login")

    # --- обычный пользователь не видит вкладку --------------------------
    login(page, "olga", "secret123")
    page.wait_for_selector("#whoami", timeout=15000)
    page.wait_for_timeout(800)
    check("viewer вошёл", page.inner_text("#whoami") == "olga / viewer")
    check("viewer не видит таблицу пользователей", page.locator("#users-table").count() == 0)
    shot(page, "09_viewer")

    # --- добавление пользователя админом (новая сессия) ---------------------
    ctx2 = browser.new_context(viewport={"width": 1280, "height": 900})
    pg2 = ctx2.new_page()
    pg2.goto(BASE)
    pg2.wait_for_selector("#auth-login_btn", timeout=30000)
    login(pg2, "boss", "secret123")
    pg2.wait_for_selector("#users-add", timeout=20000)
    pg2.click("#users-add")
    pg2.wait_for_selector("#users-new_login", timeout=10000)
    shot(pg2, "10_add_modal")
    pg2.fill("#users-new_login", "newbie")
    pg2.fill("#users-new_user_password", "secret123")
    pg2.fill("#users-new_user_confirm", "different")
    pg2.click("#users-add_confirm")
    pg2.wait_for_timeout(800)
    check("добавление: несовпадение паролей показано", "Пароли не совпадают" in pg2.inner_text("#users-add_message"))
    pg2.fill("#users-new_user_confirm", "secret123")
    pg2.click("#users-add_confirm")
    pg2.wait_for_timeout(1500)
    check("добавленный пользователь появился в таблице", pg2.locator("#users-table tbody tr", has_text="newbie").count() == 1)
    shot(pg2, "11_after_add")

    # --- слабый пароль при добавлении (режим warn): принят, но с предупреждением ----
    pg2.click("#users-add")
    pg2.wait_for_selector("#users-new_login", timeout=10000)
    pg2.fill("#users-new_login", "weakling")
    pg2.fill("#users-new_user_password", "123456")
    pg2.fill("#users-new_user_confirm", "123456")
    pg2.click("#users-add_confirm")
    pg2.wait_for_timeout(1500)
    notes = " ".join(pg2.locator(".shiny-notification").all_inner_texts())
    check("слабый пароль принят и показано предупреждение", pg2.locator("#users-table tbody tr", has_text="weakling").count() == 1 and "слабый" in notes, notes)
    shot(pg2, "11b_weak_password_warning")

    # --- удаление требует подтверждения ---------------------------------------------
    pg2.locator("#users-table tbody tr", has_text="weakling").dblclick()
    pg2.wait_for_selector("#users-delete", timeout=10000)
    pg2.click("#users-delete")
    pg2.wait_for_selector("#users-delete_confirm", timeout=10000)
    check("удаление: окно подтверждения с названием пользователя", "weakling" in pg2.inner_text(".modal-body") and pg2.locator("#users-delete_cancel").count() == 1)
    shot(pg2, "11c_delete_confirm")
    pg2.click("#users-delete_cancel")
    pg2.wait_for_selector("#users-delete", timeout=10000)
    check("отмена удаления возвращает карточку, пользователь остаётся", pg2.locator("#users-table tbody tr", has_text="weakling").count() == 1)
    pg2.click("#users-delete")
    pg2.wait_for_selector("#users-delete_confirm", timeout=10000)
    pg2.click("#users-delete_confirm")
    pg2.wait_for_timeout(1500)
    check("после подтверждения пользователь удалён", pg2.locator("#users-table tbody tr", has_text="weakling").count() == 0)

    # --- принудительный выход: админ блокирует пользователя с открытой сессией ----
    ctx3 = browser.new_context(viewport={"width": 1280, "height": 900})
    pg3 = ctx3.new_page()
    pg3.goto(BASE)
    pg3.wait_for_selector("#auth-login_btn", timeout=30000)
    login(pg3, "temp2", "secret123")
    pg3.wait_for_selector("#whoami", timeout=15000)
    check("temp2 вошёл", pg3.inner_text("#whoami") == "temp2 / user")

    pg2.locator("#users-table tbody tr", has_text="temp2").dblclick()
    pg2.wait_for_selector("#users-block", timeout=10000)
    pg2.click("#users-block")
    pg2.wait_for_selector("#users-unblock", timeout=10000)
    pg3.wait_for_selector("#auth-login_btn", timeout=20000)
    check("заблокированного с открытой сессией выбросило на форму входа (сторож сессии)", pg3.locator("#whoami").count() == 0)
    tok3 = [c for c in ctx3.cookies() if c["name"] == "appauth_token"]
    check("cookie заблокированного очищена", len(tok3) == 0, tok3)

    # смена роли у вошедшего вступает в силу без его перелогина
    ctx4 = browser.new_context(viewport={"width": 1280, "height": 900})
    pg4 = ctx4.new_page()
    pg4.goto(BASE)
    pg4.wait_for_selector("#auth-login_btn", timeout=30000)
    login(pg4, "temp3", "secret123")
    pg4.wait_for_selector("#whoami", timeout=15000)
    pg2.keyboard.press("Escape")
    pg2.wait_for_timeout(1000)
    pg2.locator("#users-table tbody tr", has_text="temp3").dblclick()
    pg2.wait_for_selector("#users-change_role", timeout=10000)
    pg2.evaluate("document.querySelector('#users-role').selectize.setValue('viewer')")
    pg2.click("#users-change_role")
    pg2.wait_for_timeout(1500)
    pg4.wait_for_selector("#auth-login_btn", timeout=20000)
    check("после смены роли сессия завершена и нужен повторный вход", pg4.locator("#whoami").count() == 0)
    login(pg4, "temp3", "secret123")
    pg4.wait_for_selector("#whoami", timeout=15000)
    check("после повторного входа роль новая", pg4.inner_text("#whoami") == "temp3 / viewer")

    # --- Enter в форме входа -------------------------------------------------
    ctx5 = browser.new_context(viewport={"width": 1280, "height": 900})
    pg5 = ctx5.new_page()
    pg5.goto(BASE)
    pg5.wait_for_selector("#auth-login_btn", timeout=30000)
    pg5.fill("#auth-login", "temp4")
    pg5.fill("#auth-password", "secret123")
    pg5.press("#auth-password", "Enter")
    pg5.wait_for_selector("#whoami", timeout=15000)
    check("вход по Enter", pg5.inner_text("#whoami") == "temp4 / user")

    # --- смена своего пароля ----------------------------------------------
    pg5.fill("#pw-old", "wrong-old")
    pg5.fill("#pw-new", "brand-new-1")
    pg5.fill("#pw-confirm", "brand-new-1")
    pg5.click("#pw-change")
    pg5.wait_for_timeout(900)
    check("смена пароля: неверный текущий показан", "Неверный текущий пароль" in pg5.inner_text("#pw-message"), pg5.inner_text("#pw-message"))
    pg5.fill("#pw-old", "secret123")
    pg5.click("#pw-change")
    pg5.wait_for_timeout(1500)
    check("после смены пароля пользователь остаётся в приложении", pg5.locator("#whoami").count() == 1)
    pg5.reload()
    pg5.wait_for_selector("#whoami", timeout=20000)
    check("после смены своего пароля автовход текущей сессии работает", pg5.inner_text("#whoami") == "temp4 / user")
    shot(pg5, "12_password_form")

    # --- завершение всех сессий админом ----------------------------------
    pg2.keyboard.press("Escape")
    pg2.wait_for_timeout(1000)
    pg2.locator("#users-table tbody tr", has_text="temp4").dblclick()
    pg2.wait_for_selector("#users-revoke", timeout=10000)
    shot(pg2, "13_card_revoke")
    pg2.click("#users-revoke")
    pg5.wait_for_selector("#auth-login_btn", timeout=20000)
    check("«завершить все сессии» выбросило пользователя на форму входа", pg5.locator("#whoami").count() == 0)
    pg5.fill("#auth-login", "temp4")
    pg5.fill("#auth-password", "secret123")
    pg5.press("#auth-password", "Enter")
    pg5.wait_for_timeout(900)
    check("старый пароль после смены не подходит", "Неверный логин или пароль" in pg5.inner_text("#auth-message"))
    pg5.fill("#auth-password", "brand-new-1")
    pg5.press("#auth-password", "Enter")
    pg5.wait_for_selector("#whoami", timeout=15000)
    check("новый пароль подходит", pg5.inner_text("#whoami") == "temp4 / user")

    # --- обязательная смена пароля -----------------------------------------
    ctx6 = browser.new_context(viewport={"width": 1280, "height": 900})
    pg6 = ctx6.new_page()
    pg6.goto(BASE)
    pg6.wait_for_selector("#auth-login_btn", timeout=30000)
    pg6.fill("#auth-login", "temp5")
    pg6.fill("#auth-password", "secret123")
    pg6.press("#auth-password", "Enter")
    pg6.wait_for_selector("#auth-change_btn", timeout=15000)
    check("пароль от администратора: показана форма смены, приложения нет", pg6.locator("#whoami").count() == 0)
    shot(pg6, "14_must_change")
    pg6.fill("#auth-change_password", "personal-pass-1")
    pg6.fill("#auth-change_confirm", "personal-pass-1")
    pg6.press("#auth-change_confirm", "Enter")
    pg6.wait_for_selector("#whoami", timeout=15000)
    check("после смены пароля вход выполнен", pg6.inner_text("#whoami") == "temp5 / user")

    check("ошибок JS на странице нет", len(errors) == 0, errors)
    browser.close()

failed = [n for n, ok in results if not ok]
print("\nИТОГО: %d проверок, провалено %d" % (len(results), len(failed)))
sys.exit(1 if failed else 0)
