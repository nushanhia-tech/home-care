"""Local UI integration checks. All API records and GPS positions are test-only mocks."""
from playwright.sync_api import sync_playwright
from urllib.parse import urlparse
import json,os,pathlib,shutil
base=os.environ.get('LOCAL_MATE_TEST_URL','http://localhost:3200')
artifacts=pathlib.Path('/workspace/work/marketplace-qa');artifacts.mkdir(parents=True,exist_ok=True)
state={'role':'admin','providers':[],'saved_provider':None,'booking_payload':None,'gps':None,'session':None,'gps_stops':0,'address':None,'message':None}
service={'id':'plumbing','name':'Plumbing','category':'Home care','description':'Test fixture service','price':500,'type':'fixed','icon':'🔧','tone':'blue','active':True}
website={'content':{},'maintenance_mode':False,'customer_portal_enabled':True,'provider_portal_enabled':True,'registration_enabled':True,'bookings_enabled':True}
def provider():return {'user_id':'test-provider','name':'Test Provider','business_name':'Test Plumbing','username':'fixture_provider','phone':'+919876543210','publish_phone':True,'category':'Home care','description':'Local test provider fixture','experience':5,'locations':'["Pattambi"]','service_ids':'["plumbing"]','schedule':'{}','status':'approved','online':True,'rating':None,'review_count':0,'assessment_rating':4.3,'rating_source':'Test assessment source','offerings':[{'service_id':'plumbing','price':750,'pricing_unit':'visit'}]}
def booking():return {'id':'test-booking-0001','customer_id':'test-customer','provider_id':'test-provider','service_id':'plumbing','service_name':'Plumbing','service_type':'fixed','location':'Pattambi','address':'Test home, test street','latitude':10.805,'longitude':76.186,'destination_latitude':None,'destination_longitude':None,'description':'Test job fixture','details':{'contact':'Test details as JSON object'},'scheduled_at':'2026-12-15T10:00:00+05:30','estimated_price':750,'status':'confirmed','payment_status':'pending','payment_method':'cash','customer_name':'Test Customer','provider_name':'Test Provider','history':[],'quotes':[]}
def handle(route):
 req=route.request;path=urlparse(req.url).path;method=req.method;payload=req.post_data_json if method=='POST' else {};data={};status=200
 if path=='/api/website':data=website
 elif path=='/api/catalog':data={'services':[service],'locations':['Pattambi','Ottapalam'],'configured':True}
 elif path=='/api/providers':data=state['providers']
 elif path=='/api/me':
  role=state['role'];data={'id':'test-'+role,'name':'Test '+role.title(),'username':'fixture_'+role,'phone':'+919876543212','is_active':True,'admin':role=='admin','must_change_password':False,'provider':provider() if role=='provider' else None}
 elif path=='/api/admin/overview':data={'customers':2,'providers':len(state['providers']),'pending':0,'bookings':1,'paid':0,'commission':10}
 elif path=='/api/admin/providers':
  if method=='POST':
   state['saved_provider']=payload;assert payload['offerings']==[{'service_id':'plumbing','price':750,'pricing_unit':'visit'}];assert payload['locations']==['Pattambi'];assert payload['assessment_rating']=='4.3';state['providers']=[provider()];data={'ok':True}
  else:data=state['providers']
 elif path=='/api/admin/users':data=[]
 elif path=='/api/admin/services':data=[service]
 elif path=='/api/admin/locations':data=[{'name':'Pattambi','active':True},{'name':'Ottapalam','active':True}]
 elif path=='/api/provider/profile':state['profile']=payload;data={'ok':True}
 elif path=='/api/bookings':
  if method=='POST':state['booking_payload']=payload;data={'id':'test-booking-0001'}
  else:data=[booking()]
 elif path=='/api/addresses':
  if method=='POST':state['address']=payload;data={'id':'test-address'}
  else:data=[]
 elif path=='/api/payments':data=[]
 elif path=='/api/notifications':data=[{'id':1,'title':'New message for your job','is_read':False,'booking_id':'test-booking-0001','created_at':'2026-11-15T10:00:00Z'}]
 elif path=='/api/bookings/test-booking-0001':data=booking()
 elif path=='/api/bookings/test-booking-0001/contacts':data={'customer':{'name':'Test Customer','phone':'+919876543212'},'provider':{'name':'Test Provider','phone':'+919876543210'}}
 elif path=='/api/bookings/test-booking-0001/tracking':
  if method=='GET':data=state['gps']
  elif payload.get('start'):state['session']=payload['session_id'];data={'ok':True}
  elif payload.get('stop'):state['gps']=None;state['gps_stops']+=1;data={'ok':True}
  else:
   assert payload['session_id']==state['session'];assert payload['consent'];state['gps']={**payload,'recorded_at':'2026-11-15T10:30:00Z'};data={'ok':True}
 elif path=='/api/bookings/test-booking-0001/messages':
  if method=='POST':state['message']=payload;data={'ok':True}
  else:data=[{'id':1,'sender_id':'test-customer','sender_name':'Test Customer','body':'Test fixture message','created_at':'2026-11-15T10:00:00Z'}]
 elif path=='/api/support':data=[]
 else:raise AssertionError('Unexpected API '+method+' '+path)
 route.fulfill(status=status,content_type='application/json',body=json.dumps(data))
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path=os.environ.get('CHROMIUM_PATH') or shutil.which('chromium'),headless=True,args=['--no-sandbox'])
 context=browser.new_context(viewport={'width':1440,'height':1100},permissions=['geolocation'],geolocation={'latitude':10.805,'longitude':76.186,'accuracy':10})
 page=context.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 page.route('**/api/**',handle)
 page.route('https://*.tile.openstreetmap.org/**',lambda route:route.abort())
 page.goto(base+'/admin',wait_until='networkidle')
 page.get_by_role('button',name='Providers',exact=True).click()
 page.get_by_role('button',name='Add provider',exact=True).click()
 dialog=page.get_by_role('dialog')
 dialog.get_by_label('Username',exact=True).fill('fixture_provider')
 dialog.get_by_label('Temporary password (12+ characters)',exact=True).fill('test-only-password-123')
 dialog.get_by_label('Full name',exact=True).fill('Test Provider')
 dialog.get_by_label('Mobile number',exact=True).fill('+919876543210')
 dialog.get_by_label('Business name',exact=True).fill('Test Plumbing')
 dialog.get_by_label('Skills & description',exact=True).fill('Local test provider fixture')
 dialog.get_by_label('Plumbing',exact=True).check()
 dialog.get_by_label('Plumbing pricing',exact=True).select_option('visit')
 dialog.get_by_label('Plumbing rate (₹)',exact=True).fill('750')
 dialog.get_by_label('Pattambi',exact=True).check()
 dialog.get_by_label('Approval status',exact=True).select_option('approved')
 dialog.get_by_label('Assessment rating (optional, 0–5)',exact=True).fill('4.3')
 dialog.get_by_label('Rating source / assessment basis',exact=True).fill('Test assessment source')
 dialog.get_by_label('Online and accepting requests',exact=True).check()
 dialog.get_by_role('button',name='Save provider',exact=True).click()
 page.get_by_role('button',name='Edit profile & rates',exact=True).wait_for()
 assert state['saved_provider']
 page.get_by_role('button',name='Services',exact=True).filter(visible=True).last.click()
 page.get_by_role('button',name='Manage providers',exact=True).click()
 page.get_by_text('1 providers assigned to this service.',exact=False).wait_for()
 page.get_by_role('button',name='Close dialog',exact=True).click()
 page.get_by_role('button',name='Locations',exact=True).click()
 page.get_by_text('1 providers · manage coverage',exact=True).wait_for()
 page.screenshot(path=str(artifacts/'admin-coverage.png'),full_page=True)
 # Customer picks a professional and pins the exact service location.
 state['role']='customer';page.goto(base,wait_until='networkidle')
 page.locator('.service-card').first.click()
 page.get_by_text('1 service provider in Pattambi',exact=True).wait_for()
 assert page.get_by_text('Listed assessment: 4.3/5 · Test assessment source',exact=True).count()==1
 assert page.get_by_text('No completed-booking reviews yet',exact=True).count()==1
 page.get_by_role('button',name='Choose provider',exact=True).click()
 page.get_by_role('button',name='Plan your service',exact=True).click()
 page.locator('textarea[name="address"]').fill('Test home, test landmark, test PIN')
 page.get_by_role('button',name='Use my current location',exact=True).click()
 page.wait_for_function("document.querySelector('input[name=latitude]').value !== ''")
 page.locator('input[name="date"]').fill('2026-12-15');page.locator('textarea[name="description"]').fill('Test request fixture')
 page.screenshot(path=str(artifacts/'customer-booking.png'))
 page.get_by_role('button',name='Send booking request',exact=True).click()
 page.get_by_role('dialog').wait_for(state='hidden')
 assert state['booking_payload']['provider_id']=='test-provider'
 assert abs(float(state['booking_payload']['latitude'])-10.805)<0.00001
 page.goto(base+'/account',wait_until='networkidle')
 page.locator('.booking-row').first.click()
 page.get_by_role('heading',name='Service location & provider GPS',exact=True).wait_for()
 assert page.get_by_role('button',name='Share my live GPS for this job',exact=True).count()==0
 assert page.get_by_role('link',name='+919876543210',exact=True).count()==1
 assert page.get_by_text('Test details as JSON object',exact=False).count()==1
 page.screenshot(path=str(artifacts/'customer-tracking.png'))
 page.get_by_role('button',name='Close dialog',exact=True).click()
 page.get_by_role('button',name='Saved addresses',exact=True).click()
 page.get_by_role('button',name='Add address',exact=True).click()
 page.get_by_label('Address label',exact=True).fill('Test home')
 page.get_by_label('Full address, landmark & PIN code',exact=True).fill('Test address')
 page.get_by_role('button',name='Use my current location',exact=True).click()
 page.wait_for_function("document.querySelector('input[name=latitude]').value !== ''")
 page.get_by_role('button',name='Save changes',exact=True).click()
 page.get_by_role('dialog').wait_for(state='hidden');assert state['address']['latitude']
 # Provider gets messages, prices and optional GPS with an explicit stop.
 state['role']='provider';page.goto(base+'/provider',wait_until='networkidle')
 page.get_by_role('button',name='Messages',exact=True).click()
 page.get_by_role('button',name='Plumbing Test Customer',exact=False).first.click()
 page.get_by_label('Message',exact=True).fill('Test fixture reply')
 page.get_by_role('button',name='Send message',exact=True).click()
 page.wait_for_timeout(250);assert state['message']=={'body':'Test fixture reply'}
 page.get_by_role('button',name='Close dialog',exact=True).click()
 page.get_by_role('button',name='Jobs',exact=True).click();page.locator('.booking-row').first.click()
 page.get_by_role('button',name='Share my live GPS for this job',exact=True).click()
 page.wait_for_timeout(500)
 assert state['gps'] and state['gps']['latitude']==10.805
 page.get_by_role('button',name='Stop sharing GPS',exact=True).click()
 page.wait_for_timeout(300);assert state['gps'] is None and state['gps_stops']>=1
 page.screenshot(path=str(artifacts/'provider-gps.png'))
 page.set_viewport_size({'width':390,'height':844});page.screenshot(path=str(artifacts/'provider-mobile.png'))
 assert page.evaluate('document.documentElement.scrollWidth <= innerWidth'), 'Page overflows mobile viewport'
 page.get_by_role('button',name='Close dialog',exact=True).click()
 page.get_by_role('button',name='Profile',exact=True).click()
 page.get_by_label('Plumbing rate (₹)',exact=True).fill('850')
 page.get_by_role('button',name='Save services & profile',exact=True).click()
 page.wait_for_timeout(250);assert state['profile']['offerings'][0]['price']==850
 assert not errors,errors
 print(json.dumps({'admin_add_provider':'passed','service_counts':'passed','area_counts':'passed','provider_selection_rates':'passed','exact_places':'passed','customer_contact_tracking':'passed','provider_messages':'passed','provider_prices':'passed','gps_start_stop':'passed','mobile':'passed','javascript_errors':errors,'live_writes':0}))
 browser.close()
