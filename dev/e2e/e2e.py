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

    # --- sign-in ------------------------------------------------------
    page.goto(BASE)
    page.wait_for_selector("#auth-login_btn", timeout=30000)
    check("login form is shown with the app title", "E2E App" in page.inner_text(".aa-login-title"))
    shot(page, "01_login_dark")
    bg = page.evaluate("getComputedStyle(document.querySelector('.aa-login')).backgroundImage")
    check("dark login form background applied", "gradient" in bg, bg)

    login(page, "lockme", "wrong")
    check("wrong password: message", msg(page) == "Incorrect login or password", msg(page))
    shot(page, "02_login_error")

    login(page, "lockme", "wrong")
    login(page, "lockme", "wrong")
    m = msg(page)
    check("after 3 failures: lockout", "Too many failed sign-in attempts" in m, m)
    login(page, "lockme", "secret123")
    m = msg(page)
    check("correct password during lockout does not sign in", "Too many" in m and page.locator("#whoami").count() == 0, m)
    shot(page, "03_login_locked")
    mcol = page.evaluate("getComputedStyle(document.querySelector('.aa-login-message')).color")
    check("error message is red", mcol.startswith("rgb(239, 68, 68"), mcol)

    # --- light theme -------------------------------------------------
    page.evaluate("document.body.classList.add('aa-theme-light')")
    page.wait_for_timeout(300)
    bg_light = page.evaluate("getComputedStyle(document.querySelector('.aa-login-card')).backgroundColor")
    title_color = page.evaluate("getComputedStyle(document.querySelector('.aa-login-title')).color")
    check("light theme: card is light, title is dark", "255, 255, 255" in bg_light and "15, 23, 42" in title_color, (bg_light, title_color))
    shot(page, "04_login_light")
    page.evaluate("document.body.classList.remove('aa-theme-light')")

    # --- administrator sign-in ---------------------------------------
    login(page, "alsey", "secret123")
    page.wait_for_selector("#whoami", timeout=15000)
    check("administrator signs in", page.inner_text("#whoami") == "alsey / admin")
    check("login form disappeared", page.locator("#auth-login_btn").count() == 0)

    cookies = ctx.cookies()
    tok = [c for c in cookies if c["name"] == "appauth_token"]
    check("auto-login cookie issued with SameSite=Lax, without HttpOnly (JS)", len(tok) == 1 and tok[0]["sameSite"] == "Lax" and not tok[0]["httpOnly"], tok)

    page.wait_for_selector("#users-table tbody tr", timeout=15000)
    page.wait_for_timeout(800)
    rows = page.locator("#users-table tbody tr")
    check("users table: 9 rows", rows.count() == 9, rows.count())
    lrow = page.locator("#users-table tbody tr", has_text="lockme")
    lcls = lrow.get_attribute("class") or ""
    lbg = lrow.locator("td").first.evaluate("e => getComputedStyle(e).backgroundColor")
    check("row locked by attempts: class aa-row-locked and orange background", "aa-row-locked" in lcls and lbg.startswith("rgba(245, 158, 11"), (lcls, lbg))
    heads = [h.strip() for h in page.locator("#users-table thead th").all_inner_texts()]
    check("state column hidden, date columns shown", heads == ["Login", "Role", "Status", "Created", "Last sign-in"], heads)
    alsey_row = page.locator("#users-table tbody tr", has_text="alsey").inner_text()
    ivan_row = page.locator("#users-table tbody tr", has_text="ivan").inner_text()
    check("signed-in administrator has a last sign-in date", re.search(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}.*\d{4}-\d{2}-\d{2} \d{2}:\d{2}", alsey_row.replace("\n", " ").replace("\t", " ")), alsey_row)
    check("user who never signed in shows 'never signed in', creation date is present", "never signed in" in ivan_row and re.search(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}", ivan_row), ivan_row)
    shot(page, "05_users_table")

    # --- card and blocking of ivan ----------------------------------------
    page.locator("#users-table tbody tr", has_text="ivan").dblclick()
    page.wait_for_selector("#users-block", timeout=10000)
    check("card opened with a title", "ivan" in page.inner_text(".modal-title"))
    shot(page, "06_card")
    page.click("#users-block")
    page.wait_for_selector("#users-unblock", timeout=10000)
    check("after blocking the card has the Unblock button", True)
    page.keyboard.press("Escape")
    page.wait_for_timeout(800)
    row = page.locator("#users-table tbody tr", has_text="ivan")
    cls = row.get_attribute("class") or ""
    bgc = row.locator("td").first.evaluate("e => getComputedStyle(e).backgroundColor")
    check("blocked user's row highlighted with class aa-row-blocked", "aa-row-blocked" in cls, cls)
    check("highlight is red (cell background)", bgc.startswith("rgba(239, 68, 68") or bgc.startswith("rgb(239, 68, 68"), bgc)
    shot(page, "07_blocked_row")

    # --- lockout by attempts: locked row -----------------------------------
    # (olga is locked by failed attempts from another context below)

    # --- auto-login and sign-out -----------------------------------------
    page.reload()
    page.wait_for_selector("#whoami", timeout=20000)
    check("auto-login by cookie after reload", page.inner_text("#whoami") == "alsey / admin")

    page.click("#logout")
    page.wait_for_selector("#auth-login_btn", timeout=20000)
    check("after sign-out the login form is shown again", True)
    tok = [c for c in ctx.cookies() if c["name"] == "appauth_token"]
    check("cookie removed on sign-out", len(tok) == 0, tok)
    page.reload()
    page.wait_for_selector("#auth-login_btn", timeout=20000)
    page.wait_for_timeout(1000)
    check("after sign-out reload does not sign in automatically", page.locator("#whoami").count() == 0)

    # --- blocked by an administrator ---------------------------------------
    login(page, "ivan", "wrong")
    check("blocked user with wrong password: generic message", msg(page) == "Incorrect login or password")
    login(page, "ivan", "secret123")
    m = msg(page)
    check("blocked user with correct password: block message", "blocked by an administrator" in m, m)
    shot(page, "08_blocked_user_login")

    # --- regular user does not see the tab ------------------------------
    login(page, "olga", "secret123")
    page.wait_for_selector("#whoami", timeout=15000)
    page.wait_for_timeout(800)
    check("viewer signed in", page.inner_text("#whoami") == "olga / viewer")
    check("viewer does not see the users table", page.locator("#users-table").count() == 0)
    shot(page, "09_viewer")

    # --- adding a user as admin (new session) -------------------------------
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
    check("adding: password mismatch is shown", "Passwords do not match" in pg2.inner_text("#users-add_message"))
    pg2.fill("#users-new_user_confirm", "secret123")
    pg2.click("#users-add_confirm")
    pg2.wait_for_timeout(1500)
    check("added user appeared in the table", pg2.locator("#users-table tbody tr", has_text="newbie").count() == 1)
    shot(pg2, "11_after_add")

    # --- weak password on adding (warn mode): accepted, but with a warning ----
    pg2.click("#users-add")
    pg2.wait_for_selector("#users-new_login", timeout=10000)
    pg2.fill("#users-new_login", "weakling")
    pg2.fill("#users-new_user_password", "123456")
    pg2.fill("#users-new_user_confirm", "123456")
    pg2.click("#users-add_confirm")
    pg2.wait_for_timeout(1500)
    notes = " ".join(pg2.locator(".shiny-notification").all_inner_texts())
    check("weak password accepted and a warning shown", pg2.locator("#users-table tbody tr", has_text="weakling").count() == 1 and "weak" in notes, notes)
    shot(pg2, "11b_weak_password_warning")

    # --- deletion requires confirmation ---------------------------------------------
    pg2.locator("#users-table tbody tr", has_text="weakling").dblclick()
    pg2.wait_for_selector("#users-delete", timeout=10000)
    pg2.click("#users-delete")
    pg2.wait_for_selector("#users-delete_confirm", timeout=10000)
    check("deletion: confirmation dialog with the user name", "weakling" in pg2.inner_text(".modal-body") and pg2.locator("#users-delete_cancel").count() == 1)
    shot(pg2, "11c_delete_confirm")
    pg2.click("#users-delete_cancel")
    pg2.wait_for_selector("#users-delete", timeout=10000)
    check("cancelling deletion returns to the card, user stays", pg2.locator("#users-table tbody tr", has_text="weakling").count() == 1)
    pg2.click("#users-delete")
    pg2.wait_for_selector("#users-delete_confirm", timeout=10000)
    pg2.click("#users-delete_confirm")
    pg2.wait_for_timeout(1500)
    check("after confirmation the user is deleted", pg2.locator("#users-table tbody tr", has_text="weakling").count() == 0)

    # --- forced sign-out: admin blocks a user with an open session ----
    ctx3 = browser.new_context(viewport={"width": 1280, "height": 900})
    pg3 = ctx3.new_page()
    pg3.goto(BASE)
    pg3.wait_for_selector("#auth-login_btn", timeout=30000)
    login(pg3, "temp2", "secret123")
    pg3.wait_for_selector("#whoami", timeout=15000)
    check("temp2 signed in", pg3.inner_text("#whoami") == "temp2 / user")

    pg2.locator("#users-table tbody tr", has_text="temp2").dblclick()
    pg2.wait_for_selector("#users-block", timeout=10000)
    pg2.click("#users-block")
    pg2.wait_for_selector("#users-unblock", timeout=10000)
    pg3.wait_for_selector("#auth-login_btn", timeout=20000)
    check("blocked user with an open session was thrown to the login form (session guard)", pg3.locator("#whoami").count() == 0)
    tok3 = [c for c in ctx3.cookies() if c["name"] == "appauth_token"]
    check("blocked user's cookie cleared", len(tok3) == 0, tok3)

    # a role change takes effect for a signed-in user without re-login
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
    check("after a role change the session ended and re-login is required", pg4.locator("#whoami").count() == 0)
    login(pg4, "temp3", "secret123")
    pg4.wait_for_selector("#whoami", timeout=15000)
    check("after re-login the role is the new one", pg4.inner_text("#whoami") == "temp3 / viewer")

    # --- Enter in the login form ---------------------------------------------
    ctx5 = browser.new_context(viewport={"width": 1280, "height": 900})
    pg5 = ctx5.new_page()
    pg5.goto(BASE)
    pg5.wait_for_selector("#auth-login_btn", timeout=30000)
    pg5.fill("#auth-login", "temp4")
    pg5.fill("#auth-password", "secret123")
    pg5.press("#auth-password", "Enter")
    pg5.wait_for_selector("#whoami", timeout=15000)
    check("sign-in with Enter", pg5.inner_text("#whoami") == "temp4 / user")

    # --- changing own password ----------------------------------------------
    pg5.fill("#pw-old", "wrong-old")
    pg5.fill("#pw-new", "brand-new-1")
    pg5.fill("#pw-confirm", "brand-new-1")
    pg5.click("#pw-change")
    pg5.wait_for_timeout(900)
    check("password change: incorrect current password is shown", "The current password is incorrect" in pg5.inner_text("#pw-message"), pg5.inner_text("#pw-message"))
    pg5.fill("#pw-old", "secret123")
    pg5.click("#pw-change")
    pg5.wait_for_timeout(1500)
    check("after the password change the user stays in the app", pg5.locator("#whoami").count() == 1)
    pg5.reload()
    pg5.wait_for_selector("#whoami", timeout=20000)
    check("after changing own password auto-login of the current session works", pg5.inner_text("#whoami") == "temp4 / user")
    shot(pg5, "12_password_form")

    # --- admin ends all sessions ----------------------------------------
    pg2.keyboard.press("Escape")
    pg2.wait_for_timeout(1000)
    pg2.locator("#users-table tbody tr", has_text="temp4").dblclick()
    pg2.wait_for_selector("#users-revoke", timeout=10000)
    shot(pg2, "13_card_revoke")
    pg2.click("#users-revoke")
    pg5.wait_for_selector("#auth-login_btn", timeout=20000)
    check("'end all sessions' threw the user to the login form", pg5.locator("#whoami").count() == 0)
    pg5.fill("#auth-login", "temp4")
    pg5.fill("#auth-password", "secret123")
    pg5.press("#auth-password", "Enter")
    pg5.wait_for_timeout(900)
    check("old password no longer works after the change", "Incorrect login or password" in pg5.inner_text("#auth-message"))
    pg5.fill("#auth-password", "brand-new-1")
    pg5.press("#auth-password", "Enter")
    pg5.wait_for_selector("#whoami", timeout=15000)
    check("new password works", pg5.inner_text("#whoami") == "temp4 / user")

    # --- mandatory password change -----------------------------------------
    ctx6 = browser.new_context(viewport={"width": 1280, "height": 900})
    pg6 = ctx6.new_page()
    pg6.goto(BASE)
    pg6.wait_for_selector("#auth-login_btn", timeout=30000)
    pg6.fill("#auth-login", "temp5")
    pg6.fill("#auth-password", "secret123")
    pg6.press("#auth-password", "Enter")
    pg6.wait_for_selector("#auth-change_btn", timeout=15000)
    check("password set by an administrator: change form shown, no app", pg6.locator("#whoami").count() == 0)
    shot(pg6, "14_must_change")
    pg6.fill("#auth-change_password", "personal-pass-1")
    pg6.fill("#auth-change_confirm", "personal-pass-1")
    pg6.press("#auth-change_confirm", "Enter")
    pg6.wait_for_selector("#whoami", timeout=15000)
    check("after the password change sign-in is completed", pg6.inner_text("#whoami") == "temp5 / user")

    check("no JS errors on the page", len(errors) == 0, errors)
    browser.close()

failed = [n for n, ok in results if not ok]
print("\nTOTAL: %d checks, %d failed" % (len(results), len(failed)))
sys.exit(1 if failed else 0)
