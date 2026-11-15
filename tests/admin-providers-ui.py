"""Administrator Providers regression: all records and writes are browser-local fixtures."""
from playwright.sync_api import sync_playwright
from urllib.parse import urlparse
import json,os,shutil
base=os.environ.get('LOCAL_MATE_TEST_URL','http://localhost:3200')
state={'pending':{},'hold_services':True,'hold_providers':True,'providers':[{'user_id':'provider-one','name':'Actual Provider','business_name':'Actual Provider Business','phone':'+919876543210','category':'Home care','description':'Test-only provider record','experience':4,'locations':'["Pattambi"]','service_ids':'["plumbing"]','status':'pending','offerings':[],'online':False}],'posts':[]}
service={'id':'plumbing','name':'Service-only result','category':'Home care','description':'Test-only service','price':500,'type':'fixed','active':True}
website={'content':{},'maintenance_mode':False,'customer_portal_enabled':True,'provider_portal_enabled':True,'registration_enabled':True,'bookings_enabled':True}
def fulfill(route,data,status=200):route.fulfill(status=status,content_type='application/json',body=json.dumps(data))
def handle(route):
 req=route.request;path=urlparse(req.url).path;payload=req.post_data_json if req.method=='POST' else {}
 if path=='/api/website':data=website
 elif path=='/api/catalog':data={'services':[service],'locations':['Pattambi'],'configured':True}
 elif path=='/api/providers':data=[]
 elif path=='/api/me':data={'id':'admin-one','name':'Administrator','username':'admin','admin':True,'provider':None,'is_active':True,'must_change_password':False}
 elif path=='/api/admin/overview':data={'customers':2,'providers':1,'pending':1,'bookings':0,'paid':0,'commission':10}
 elif path=='/api/admin/services':
  if state['hold_services']:state['pending'].setdefault('services',[]).append(route);return
  data=[service]
 elif path=='/api/admin/providers':
  if state['hold_providers']:state['pending'].setdefault('providers',[]).append(route);return
  data=state['providers']
 elif path=='/api/admin/provider':
  assert payload['user_id']=='provider-one';state['posts'].append(payload)
  state['providers'][0]['status']=payload['status'];data={'ok':True}
 elif path=='/api/admin/users':data=[{'id':'customer-one','name':'Customer-only result','username':'customer','is_active':True}]
 elif path=='/api/admin/logs':data=[]
 else:raise AssertionError('Unexpected API '+path)
 fulfill(route,data)
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path=os.environ.get('CHROMIUM_PATH') or shutil.which('chromium'),headless=True,args=['--no-sandbox'])
 page=browser.new_page(viewport={'width':1440,'height':1000});errors=[]
 page.on('pageerror',lambda e:errors.append(str(e)))
 page.on('console',lambda m:errors.append(m.text) if m.type=='error' and not m.text.startswith('Failed to load resource') else None)
 page.route('**/api/**',handle)
 page.goto(base+'/admin',wait_until='networkidle')
 def click_tab(name):page.locator('.portal-layout > aside').get_by_role('button',name=name,exact=True).click()
 # Services starts first, but its slow response arrives after Providers.
 click_tab('Services');page.wait_for_timeout(100)
 click_tab('Providers');page.wait_for_timeout(100)
 fulfill(state['pending']['providers'].pop(0),state['providers'])
 page.get_by_text('Actual Provider Business',exact=True).wait_for()
 fulfill(state['pending']['services'].pop(0),[service]);page.wait_for_timeout(150)
 assert page.locator('.admin-provider').get_by_text('Actual Provider Business',exact=True).count()==1,'A late Services response replaced the Providers list'
 assert page.locator('.admin-provider').get_by_text('Service-only result',exact=True).count()==0
 # A late Providers response must not appear on another screen either.
 click_tab('Users');page.get_by_text('Customer-only result',exact=True).wait_for()
 click_tab('Providers');page.wait_for_timeout(100)
 click_tab('Services');page.wait_for_timeout(100)
 fulfill(state['pending']['services'].pop(0),[service])
 page.get_by_text('Service-only result',exact=True).wait_for()
 fulfill(state['pending']['providers'].pop(0),state['providers']);page.wait_for_timeout(150)
 assert page.get_by_text('Service-only result',exact=True).count()==1
 assert page.get_by_text('Actual Provider Business',exact=True).count()==0
 # Missing and legacy area metadata is safe when the provider list renders.
 state['hold_providers']=False;state['hold_services']=False
 for locations in [None,'null',{},['Pattambi'],'["Pattambi"]']:
  state['providers'][0]['locations']=locations
  click_tab('Users');page.get_by_text('Customer-only result',exact=True).wait_for()
  click_tab('Providers');page.get_by_text('Actual Provider Business',exact=True).wait_for()
  assert page.get_by_role('heading',name='Let’s give that another try.').count()==0
 # The administrator still approves the correct provider after switching tabs.
 page.get_by_role('button',name='Approve',exact=True).click()
 page.get_by_role('button',name='Confirm',exact=True).click()
 page.get_by_role('status').filter(has_text='Provider approved.').wait_for()
 assert state['posts']==[{'user_id':'provider-one','status':'approved'}]
 # A failed list load is recoverable in place and leaves admin navigation available.
 state['hold_providers']=True;click_tab('Users');click_tab('Providers');page.wait_for_timeout(100)
 fulfill(state['pending']['providers'].pop(0),{'error':'Temporary provider directory problem.'},503)
 page.get_by_role('alert').filter(has_text='Temporary provider directory problem.').wait_for()
 state['hold_providers']=False
 page.get_by_role('button',name='Retry provider list',exact=True).click()
 page.get_by_text('Actual Provider Business',exact=True).wait_for()
 # Invalid or unexpected rows show an inline retry rather than crashing the route.
 valid_providers=state['providers']
 state['providers']=[{'id':'customer-one','name':'Wrong resource type'}]
 click_tab('Users');click_tab('Providers')
 page.get_by_role('alert').filter(has_text='The provider list could not be read').wait_for()
 assert page.get_by_role('heading',name='Local Mate administration',exact=True).count()==1
 state['providers']=valid_providers
 page.get_by_role('button',name='Retry provider list',exact=True).click()
 page.get_by_text('Actual Provider Business',exact=True).wait_for()
 state['providers']=[{**valid_providers[0],'business_name':{},'description':{},'experience':{}}]
 click_tab('Users');click_tab('Providers');page.get_by_text('Actual Provider',exact=True).wait_for()
 assert page.get_by_role('heading',name='Let’s give that another try.').count()==0
 state['providers']=valid_providers
 page.set_viewport_size({'width':390,'height':844})
 for name in ['Users','Providers','Services','Providers']:
  click_tab(name)
  if name=='Providers':page.get_by_text('Actual Provider Business',exact=True).wait_for()
 assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
 assert not errors,errors
 print(json.dumps({'late_services_response':'passed','late_providers_response':'passed','legacy_locations':'passed','correct_provider_approval':'passed','inline_error_retry':'passed','invalid_directory_recovery':'passed','desktop_mobile':'passed','javascript_errors':errors,'hosted_writes':0}))
 browser.close()
