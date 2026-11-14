import {html,house,assets} from '../dist/document.js';
import {services,locations,workflow} from './catalog.js';
const uid=()=>crypto.randomUUID();
const response=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{'content-type':'application/json','cache-control':'no-store'}});
const fail=(message,status=400)=>{throw Object.assign(new Error(message),{status})};
const text=(value,max=2000)=>{if(typeof value!=='string'||!value.trim()||value.length>max)fail('Please check the required fields.');return value.trim()};
const money=value=>{const n=Number(value);if(!Number.isSafeInteger(n)||n<0||n>10000000)fail('Enter a valid amount in rupees.');return n};
const sql=(env,query,...args)=>env.DB.prepare(query).bind(...args);
const rows=async(env,q,...args)=>(await sql(env,q,...args).all()).results;
const one=async(env,q,...args)=>sql(env,q,...args).first();
export function isAdmin(email,env){return (env.ADMIN_EMAILS||'').split(',').map(x=>x.trim().toLowerCase()).filter(Boolean).includes((email||'').toLowerCase())}
export function eligible(provider,booking){return provider?.status==='approved'&&!!provider.online&&JSON.parse(provider.service_ids||'[]').includes(booking.service_id)&&JSON.parse(provider.locations||'[]').includes(booking.location)}
export function transitionAllowed(current,next,role){return role==='admin'||(workflow[current]||[]).includes(next)}
async function notify(env,user,title,booking=null){if(user)await sql(env,'INSERT INTO notifications(id,user_id,title,booking_id) VALUES(?,?,?,?)',uid(),user,title,booking).run()}
async function history(env,booking,actor,status,note=''){await sql(env,'INSERT INTO booking_status_history(id,booking_id,actor_id,status,note) VALUES(?,?,?,?,?)',uid(),booking,actor,status,note).run()}
async function audit(env,actor,action,target=''){await sql(env,'INSERT INTO admin_activity_logs(id,actor_id,action,target_id) VALUES(?,?,?,?)',uid(),actor,action,target).run()}
async function handler(req,env){
 const url=new URL(req.url),p=url.pathname,method=req.method;
 if(assets[p])return new Response(Uint8Array.from(atob(assets[p]),c=>c.charCodeAt(0)),{headers:{'content-type':'image/png','cache-control':'public,max-age=86400'}});
 if(p==='/assets/house.svg')return new Response(house,{headers:{'content-type':'image/svg+xml','cache-control':'public,max-age=86400'}});
 if(!p.startsWith('/api/'))return new Response(html,{headers:{'content-type':'text/html;charset=utf-8','x-content-type-options':'nosniff','referrer-policy':'strict-origin-when-cross-origin','content-security-policy':"default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; img-src 'self' data:; connect-src 'self'; frame-ancestors 'self' https://chatgpt.com https://*.chatgpt.com"}});
 if(p==='/api/status')return response({database:!!env.DB,uploads:!!env.BUCKET,payments:!!(env.RAZORPAY_KEY_ID&&env.RAZORPAY_KEY_SECRET&&env.RAZORPAY_WEBHOOK_SECRET),adminConfigured:!!env.ADMIN_EMAILS});
 if(p==='/api/catalog'&&method==='GET'){
  if(!env.DB)return response({services:services.map(s=>({...s,available:false})),locations,configured:false});
  const data=await rows(env,'SELECT * FROM services WHERE active=1');return response({services:data.length?data:services.map(s=>({...s,available:false})),locations,configured:data.length>0});
 }
 if(p==='/api/providers'&&method==='GET'){
  if(!env.DB)return response([]);
  return response(await rows(env,"SELECT p.user_id,p.business_name,p.category,p.description,p.experience,p.service_ids,p.locations,p.online,u.name,(SELECT AVG(r.rating) FROM reviews r WHERE r.provider_id=p.user_id) rating,(SELECT COUNT(*) FROM reviews r WHERE r.provider_id=p.user_id) review_count FROM provider_profiles p JOIN users u ON u.id=p.user_id WHERE p.status='approved'"));
 }
 if(!env.DB)fail('The booking database is not connected yet. Please try again after setup.',503);
 if(method!=='GET'){
  if(req.headers.get('origin')&&req.headers.get('origin')!==url.origin)fail('This request is not permitted.',403);
  if(Number(req.headers.get('content-length')||0)>100000)fail('Request is too large.',413);
 }
 // Webhooks are authenticated by their signed raw body, never by browser state.
 if(p==='/api/payments/webhook'&&method==='POST'){
  if(!env.RAZORPAY_WEBHOOK_SECRET)fail('Payment webhooks are not configured.',503);
  const raw=await req.text(),signature=req.headers.get('x-razorpay-signature')||'';
  const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(env.RAZORPAY_WEBHOOK_SECRET),{name:'HMAC',hash:'SHA-256'},false,['verify']);
  if(!/^[a-f0-9]{64}$/i.test(signature))fail('Invalid signature.',403);
  if(!await crypto.subtle.verify('HMAC',key,Uint8Array.from(signature.match(/../g),x=>parseInt(x,16)),new TextEncoder().encode(raw)))fail('Invalid signature.',403);
  const event=JSON.parse(raw);if(event.event!=='payment.captured')return response({received:true});
  const payment=event.payload?.payment?.entity,record=await one(env,'SELECT * FROM payments WHERE gateway_order_id=?',payment?.order_id||'');
  if(!record||payment.currency!=='INR'||payment.amount!==record.amount*100)fail('Payment amount does not match.');
  await env.DB.batch([sql(env,"UPDATE payments SET status='successful',gateway_payment_id=? WHERE id=? AND status<>'successful'",payment.id,record.id),sql(env,"UPDATE bookings SET payment_status='successful' WHERE id=?",record.booking_id)]);return response({received:true});
 }
 const userId=req.headers.get('oai-authenticated-user-id'),email=req.headers.get('oai-authenticated-user-email');
 if(!userId||!email)fail('Please sign in to continue.',401);
 let name=req.headers.get('oai-authenticated-user-full-name')||email.split('@')[0];try{if(req.headers.get('oai-authenticated-user-full-name-encoding')==='percent-encoded-utf-8')name=decodeURIComponent(name)}catch{}
 await sql(env,'INSERT OR IGNORE INTO users(id,email,name) VALUES(?,?,?)',userId,email,name).run();
 if(method!=='GET'){const window=Math.floor(Date.now()/60000);await sql(env,'INSERT OR IGNORE INTO request_windows(user_id,window,hits) VALUES(?,?,0)',userId,window).run();const limit=await sql(env,'UPDATE request_windows SET hits=hits+1 WHERE user_id=? AND window=? AND hits<60',userId,window).run();if(!limit.meta.changes)fail('Too many updates. Please try again in a minute.',429);}
 const me=await one(env,'SELECT * FROM users WHERE id=?',userId),provider=await one(env,'SELECT * FROM provider_profiles WHERE user_id=?',userId),admin=isAdmin(email,env);
 let body={};if(method!=='GET'&&method!=='DELETE'){if(!(req.headers.get('content-type')||'').includes('application/json'))fail('JSON is required.',415);try{const raw=await req.text();if(raw.length>100000)fail('Request too large.',413);body=JSON.parse(raw)}catch(e){if(e.status)throw e;fail('Invalid request.')}}
 if(p==='/api/me'&&method==='GET')return response({...me,provider,admin});
 if(p==='/api/profile'&&method==='POST'){const phone=text(body.phone,20);if(!/^(\+91)?[6-9]\d{9}$/.test(phone.replace(/[ -]/g,'')))fail('Enter a valid Indian mobile number.');await sql(env,'UPDATE users SET name=?,phone=? WHERE id=?',text(body.name,100),phone,userId).run();return response({ok:true})}
 if(p==='/api/setup'&&method==='POST'){
  if(!admin)fail('An administrator must initialize the service catalogue.',403);
  await env.DB.batch(services.map(s=>sql(env,'INSERT OR IGNORE INTO services(id,name,category,description,price,type,icon,tone) VALUES(?,?,?,?,?,?,?,?)',s.id,s.name,s.category,s.description,s.price,s.type,s.icon,s.tone)));await audit(env,userId,'Initialize service catalogue');return response({ok:true});
 }
 if(p==='/api/addresses'){
  if(method==='GET')return response(await rows(env,'SELECT * FROM addresses WHERE user_id=?',userId));
  if(method==='POST'){if(!locations.includes(body.location))fail('Choose a supported town.');const id=body.id||uid();if(body.id&&!await one(env,'SELECT id FROM addresses WHERE id=? AND user_id=?',id,userId))fail('Address not found.',404);await sql(env,'INSERT INTO addresses(id,user_id,label,address,location) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET label=excluded.label,address=excluded.address,location=excluded.location',id,userId,text(body.label,100),text(body.address,1000),body.location).run();return response({id})}
 }
 if(p.startsWith('/api/addresses/')&&method==='DELETE'){await sql(env,'DELETE FROM addresses WHERE id=? AND user_id=?',p.split('/').pop(),userId).run();return response({ok:true})}
 if(p==='/api/provider/register'&&method==='POST'){
  if(provider)fail('Your provider application already exists.');
  if(!Array.isArray(body.service_ids)||!body.service_ids.length||!body.service_ids.every(x=>typeof x==='string'))fail('Choose at least one service.');
  for(const serviceId of body.service_ids){if(!await one(env,'SELECT id FROM services WHERE id=? AND active=1',serviceId))fail('Choose an active service.');}
  if(!Array.isArray(body.locations)||!body.locations.length||!body.locations.every(x=>locations.includes(x)))fail('Choose your service areas.');
  if(!me.phone)fail('Add your mobile number in your profile before applying.');
  await sql(env,'INSERT INTO provider_profiles(user_id,business_name,category,service_ids,locations,description,experience) VALUES(?,?,?,?,?,?,?)',userId,(body.business_name||'').slice(0,100),text(body.category,100),JSON.stringify(body.service_ids),JSON.stringify(body.locations),text(body.description,2000),money(body.experience)).run();return response({ok:true,status:'pending'});
 }
 if(p==='/api/provider/availability'&&method==='POST'){if(!provider)fail('Provider registration is required.',403);await sql(env,'UPDATE provider_profiles SET online=?,schedule=? WHERE user_id=?',body.online?1:0,JSON.stringify(body.schedule||{}),userId).run();return response({ok:true})}
 if(p==='/api/bookings'&&method==='GET'){
  const role=url.searchParams.get('role');if(role==='admin'&&!admin)fail('Administrator access required.',403);
  if(role==='provider'){
   if(!provider)return response([]);
   const data=await rows(env,"SELECT b.*,s.name service_name,u.name customer_name FROM bookings b JOIN services s ON s.id=b.service_id JOIN users u ON u.id=b.customer_id WHERE b.provider_id=? OR (b.provider_id IS NULL AND b.status='requested' AND NOT EXISTS(SELECT 1 FROM booking_rejections r WHERE r.booking_id=b.id AND r.provider_id=?)) ORDER BY b.created_at DESC",userId,userId);
   return response(data.filter(b=>b.provider_id===userId||eligible(provider,b)));
  }
  return response(await rows(env,'SELECT b.*,s.name service_name,u.name provider_name FROM bookings b JOIN services s ON s.id=b.service_id LEFT JOIN users u ON u.id=b.provider_id '+(role==='admin'?'':'WHERE b.customer_id=? ')+'ORDER BY b.created_at DESC',...(role==='admin'?[]:[userId])));
 }
 if(p==='/api/bookings'&&method==='POST'){
  const service=await one(env,'SELECT * FROM services WHERE id=? AND active=1',body.service_id);if(!service)fail('This service is not open for booking yet.');
  if(!locations.includes(body.location))fail('Choose a supported location.');
  const candidates=await rows(env,"SELECT * FROM provider_profiles WHERE status='approved' AND online=1");if(!candidates.some(pr=>eligible(pr,{service_id:service.id,location:body.location})))fail('There are no available, approved providers for this service in '+body.location+' yet. Please check back soon.');
  const date=new Date(body.scheduled_at);if(!Number.isFinite(date.getTime())||date.getTime()<Date.now())fail('Choose a future date and time.');
  const details=body.details||{};if(['transport','goods'].includes(service.type)&&!details.destination)fail('Enter your destination.');if(service.type==='rental'&&(!details.end_date||new Date(details.end_date)<date))fail('Choose a rental end date after the start date.');
  if(body.payment_method!=='cash')fail('Online payment is not enabled for booking. Choose pay after service.');
  const id=uid(),idem=text(body.idempotency_key,100);const existing=await one(env,'SELECT id FROM bookings WHERE customer_id=? AND idempotency_key=?',userId,idem);if(existing)return response(existing);
  await sql(env,'INSERT INTO bookings(id,customer_id,service_id,location,address,scheduled_at,description,details,estimated_price,payment_method,idempotency_key) VALUES(?,?,?,?,?,?,?,?,?,?,?)',id,userId,service.id,body.location,text(body.address,1000),date.toISOString(),text(body.description,4000),JSON.stringify(details),service.price,'cash',idem).run();
  await history(env,id,userId,'requested');await notify(env,userId,'Your booking request has been created',id);for(const pr of candidates.filter(pr=>eligible(pr,{service_id:service.id,location:body.location})))await notify(env,pr.user_id,'New '+service.name+' request in '+body.location,id);return response({id},201);
 }
 const match=p.match(/^\/api\/bookings\/([^/]+)(?:\/(.*))?$/);
 if(match){
  const id=match[1],action=match[2],booking=await one(env,'SELECT b.*,s.type service_type,s.name service_name FROM bookings b JOIN services s ON s.id=b.service_id WHERE b.id=?',id);if(!booking)fail('Booking not found.',404);
  const customer=booking.customer_id===userId,assigned=booking.provider_id===userId,candidate=!booking.provider_id&&booking.status==='requested'&&eligible(provider,booking)&&!await one(env,'SELECT 1 FROM booking_rejections WHERE booking_id=? AND provider_id=?',id,userId);
  if(!customer&&!assigned&&!candidate&&!admin)fail('You do not have access to this booking.',403);
  if(!action&&method==='GET')return response({...booking,history:await rows(env,'SELECT status,note,created_at FROM booking_status_history WHERE booking_id=? ORDER BY created_at,rowid',id),quotes:await rows(env,'SELECT * FROM quotations WHERE booking_id=? ORDER BY created_at DESC',id)});
  if(action==='messages'){
   if(candidate)fail('Accept the booking before opening its conversation.',403);
   if(method==='GET')return response(await rows(env,'SELECT m.*,u.name sender_name FROM messages m JOIN users u ON u.id=m.sender_id WHERE booking_id=? ORDER BY m.created_at,m.rowid',id));
   if(method==='POST'){await sql(env,'INSERT INTO messages(id,booking_id,sender_id,body) VALUES(?,?,?,?)',uid(),id,userId,text(body.body,4000)).run();await notify(env,customer?booking.provider_id:booking.customer_id,'New message about your booking',id);return response({ok:true})}
  }
  if(action==='accept'&&method==='POST'){
   if(!candidate)fail('This request is no longer available.',409);if(booking.service_type==='quote')fail('Send a quotation for this project first.');
   const result=await sql(env,"UPDATE bookings SET provider_id=?,status='confirmed' WHERE id=? AND provider_id IS NULL AND status='requested'",userId,id).run();if(!result.meta.changes)fail('Another provider has already accepted.',409);await history(env,id,userId,'confirmed');await notify(env,booking.customer_id,'Your provider has accepted the booking',id);return response({ok:true});
  }
  if(action==='reject'&&method==='POST'){if(!candidate)fail('Request is not available.',409);await sql(env,'INSERT OR IGNORE INTO booking_rejections(booking_id,provider_id) VALUES(?,?)',id,userId).run();return response({ok:true})}
  if(action==='quote'&&method==='POST'){
   if(!(candidate||assigned)||!['requested','confirmed'].includes(booking.status))fail('A quotation cannot be sent now.',409);
   const labour=money(body.labour),materials=money(body.materials),additional=money(body.additional||0),quoteId=uid();
   const result=await sql(env,"UPDATE bookings SET provider_id=?,status='quote_sent' WHERE id=? AND status IN ('requested','confirmed') AND (provider_id IS NULL OR provider_id=?)",userId,id,userId).run();if(!result.meta.changes)fail('This request is no longer available.',409);
   await sql(env,'INSERT INTO quotations(id,booking_id,provider_id,labour,materials,additional,terms) VALUES(?,?,?,?,?,?,?)',quoteId,id,userId,labour,materials,additional,text(body.terms,2000)).run();await history(env,id,userId,'quote_sent');await notify(env,booking.customer_id,'A quotation is ready for your approval',id);return response({id:quoteId});
  }
  if(action==='quote-response'&&method==='POST'){
   if(!customer||booking.status!=='quote_sent')fail('Only the customer can respond to this quotation.',403);const quote=await one(env,"SELECT * FROM quotations WHERE id=? AND booking_id=? AND status='pending'",body.quote_id,id);if(!quote)fail('Quotation is no longer pending.',409);
   const accept=body.accept===true;await env.DB.batch([sql(env,'UPDATE quotations SET status=? WHERE id=?',accept?'approved':'rejected',quote.id),sql(env,'UPDATE bookings SET status=?,estimated_price=?,provider_id=? WHERE id=?',accept?'confirmed':'requested',accept?quote.labour+quote.materials+quote.additional:booking.estimated_price,accept?booking.provider_id:null,id)]);await history(env,id,userId,accept?'confirmed':'requested');await notify(env,quote.provider_id,accept?'Your quotation was approved':'Your quotation was declined',id);return response({ok:true});
  }
  if(action==='reschedule'&&method==='POST'){if(!customer||!['requested','confirmed'].includes(booking.status))fail('This booking cannot be rescheduled.',409);const date=new Date(body.scheduled_at);if(!Number.isFinite(date.getTime())||date.getTime()<Date.now())fail('Choose a future date and time.');await sql(env,'UPDATE bookings SET scheduled_at=? WHERE id=?',date.toISOString(),id).run();await history(env,id,userId,booking.status,'Rescheduled to '+date.toISOString());await notify(env,booking.provider_id,'A booking has been rescheduled',id);return response({ok:true})}
  if(action==='status'&&method==='POST'){
   const next=body.status;if(!transitionAllowed(booking.status,next,admin?'admin':'user')||!['cancelled','disputed','on_the_way','arrived','work_started','work_paused','work_completed'].includes(next))fail('This status change is not permitted.',409);
   if(!admin&&!assigned&&!(customer&&['cancelled','disputed'].includes(next)))fail('Only the assigned provider can update this job.',403);
   if(customer&&next==='cancelled'&&!['requested','quote_sent','confirmed','on_the_way','arrived'].includes(booking.status))fail('Contact support to cancel a job after work starts.',409);
   const result=await sql(env,'UPDATE bookings SET status=? WHERE id=? AND status=?',next,id,booking.status).run();if(!result.meta.changes)fail('Booking changed. Please refresh.',409);await history(env,id,userId,next);await notify(env,customer?booking.provider_id:booking.customer_id,'Booking update: '+next.replaceAll('_',' '),id);return response({ok:true});
  }
  if(action==='review'&&method==='POST'){if(!customer||booking.status!=='work_completed'||!booking.provider_id)fail('Reviews are available after a completed booking.',403);const rating=Number(body.rating);if(!Number.isInteger(rating)||rating<1||rating>5)fail('Choose a rating between 1 and 5.');if(await one(env,'SELECT id FROM reviews WHERE booking_id=?',id))fail('You have already reviewed this booking.');await sql(env,'INSERT INTO reviews(id,booking_id,customer_id,provider_id,rating,body) VALUES(?,?,?,?,?,?)',uid(),id,userId,booking.provider_id,rating,text(body.body,2000)).run();return response({ok:true})}
  if(action==='invoice'&&method==='GET'){if(candidate)fail('Not permitted.',403);return response({booking_id:id,service:booking.service_name,amount:booking.estimated_price,status:booking.payment_status,date:booking.created_at,notice:'Service summary. This is not proof of payment.'})}
 }
 if(p==='/api/notifications'){
  if(method==='GET')return response(await rows(env,'SELECT * FROM notifications WHERE user_id=? ORDER BY created_at DESC LIMIT 100',userId));
  if(method==='POST'){await sql(env,'UPDATE notifications SET is_read=1 WHERE user_id=?',userId).run();return response({ok:true})}
 }
 if(p==='/api/support'){
  if(method==='GET')return response(await rows(env,'SELECT * FROM support_tickets '+(admin?'':'WHERE user_id=? ')+'ORDER BY created_at DESC',...(admin?[]:[userId])));
  if(method==='POST'){if(body.booking_id&&!await one(env,'SELECT id FROM bookings WHERE id=? AND (customer_id=? OR provider_id=?)',body.booking_id,userId,userId))fail('Booking not found.',404);const id=uid();await sql(env,'INSERT INTO support_tickets(id,user_id,booking_id,subject,body) VALUES(?,?,?,?,?)',id,userId,body.booking_id||null,text(body.subject,200),text(body.body,4000)).run();return response({id})}
 }
 if(p==='/api/favourites'){
  if(method==='GET')return response(await rows(env,'SELECT provider_id FROM favourites WHERE user_id=?',userId));
  if(method==='POST'){if(!await one(env,"SELECT user_id FROM provider_profiles WHERE user_id=? AND status='approved'",body.provider_id))fail('Provider not found.',404);if(body.remove)await sql(env,'DELETE FROM favourites WHERE user_id=? AND provider_id=?',userId,body.provider_id).run();else await sql(env,'INSERT OR IGNORE INTO favourites(user_id,provider_id) VALUES(?,?)',userId,body.provider_id).run();return response({ok:true})}
 }
 if(p==='/api/payments'&&method==='GET')return response(await rows(env,'SELECT p.* FROM payments p JOIN bookings b ON b.id=p.booking_id WHERE b.customer_id=? ORDER BY p.created_at DESC',userId));
 if(p==='/api/payments/order'&&method==='POST'){
  if(!env.RAZORPAY_KEY_ID||!env.RAZORPAY_KEY_SECRET||!env.RAZORPAY_WEBHOOK_SECRET)fail('Online payments are not configured. Pay after service is available.',503);
  const booking=await one(env,"SELECT * FROM bookings WHERE id=? AND customer_id=? AND status='work_completed' AND payment_status='pending'",body.booking_id,userId);if(!booking||booking.estimated_price<=0)fail('This booking is not ready for payment.');
  const existing=await one(env,"SELECT * FROM payments WHERE booking_id=? AND status='pending'",booking.id);if(existing)return response({order_id:existing.gateway_order_id,key_id:env.RAZORPAY_KEY_ID,amount:existing.amount*100});
  const gateway=await fetch('https://api.razorpay.com/v1/orders',{method:'POST',headers:{Authorization:'Basic '+btoa(env.RAZORPAY_KEY_ID+':'+env.RAZORPAY_KEY_SECRET),'Content-Type':'application/json'},body:JSON.stringify({amount:booking.estimated_price*100,currency:'INR',receipt:booking.id})});if(!gateway.ok)fail('The payment gateway could not create an order.',502);const order=await gateway.json();await sql(env,'INSERT INTO payments(id,booking_id,amount,gateway_order_id) VALUES(?,?,?,?)',uid(),booking.id,booking.estimated_price,order.id).run();return response({order_id:order.id,key_id:env.RAZORPAY_KEY_ID,amount:order.amount});
 }
 if(p.startsWith('/api/admin/')){
  if(!admin)fail('Administrator access required. Configure ADMIN_EMAILS for authorized administrators.',403);
  if(p==='/api/admin/overview')return response({customers:(await one(env,'SELECT COUNT(*) n FROM users')).n,providers:(await one(env,'SELECT COUNT(*) n FROM provider_profiles')).n,pending:(await one(env,"SELECT COUNT(*) n FROM provider_profiles WHERE status='pending'")).n,bookings:(await one(env,'SELECT COUNT(*) n FROM bookings')).n,paid:(await one(env,"SELECT COALESCE(SUM(amount),0) n FROM payments WHERE status='successful'")).n,commission:JSON.parse((await one(env,"SELECT value FROM settings WHERE key='commission'"))?.value||'10')});
  if(p==='/api/admin/providers'&&method==='GET')return response(await rows(env,'SELECT p.*,u.name,u.email,u.phone FROM provider_profiles p JOIN users u ON u.id=p.user_id ORDER BY p.created_at DESC'));
  if(p==='/api/admin/provider'&&method==='POST'){if(!['approved','rejected','suspended','pending'].includes(body.status))fail('Invalid provider status.');await sql(env,'UPDATE provider_profiles SET status=? WHERE user_id=?',body.status,body.user_id).run();await audit(env,userId,'Provider '+body.status,body.user_id);await notify(env,body.user_id,'Your provider application is '+body.status);return response({ok:true})}
  if(p==='/api/admin/users'&&method==='GET')return response(await rows(env,'SELECT * FROM users ORDER BY created_at DESC'));
  if(p==='/api/admin/services'&&method==='GET')return response(await rows(env,'SELECT * FROM services ORDER BY category,name'));
  if(p==='/api/admin/services'&&method==='POST'){
   if(!['fixed','quote','transport','goods','rental','emergency'].includes(body.type))fail('Choose a valid booking type.');const id=body.id||uid();await sql(env,'INSERT INTO services(id,name,category,description,price,type,icon,tone,active) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,category=excluded.category,description=excluded.description,price=excluded.price,type=excluded.type,active=excluded.active',id,text(body.name,100),text(body.category,100),text(body.description,1000),money(body.price),body.type,body.icon||'🔧',body.tone||'blue',body.active===false?0:1).run();await audit(env,userId,'Save service',id);return response({id});
  }
  if(p==='/api/admin/assign'&&method==='POST'){const booking=await one(env,'SELECT * FROM bookings WHERE id=?',body.booking_id),pr=await one(env,'SELECT * FROM provider_profiles WHERE user_id=?',body.provider_id);if(!booking||!eligible(pr,booking)||!['requested','confirmed','quote_sent'].includes(booking.status))fail('Choose an approved, available provider matching this service and location.');await sql(env,"UPDATE bookings SET provider_id=?,status='confirmed' WHERE id=?",body.provider_id,booking.id).run();await history(env,booking.id,userId,'confirmed','Assigned by administrator');await audit(env,userId,'Assign booking',booking.id);return response({ok:true})}
  if(p==='/api/admin/commission'&&method==='POST'){const n=Number(body.percent);if(!Number.isFinite(n)||n<0||n>100)fail('Commission must be between 0 and 100.');await sql(env,"INSERT INTO settings(key,value) VALUES('commission',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",JSON.stringify(n)).run();await audit(env,userId,'Update commission');return response({ok:true})}
  if(p==='/api/admin/support'&&method==='POST'){if(!['open','under_review','resolved','closed'].includes(body.status))fail('Invalid ticket status.');await sql(env,'UPDATE support_tickets SET status=?,resolution=? WHERE id=?',body.status,text(body.resolution,4000),body.id).run();await audit(env,userId,'Resolve support ticket',body.id);return response({ok:true})}
  if(p==='/api/admin/logs')return response(await rows(env,'SELECT * FROM admin_activity_logs ORDER BY created_at DESC LIMIT 100'));
 }
 fail('This action is not available.',404);
}
export default {async fetch(req,env){try{return await handler(req,env)}catch(error){if(!error.status)console.error(error.message);return response({error:error.status?error.message:'We could not complete this request. Please try again.'},error.status||500)}}};
