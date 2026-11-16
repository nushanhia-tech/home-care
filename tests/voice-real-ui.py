"""Real WebRTC media over the actual Next API, local PostgREST/PostgreSQL and Coturn."""
from playwright.sync_api import sync_playwright
import urllib.request,json,base64,os,shutil,time,wave,math,struct,pathlib
base=os.environ.get('LOCAL_MATE_TEST_URL','http://127.0.0.1:3201')
result=json.loads(pathlib.Path('/workspace/work/operations-real-db.log').read_text());booking=result['live_booking'];ref=booking[:8].upper()
wavefile='/workspace/work/localmate-test-tone.wav'
with wave.open(wavefile,'w') as f:
 f.setnchannels(1);f.setsampwidth(2);f.setframerate(48000);f.writeframes(b''.join(struct.pack('<h',int(5000*math.sin(2*math.pi*440*n/48000))) for n in range(48000*3)))
def session(who):return json.load(urllib.request.urlopen('http://127.0.0.1:3211/test/session?who='+who))
def context(browser,who):
 ctx=browser.new_context(permissions=['microphone'],viewport={'width':1400,'height':1100},ignore_https_errors=True)
 value='base64-'+base64.urlsafe_b64encode(json.dumps(session(who),separators=(',',':')).encode()).decode().rstrip('=')
 ctx.add_cookies([{'name':'sb-127-auth-token','value':value,'domain':'127.0.0.1','path':'/','httpOnly':False,'secure':False,'sameSite':'Lax'}]);return ctx
with sync_playwright() as p:
 args=['--no-sandbox','--use-fake-ui-for-media-stream','--use-fake-device-for-media-stream','--use-file-for-fake-audio-capture='+wavefile,'--autoplay-policy=no-user-gesture-required']
 browser=p.chromium.launch(executable_path=shutil.which('chromium'),headless=True,args=args)
 customer=context(browser,'customer');provider=context(browser,'p1');admin=context(browser,'admin');other=context(browser,'other');candidate=context(browser,'p5')
 c=customer.new_page();pr=provider.new_page();errors=[]
 for page in [c,pr]:
  page.on('pageerror',lambda e:errors.append(str(e)))
  page.add_init_script("window.testPeers=[];const OriginalRTC=window.RTCPeerConnection;window.RTCPeerConnection=class extends OriginalRTC{constructor(...args){super(...args);window.testPeers.push(this)}};")
 c.goto(base+'/account',wait_until='domcontentloaded');c.locator('.booking-row').first.wait_for();c.locator('.booking-row').first.click()
 pr.goto(base+'/provider',wait_until='domcontentloaded');pr.get_by_role('button',name='Accepted Jobs',exact=True).click();pr.locator('.booking-row').filter(has_text=ref).click()
 c.get_by_role('button',name='Call Provider',exact=True).wait_for();pr.get_by_role('button',name='Call Customer',exact=True).wait_for()
 assert c.get_by_role('link',name='+919876543201',exact=True).count()==0
 assert pr.get_by_role('link',name='+919876543210',exact=True).count()==0
 def headers():return {'Origin':base,'Content-Type':'application/json'}
 assert candidate.request.post(base+'/api/voice/start',data={'booking_id':booking},headers=headers()).status==403
 assert other.request.post(base+'/api/voice/start',data={'booking_id':booking},headers=headers()).status==403
 def stats(page):return page.evaluate("""async()=>{const pc=window.testPeers.at(-1);if(!pc)return null;const all=Array.from((await pc.getStats()).values());const inbound=all.filter(x=>x.type==='inbound-rtp'&&x.kind==='audio');const transport=all.find(x=>x.type==='transport'&&x.selectedCandidatePairId);const pair=transport&&all.find(x=>x.id===transport.selectedCandidatePairId);const local=pair&&all.find(x=>x.id===pair.localCandidateId);return {state:pc.connectionState,bytes:inbound.reduce((n,x)=>n+(x.bytesReceived||0),0),candidate:local?.candidateType}}""")
 def wait_audio(page,relay=False):
  for i in range(80):
   value=stats(page)
   if value and value['state']=='connected' and value['bytes']>500 and(not relay or value['candidate']=='relay'):return value
   page.wait_for_timeout(500)
  raise AssertionError('No real incoming audio: '+str(stats(page))+' | '+page.locator('body').inner_text()[-2000:])
 c.get_by_role('button',name='Call Provider',exact=True).click();pr.get_by_role('button',name='Accept',exact=True).wait_for(timeout=20000);pr.get_by_role('button',name='Accept',exact=True).click()
 direct_c=wait_audio(c);direct_p=wait_audio(pr)
 c.get_by_role('button',name='Mute',exact=True).click();assert c.evaluate('window.testPeers.at(-1).getSenders().filter(s=>s.track?.kind==="audio").every(s=>s.track.enabled===false)')
 c.get_by_role('button',name='Unmute',exact=True).click();c.get_by_role('button',name='End call',exact=True).click();pr.wait_for_timeout(2200)
 print('DIRECT_AUDIO',direct_c,direct_p,flush=True)
 # Close only call panels, keeping each authenticated booking open.
 for page in [c,pr]:page.get_by_role('button',name='Close call panel',exact=True).click()
 cfg=admin.request.post(base+'/api/operations/config',data={'relay_only':True},headers=headers());assert cfg.ok,cfg.text()
 pr.get_by_role('button',name='Call Customer',exact=True).click();c.get_by_role('button',name='Accept',exact=True).wait_for(timeout=20000);c.get_by_role('button',name='Accept',exact=True).click()
 relay_c=wait_audio(c,True);relay_p=wait_audio(pr,True)
 pr.get_by_role('button',name='End call',exact=True).click();c.wait_for_timeout(2200)
 print('TURN_AUDIO',relay_c,relay_p,flush=True)
 history=customer.request.get(base+'/api/voice/history?booking='+booking).json();assert len(history)>=2;assert all(x['ended_at'] and x['duration_seconds']>=0 for x in history)
 call=history[0]['id'];assert other.request.get(base+'/api/voice/'+call).status==403
 assert admin.request.get(base+'/api/voice/'+call+'/signals').status==403
 # Chat is available independently when calling is disabled.
 assert admin.request.post(base+'/api/operations/config',data={'calling_enabled':False},headers=headers()).ok
 denied=customer.request.post(base+'/api/voice/start',data={'booking_id':booking},headers=headers());assert denied.status>=400
 msg=customer.request.post(base+'/api/bookings/'+booking+'/messages',data={'body':'Work-related message while calling is disabled.'},headers=headers());assert msg.ok,msg.text()
 assert any(x['body']=='Work-related message while calling is disabled.' for x in provider.request.get(base+'/api/bookings/'+booking+'/messages').json())
 # Phone sharing is blocked, including direct backend requests.
 phone=customer.request.post(base+'/api/bookings/'+booking+'/messages',data={'body':'Contact me on +919876543210'},headers=headers());assert phone.status==400
 contacts=customer.request.get(base+'/api/bookings/'+booking+'/contacts').json();assert 'phone' not in json.dumps(contacts)
 assert not errors,errors
 print(json.dumps({'customer_to_provider_real_audio':direct_p,'provider_to_customer_real_audio':relay_c,'forced_coturn_relay_both_peers':[relay_c,relay_p],'mute_control':'passed','history':'passed','booking_authorization':'passed','private_numbers':'passed','chat_when_calls_disabled':'passed','javascript_errors':errors,'hosted_mutations':0}),flush=True)
 browser.close()
