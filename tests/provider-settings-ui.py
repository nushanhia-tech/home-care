"""Local provider availability/profile regressions. Every API response is a fixture."""
from playwright.sync_api import sync_playwright
from urllib.parse import urlparse
import json, os, shutil

base=os.environ.get('LOCAL_MATE_TEST_URL','http://localhost:3200')
service={'id':'plumbing','name':'Plumbing','category':'Home care','type':'fixed','price':500,'description':'Test service','tone':'blue','icon':'🔧'}
state={'schedule':'{}','service_ids':'["plumbing"]','locations':'["Pattambi"]','offerings':[{'service_id':'plumbing','price':750,'pricing_unit':'visit'}],'availability_posts':0,'profile_posts':0,'fail_save':False}
website={'content':{},'maintenance_mode':False,'customer_portal_enabled':True,'provider_portal_enabled':True,'registration_enabled':True,'bookings_enabled':True}
def profile():
 return {'user_id':'test-provider','business_name':'Test provider','category':'Home care','description':'Test fixture provider','experience':5,'status':'approved','online':True,'schedule':state['schedule'],'service_ids':state['service_ids'],'locations':state['locations'],'offerings':state['offerings']}
def handle(route):
 req=route.request;path=urlparse(req.url).path;payload=req.post_data_json if req.method=='POST' else {};status=200;data={}
 if path=='/api/website':data=website
 elif path=='/api/catalog':data={'services':[service],'locations':['Pattambi'],'configured':True}
 elif path=='/api/providers':data=[]
 elif path=='/api/me':data={'id':'test-provider','name':'Test Provider','username':'provider_fixture','phone':'+919876543210','admin':False,'must_change_password':False,'is_active':True,'provider':profile()}
 elif path=='/api/bookings':data=[]
 elif path=='/api/notifications':data=[]
 elif path=='/api/provider/availability':
  if state.get('hold_save'):
   state['pending_route']=route;state['pending_payload']=payload;return
  if state['fail_save']:status=503;data={'error':'Temporary test connection problem. Try again.'}
  else:state['schedule']=payload['schedule'];state['availability_posts']+=1;data={'ok':True}
 elif path=='/api/provider/profile':
  state['offerings']=payload['offerings'];state['service_ids']=[o['service_id'] for o in payload['offerings']];state['locations']=payload['locations'];state['profile_posts']+=1;data={'ok':True}
 else:raise AssertionError('Unexpected API request: '+path)
 route.fulfill(status=status,content_type='application/json',body=json.dumps(data))

with sync_playwright() as p:
 browser=p.chromium.launch(executable_path=os.environ.get('CHROMIUM_PATH') or shutil.which('chromium'),headless=True,args=['--no-sandbox'])
 page=browser.new_page(viewport={'width':1440,'height':1000});errors=[]
 page.on('pageerror',lambda e:errors.append(str(e)))
 page.on('console',lambda m:errors.append(m.text) if m.type=='error' and not m.text.startswith('Failed to load resource') else None)
 page.route('**/api/**',handle)
 def tab(name):
  state['tab_switches']=state.get('tab_switches',0)+1
  page.get_by_role('button',name=name,exact=True).click()
  assert page.get_by_role('heading',name='Let’s give that another try.').count()==0
 # Missing and legacy settings caused the whole provider page to crash before this fix.
 cases=[
  ('{}','["plumbing"]','["Pattambi"]',[{'service_id':'plumbing','price':750,'pricing_unit':'visit'}]),
  ('null','null','null','null'),
  (None,None,None,None),
  ({'days':'Friday','hours':'10:00–14:00','max_daily':7,'leave':''},['plumbing'],['Pattambi'],[{'service_id':'plumbing','price':750,'pricing_unit':'visit'}]),
  ('{broken','{}','{}','{}'),
  ({'days':{},'hours':[],'max_daily':None,'leave':None},'[null,"plumbing"]','[null,"Pattambi"]',[None,{'service_id':'plumbing','price':750,'pricing_unit':'visit'}]),
  (json.dumps(json.dumps({'max_daily':8})),json.dumps(json.dumps(['plumbing'])),json.dumps(json.dumps(['Pattambi'])),json.dumps([{'service_id':'plumbing','price':750,'pricing_unit':'visit'}]))
 ]
 for schedule,services,areas,offers in cases:
  state.update(schedule=schedule,service_ids=services,locations=areas,offerings=offers)
  page.goto(base+'/provider',wait_until='networkidle')
  for i in range(3):
   tab('Availability');page.get_by_label('Working days',exact=True).wait_for()
   tab('Profile');page.get_by_role('button',name='Save services & profile',exact=True).wait_for()
 # Edits must survive the account refresh after a successful save.
 state.update(schedule={'max_daily':5},service_ids=['plumbing'],locations=['Pattambi'],offerings=[{'service_id':'plumbing','price':750,'pricing_unit':'visit'}])
 page.goto(base+'/provider',wait_until='networkidle')
 tab('Availability')
 page.get_by_label('Working days',exact=True).fill('Friday')
 page.get_by_label('Working hours',exact=True).fill('10:00–14:00')
 page.get_by_label('Maximum daily bookings',exact=True).fill('8')
 page.get_by_role('button',name='Save changes',exact=True).click()
 page.get_by_role('status').filter(has_text='Your availability has been updated.').wait_for()
 assert state['availability_posts']==1 and state['schedule']['max_daily']==8
 assert page.get_by_label('Maximum daily bookings',exact=True).input_value()=='8'
 tab('Profile');page.get_by_label('Plumbing rate (₹)',exact=True).fill('850')
 page.get_by_role('button',name='Save services & profile',exact=True).click()
 page.get_by_role('status').filter(has_text='Your provider profile and rates have been saved.').wait_for()
 page.wait_for_timeout(200)
 assert state['profile_posts']==1 and page.get_by_label('Plumbing rate (₹)',exact=True).input_value()=='850'
 tab('Availability');assert page.get_by_label('Working days',exact=True).input_value()=='Friday'
 # Failed saves remain inline, retain the draft, and can be retried.
 state['fail_save']=True
 page.get_by_label('Working days',exact=True).fill('Saturday')
 page.get_by_role('button',name='Save changes',exact=True).click()
 page.get_by_role('alert').filter(has_text='Temporary test connection problem').wait_for()
 assert page.get_by_label('Working days',exact=True).input_value()=='Saturday'
 state['fail_save']=False;page.get_by_role('button',name='Save changes',exact=True).click()
 page.get_by_role('status').filter(has_text='Your availability has been updated.').wait_for()
 assert state['schedule']['days']=='Saturday'
 # A slow successful request must not erase an edit made while it was saving.
 state['hold_save']=True
 page.get_by_label('Working days',exact=True).fill('Monday')
 page.get_by_role('button',name='Save changes',exact=True).click()
 page.get_by_label('Working days',exact=True).fill('Tuesday')
 state['schedule']=state['pending_payload']['schedule'];state['hold_save']=False
 state['pending_route'].fulfill(status=200,content_type='application/json',body='{"ok":true}')
 page.get_by_role('button',name='Save changes',exact=True).wait_for()
 page.wait_for_timeout(200)
 assert page.get_by_label('Working days',exact=True).input_value()=='Tuesday'
 page.get_by_role('button',name='Save changes',exact=True).click()
 page.get_by_role('status').filter(has_text='Your availability has been updated.').wait_for()
 assert state['schedule']['days']=='Tuesday'
 page.set_viewport_size({'width':390,'height':844})
 for name in ['Profile','Availability','Profile','Availability']:tab(name)
 assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
 assert not errors,errors
 print(json.dumps({'provider_json_cases':len(cases),'availability_profile_switches':state['tab_switches'],'saved_values_after_refresh':'passed','failed_save_retry':'passed','desktop_mobile':'passed','javascript_errors':errors,'hosted_writes':0}))
 browser.close()
