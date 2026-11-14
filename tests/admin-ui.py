"""Local-only UI checks with mocked APIs: never creates accounts or deletes hosted data."""
from playwright.sync_api import sync_playwright
from urllib.parse import urlparse
import json,os,pathlib,shutil
base=os.environ.get('LOCAL_MATE_TEST_URL','http://localhost:3100')
artifacts=pathlib.Path(os.environ.get('LOCAL_MATE_TEST_ARTIFACTS','/tmp/local-mate-admin-qa'));artifacts.mkdir(parents=True,exist_ok=True)
state={'signed_in':False,'must_change':True,'login_calls':0,'reset_calls':0,'website_payload':None}
website={'id':True,'content':{'site_name':'Local Mate','hero_line_1':'Your home.','hero_line_2':'Our people.','hero_line_3':'Consider it done.'},'maintenance_mode':False,'customer_portal_enabled':True,'provider_portal_enabled':True,'registration_enabled':True,'bookings_enabled':True,'updated_at':'2026-11-14T12:00:00Z'}
def handle(route):
 request=route.request;path=urlparse(request.url).path;method=request.method
 payload=request.post_data_json if method=='POST' else {}
 status=200;data={}
 if path=='/api/website':data=website
 elif path=='/api/catalog':data={'services':[],'locations':['Pattambi'],'configured':True}
 elif path=='/api/providers':data=[]
 elif path=='/api/me':
  if not state['signed_in']:status=401;data={'error':'Please sign in.'}
  else:data={'id':'test-admin','name':'Administrator','username':'admin','email':'admin@localmate.invalid','phone':'','is_active':True,'admin':not state['must_change'],'must_change_password':state['must_change'],'provider':None}
 elif path=='/api/auth/signin':
  assert payload=={'username':'admin','password':'admin123'}
  state['signed_in']=True;state['login_calls']+=1;data={'ok':True,'admin':False,'must_change_password':True}
 elif path=='/api/auth/account':
  assert payload['current_password']=='admin123';assert len(payload['new_password'])>=12
  state['must_change']=False;data={'ok':True}
 elif path=='/api/admin/overview':data={'customers':1,'providers':0,'pending':0,'bookings':0,'paid':0,'commission':10}
 elif path=='/api/admin/website':
  if method=='POST':state['website_payload']=payload;website.update(payload);website['updated_at']='2026-11-14T13:00:00Z';data={'ok':True}
  else:data=website
 elif path=='/api/admin/backup':data={'format':'local-mate-application-backup','version':1,'tables':{'users':[],'bookings':[]}}
 elif path=='/api/admin/reset':
  assert payload['confirmation']=='DELETE ALL DATA';assert payload['current_password']=='new-private-password-123'
  state['reset_calls']+=1;data={'ok':True,'message':'All marketplace records and other accounts were removed. Your administrator login is preserved.'}
 elif path.startswith('/api/admin/') or path in ['/api/bookings','/api/addresses','/api/payments']:data=[]
 else:raise AssertionError('Unexpected API request: '+path)
 route.fulfill(status=status,content_type='application/json',body=json.dumps(data))
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path=os.environ.get('CHROMIUM_PATH') or shutil.which('chromium'),headless=True,args=['--no-sandbox'])
 page=browser.new_page(viewport={'width':1440,'height':1000},accept_downloads=True)
 errors=[];page.on('pageerror',lambda e:errors.append(str(e)));page.route('**/api/**',handle)
 page.goto(base+'/admin',wait_until='networkidle')
 page.get_by_role('button',name='Sign in to continue').click()
 assert page.get_by_label('Your email',exact=True).count()==0
 page.get_by_label('Username',exact=True).fill('admin');page.get_by_label('Password',exact=True).fill('admin123')
 page.get_by_role('button',name='Sign in',exact=True).click()
 page.get_by_role('heading',name='Choose your private sign-in details').wait_for()
 assert page.get_by_role('button',name='Website & portals',exact=True).count()==0
 page.get_by_label('Current password',exact=True).fill('admin123')
 page.locator('input[name="new_password"]').fill('new-private-password-123')
 page.get_by_label('Confirm new password',exact=True).fill('new-private-password-123')
 page.get_by_role('button',name='Update sign-in details').click()
 page.get_by_role('heading',name='Local Mate administration').wait_for()
 page.get_by_role('button',name='Website & portals',exact=True).click()
 page.get_by_label('Website name',exact=True).fill('Neighbourhood Helpers')
 page.get_by_label('Accept new service bookings',exact=True).uncheck()
 page.get_by_role('button',name='Save changes',exact=True).click()
 page.wait_for_timeout(300)
 assert state['website_payload']['content']['site_name']=='Neighbourhood Helpers'
 assert state['website_payload']['bookings_enabled'] is False
 page.get_by_role('button',name='Backup',exact=True).click()
 with page.expect_download() as download_info:page.get_by_role('button',name='Download backup',exact=True).click()
 download=download_info.value;download.save_as(artifacts/'backup.json')
 assert json.loads((artifacts/'backup.json').read_text())['format']=='local-mate-application-backup'
 page.get_by_role('button',name='Delete all data',exact=True).click()
 page.get_by_label('Your current password',exact=True).fill('new-private-password-123')
 page.get_by_label('Type DELETE ALL DATA to confirm',exact=True).fill('WRONG')
 page.get_by_role('button',name='Delete all data and other accounts',exact=True).click()
 page.get_by_role('alert').filter(has_text='Type DELETE ALL DATA exactly').wait_for()
 assert state['reset_calls']==0
 page.get_by_label('Type DELETE ALL DATA to confirm',exact=True).fill('DELETE ALL DATA')
 page.get_by_role('button',name='Delete all data and other accounts',exact=True).click()
 page.get_by_text('All marketplace records and other accounts were removed.',exact=False).first.wait_for()
 assert state['reset_calls']==1
 page.get_by_role('button',name='Website & portals',exact=True).click()
 page.screenshot(path=str(artifacts/'admin-desktop.png'),full_page=True)
 page.set_viewport_size({'width':390,'height':844})
 page.screenshot(path=str(artifacts/'admin-mobile.png'),full_page=True)
 assert page.evaluate('document.documentElement.scrollWidth <= innerWidth'),page.evaluate('Array.from(document.querySelectorAll("body *")).filter(e=>e.getBoundingClientRect().right>innerWidth+1).map(e=>({tag:e.tagName,cls:e.className,right:e.getBoundingClientRect().right})).slice(0,12)')
 assert not errors,errors
 assert state['login_calls']==1
 print(json.dumps({'username_login':'passed','mandatory_password_change':'passed','website_controls':'passed','backup_download':'passed','typed_reset_confirmation':'passed','desktop_mobile':'passed','live_operations':0,'javascript_errors':errors}))
 browser.close()
