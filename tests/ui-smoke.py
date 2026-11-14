from playwright.sync_api import sync_playwright
import json,os,pathlib,shutil
base=os.environ.get("LOCAL_MATE_TEST_URL","http://localhost:3000")
artifacts=pathlib.Path(os.environ.get("LOCAL_MATE_TEST_ARTIFACTS","/tmp/local-mate-qa"));artifacts.mkdir(parents=True,exist_ok=True)
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path=os.environ.get('CHROMIUM_PATH') or shutil.which('chromium'),headless=True,args=['--no-sandbox'])
 page=browser.new_page(viewport={'width':1440,'height':1100},device_scale_factor=1)
 status=page.request.get(base+'/api/status').json()
 assert status.get('database') is False, 'Run this configuration-error smoke test with Supabase environment variables unset.'
 errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 page.goto(base,wait_until='networkidle')
 page.get_by_role('heading',name='Your home. Our people. Consider it done.').wait_for()
 assert page.locator('.service-card').count()==6
 page.screenshot(path=str(artifacts/'desktop.png'),full_page=True)
 page.get_by_role('button',name='Explore all services').click()
 assert page.locator('.listing-grid .service-card').count()==18
 page.get_by_placeholder('Search services…').fill('Plumbing')
 assert page.locator('.listing-grid .service-card').count()==1
 page.locator('.service-card').click()
 page.get_by_role('button',name='Plan your service').click()
 page.get_by_role('textbox',name='Your email').fill('ui-test@example.invalid')
 page.get_by_role('button',name='Email me a sign-in link').click()
 page.get_by_role('alert').filter(has_text='Supabase is not connected yet').wait_for()
 page.get_by_role('button',name='Close dialog').click()
 page.get_by_role('button',name='Local Mate home').click()
 page.get_by_role('button',name='Notifications').count()
 mobile=browser.new_page(viewport={'width':390,'height':844},device_scale_factor=1)
 mobile.on('pageerror',lambda e:errors.append(str(e)))
 mobile.goto(base,wait_until='networkidle')
 assert mobile.evaluate('document.documentElement.scrollWidth <= innerWidth')
 mobile.get_by_role('button',name='Toggle navigation').click()
 mobile.locator('nav').get_by_role('button',name='Services',exact=True).click()
 assert mobile.locator('.listing-grid .service-card').count()==18
 mobile.locator('.service-card').first.click()
 assert mobile.get_by_role('dialog').is_visible()
 mobile.keyboard.press('Escape')
 assert mobile.get_by_role('dialog').count()==0
 mobile.get_by_role('button',name='Local Mate home').click()
 mobile.screenshot(path=str(artifacts/'mobile.png'),full_page=True)
 assert not errors, errors
 print(json.dumps({'desktop':'passed','mobile':'passed','search':'passed','booking_signin':'passed','unconfigured_supabase_error':'passed','dialog_keyboard':'passed','javascript_errors':errors}))
 browser.close()
