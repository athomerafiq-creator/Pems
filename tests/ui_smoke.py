"""Browser smoke test: runs the real index.html against the in-memory mock
Supabase client and clicks through every page as each type of user.
Usage: python3 tests/ui_smoke.py   (needs playwright + Chrome)"""
import os, sys
from playwright.sync_api import sync_playwright
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOCK = open(os.path.join(ROOT, 'tests/mock_supabase.js')).read()
PAGES = ['dashboard','calendar','tasks','contacts','documents','portfolio','finance','payroll','meetings','chat','attendance','warnings','travel','reports','admin']
errs = []
with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/usr/bin/google-chrome')
    for who in ['p', 'a1', 'a2', 'noauth']:
        ctx = b.new_context(viewport={'width': 1400, 'height': 950}, accept_downloads=True)
        pre = f"window.MOCK_USER='{who if who!='noauth' else 'p'}';window.MOCK_NOAUTH={'true' if who=='noauth' else 'false'};"
        ctx.route('**/config.js', lambda r: r.fulfill(body="window.PEMS_CONFIG={url:'https://mock.supabase.co',anonKey:'x'};", content_type='text/javascript'))
        ctx.route('**/supabase.min.js', lambda r: r.fulfill(body=MOCK, content_type='text/javascript'))
        ctx.route('**/fonts.googleapis.com/**', lambda r: r.fulfill(body='', content_type='text/css'))
        ctx.add_init_script(pre)
        pg = ctx.new_page()
        pg.on('pageerror', lambda e, w=who: errs.append(f'{w}: {e}'))
        pg.goto('file://' + ROOT + '/index.html'); pg.wait_for_timeout(600)
        if who == 'noauth':
            assert pg.is_visible('#aEmail'), 'login screen not shown'
            pg.fill('#aEmail', 'a@b.c'); pg.fill('#aPass', 'x'); pg.click('#aBtn'); pg.wait_for_timeout(500)
            assert not pg.is_visible('#auth .box') or not pg.eval_on_selector('#auth', 'e=>e.classList.contains("on")'), 'login did not proceed'
            ctx.close(); continue
        for r in PAGES:
            pg.evaluate(f"location.hash='{r}'"); pg.wait_for_timeout(120)
            pg.screenshot(path=f'/tmp/ui_{who}_{r}.png')
        # flows
        pg.evaluate("location.hash='tasks'"); pg.wait_for_timeout(100)
        if who != 'a2' or True:
            pg.evaluate("openForm('tasks')"); pg.fill('#fm input[name=title]', 'New task ' + who); pg.evaluate("saveForm()"); pg.wait_for_timeout(200)
        pg.evaluate("location.hash='contacts'"); pg.wait_for_timeout(100)
        if who != 'a2': pg.evaluate("openForm('contacts',null,null,true)"); pg.fill('#fm input[name=name]', 'C ' + who) if who!='a2' else None; pg.evaluate("saveForm()") if who!='a2' else None
        if who != 'a1':
          pg.evaluate("location.hash='finance'"); pg.wait_for_timeout(100)
          pg.evaluate("openForm('tx')"); pg.fill('#fm input[name=cat]', 'Taxi'); pg.fill('#fm input[name=amount]', '500'); pg.evaluate("saveForm()"); pg.wait_for_timeout(200)
        pg.evaluate("location.hash='chat'"); pg.wait_for_timeout(150); pg.fill('#msg', 'hi from ' + who); pg.press('#msg', 'Enter'); pg.wait_for_timeout(200)
        pg.evaluate('closeM()'); pg.click('#ck'); pg.wait_for_timeout(200)
        if who == 'p':
            pg.evaluate("approveTx(S.tx.find(t=>t.status==='Pending').id,true)"); pg.wait_for_timeout(150)
            pg.evaluate("approveTask(S.tasks.find(t=>t.status==='Review').id,true)"); pg.wait_for_timeout(150)
            pg.evaluate("location.hash='admin'"); pg.wait_for_timeout(150)
            pg.fill('#newWS', 'Ishc Holdings'); pg.press('#newWS', 'Enter'); pg.wait_for_timeout(200)
            pg.evaluate("setPerm('pa1','finance','entry')"); pg.wait_for_timeout(150)
            pg.evaluate("setActive('pa2',false)"); pg.wait_for_timeout(150)
            pg.evaluate("archive('contacts',S.contacts[0].id)"); pg.wait_for_timeout(150)
            pg.evaluate("restore(0)"); pg.wait_for_timeout(150)
            pg.evaluate("location.hash='warnings'"); pg.evaluate("openForm('warnings')"); pg.fill('#fm input[name=reason]', 'x'); pg.evaluate("saveForm()"); pg.wait_for_timeout(200)
            pg.evaluate("location.hash='payroll'"); pg.wait_for_timeout(100)
            with pg.expect_download() as d: pg.evaluate("payrollPDF(TODAY.slice(0,7))")
            d.value.save_as('/tmp/ui_payroll.pdf')
            with pg.expect_download() as d: pg.evaluate("reportXLSX(weekStart(TODAY),TODAY)")
            d.value.save_as('/tmp/ui_report.xlsx')
            print('outbox:', pg.evaluate("__MOCKDB.email_outbox.map(m=>m.subject)"))
            print('audit:', pg.evaluate("__MOCKDB.audit_log.length"))
        if who == 'a2':
            pg.evaluate("location.hash='warnings'"); pg.wait_for_timeout(100); pg.evaluate("ackWarning(S.warnings[0].id)"); pg.wait_for_timeout(150)
            print('a2 tx statuses:', pg.evaluate("__MOCKDB.transactions.map(t=>t.status)"))
        for r in PAGES:
            pg.evaluate(f"location.hash='{r}'"); pg.wait_for_timeout(80)
        m = b.new_page(viewport={'width': 390, 'height': 844})
        ctx.close()
    b.close()
print('\n'.join(errs) if errs else 'NO JS ERRORS')
sys.exit(1 if errs else 0)
