"""Проверка двух пример-приложений в браузере.

Приложения должны быть запущены (см. run_examples.ps1): minimal-app на 8771,
custom-permissions-app на 8772. Скриншоты в %TEMP%\\aa_examples\\shots.
"""
import os, sys
from playwright.sync_api import sync_playwright

SHOTS = os.path.join(os.environ["TEMP"], "aa_examples", "shots")
os.makedirs(SHOTS, exist_ok=True)
results = []


def check(name, cond, extra=""):
    results.append((name, bool(cond)))
    print(("OK   " if cond else "FAIL ") + name + (("  [" + str(extra) + "]") if extra and not cond else ""), flush=True)


def shot(page, name):
    page.screenshot(path=os.path.join(SHOTS, name + ".png"), full_page=True)


def create_admin(page, login, password):
    page.wait_for_selector("#auth-setup_btn", timeout=30000)
    page.fill("#auth-setup_login", login)
    page.fill("#auth-setup_password", password)
    page.fill("#auth-setup_confirm", password)
    page.press("#auth-setup_confirm", "Enter")


with sync_playwright() as p:
    browser = p.chromium.launch(executable_path=r"C:\Program Files\Google\Chrome\Application\chrome.exe", headless=True)
    errors = []

    # ---------------- minimal-app ----------------
    ctx = browser.new_context(viewport={"width": 1200, "height": 800})
    page = ctx.new_page()
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.goto("http://127.0.0.1:8771")
    check("minimal: предлагает создать администратора", page.wait_for_selector("#auth-setup_btn", timeout=30000) is not None)
    shot(page, "m1_setup")
    create_admin(page, "boss", "secret123")
    page.wait_for_selector(".nav-tabs", timeout=20000)
    tabs = [t.strip() for t in page.locator(".nav-tabs a").all_inner_texts()]
    check("minimal: вкладки админа Задачи, Доступ", tabs == ["Задачи", "Доступ"], tabs)
    check("minimal: кнопка запуска задачи есть", page.locator("#run").count() == 1)
    check("minimal: рядом с плашкой пользователя три кнопки", all(page.locator(sel).count() == 1 for sel in ("#change_password", "#logout_all", "#logout")))
    page.click(".nav-tabs a:has-text('Доступ')")
    page.wait_for_selector("#users-table tbody tr", timeout=15000)
    page.wait_for_timeout(600)
    check("minimal: в таблице пользователей 1 строка", page.locator("#users-table tbody tr").count() == 1)
    shot(page, "m2_users")

    # смена своего пароля в окне
    page.click("#change_password")
    page.wait_for_selector("#password-old", timeout=10000)
    shot(page, "m3_password_modal")
    page.fill("#password-old", "wrong")
    page.fill("#password-new", "brand-new-1")
    page.fill("#password-confirm", "brand-new-1")
    page.click("#password-change")
    page.wait_for_timeout(900)
    check("minimal: неверный текущий пароль показан в окне", "Неверный текущий пароль" in page.inner_text("#password-message"))
    page.fill("#password-old", "secret123")
    page.click("#password-change")
    page.wait_for_selector("#shiny-modal", state="detached", timeout=10000)
    check("minimal: после смены пароля окно закрылось, пользователь остался в приложении", page.locator("#logout").count() == 1)

    # выход на всех устройствах с подтверждением
    page.click("#logout_all")
    page.wait_for_selector("#logout_all_confirm", timeout=10000)
    check("minimal: перед выходом везде просит подтверждение", "будут завершены" in page.inner_text(".modal-body"))
    shot(page, "m4_confirm")
    page.click(".modal-footer button:has-text('Отмена')")
    page.wait_for_selector("#shiny-modal", state="detached", timeout=10000)
    check("minimal: отмена оставляет в приложении", page.locator("#logout").count() == 1)
    page.click("#logout_all")
    page.wait_for_selector("#logout_all_confirm", timeout=10000)
    page.click("#logout_all_confirm")
    page.wait_for_selector("#auth-login_btn", timeout=20000)
    check("minimal: после подтверждения выход, форма входа", True)
    check("minimal: cookie автовхода удалена", len([c for c in ctx.cookies() if c["name"] == "appauth_token"]) == 0)

    # ---------------- custom-permissions-app ----------------
    ctx2 = browser.new_context(viewport={"width": 1200, "height": 800})
    pg = ctx2.new_page()
    pg.on("pageerror", lambda e: errors.append(str(e)))
    pg.goto("http://127.0.0.1:8772")
    pg.wait_for_selector("#auth-setup_btn", timeout=30000)
    check("custom: английский интерфейс и название", "Create administrator" in pg.inner_text(".aa-login-title"))
    create_admin(pg, "boss", "secret123")
    pg.wait_for_selector(".nav-tabs", timeout=20000)
    tabs = [t.strip() for t in pg.locator(".nav-tabs a").all_inner_texts()]
    check("custom: вкладки владельца Reports, Export, Users, Profile", tabs == ["Reports", "Export", "Users", "Profile"], tabs)
    pg.click(".nav-tabs a:has-text('Users')")
    pg.wait_for_selector("#users-add", timeout=15000)
    pg.click("#users-add")
    pg.wait_for_selector("#users-new_login", timeout=10000)
    must = pg.locator("#users-new_user_must_change").is_checked()
    check("custom: галочка временного пароля выключена (must_change_default = FALSE)", must is False)
    shot(pg, "c1_add")
    pg.fill("#users-new_login", "ann")
    pg.fill("#users-new_user_password", "secret123")
    pg.fill("#users-new_user_confirm", "secret123")
    pg.evaluate("document.querySelector('#users-new_user_role').selectize.setValue('editor')")
    pg.click("#users-add_confirm")
    pg.wait_for_timeout(1500)
    check("custom: ann добавлена", pg.locator("#users-table tbody tr", has_text="ann").count() == 1)
    pg.locator("#users-table tbody tr", has_text="ann").dblclick()
    pg.wait_for_selector("#users-save_permissions", timeout=10000)
    check("custom: в карточке есть блок Permissions из слота", "Permissions" in pg.inner_text(".modal-body"))
    shot(pg, "c2_card_slot")
    pg.check("input[name='users-permissions'][value='export'], #users-permissions input[value='export']")
    pg.click("#users-save_permissions")
    pg.wait_for_timeout(1200)
    pg.keyboard.press("Escape")

    ctx3 = browser.new_context(viewport={"width": 1200, "height": 800})
    pg3 = ctx3.new_page()
    pg3.on("pageerror", lambda e: errors.append(str(e)))
    pg3.goto("http://127.0.0.1:8772")
    pg3.wait_for_selector("#auth-login_btn", timeout=30000)
    pg3.fill("#auth-login", "ann")
    pg3.fill("#auth-password", "secret123")
    pg3.press("#auth-password", "Enter")
    pg3.wait_for_selector(".nav-tabs", timeout=20000)
    tabs = [t.strip() for t in pg3.locator(".nav-tabs a").all_inner_texts()]
    check("custom: у ann вкладки по её правам (Export, Profile)", tabs == ["Export", "Profile"], tabs)
    shot(pg3, "c3_editor")

    check("ошибок JS на страницах нет", len(errors) == 0, errors)
    browser.close()

failed = [n for n, ok in results if not ok]
print("\nИТОГО: %d проверок, провалено %d" % (len(results), len(failed)))
sys.exit(1 if failed else 0)
