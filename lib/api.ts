import { NextRequest,NextResponse } from 'next/server';
import { createHmac,timingSafeEqual } from 'node:crypto';
import { createClient,isSupabaseConfigured } from './supabase/server';
import { createPaymentAdmin,administrationConfigured,accountManagementHealth } from './supabase/admin';
import {ApiError} from './errors';
import {passwordPublicRoute,updateCredentials,setManagedCredentials,deleteAllData,verifyCurrentPassword} from './password-auth';
import {sameOrigin} from './request-security.mjs';
import { services as starterServices,locations as starterLocations } from '../src/catalog';
const json=(data:unknown,status=200)=>NextResponse.json(data,{status,headers:{'Cache-Control':'no-store'}});
function required(value:unknown,max=2000){if(typeof value!=='string'||!value.trim()||value.length>max)throw new ApiError('Please check the required fields.');return value.trim()}
async function checked(request:PromiseLike<any>){const {data,error}=await request;if(error)throw error;return data;}
const providerDTO=(p:any)=>p?{...p,service_ids:JSON.stringify(p.service_ids),locations:JSON.stringify(p.locations),schedule:JSON.stringify(p.schedule||{})}:null;
const paymentConfigured=()=>!!(process.env.RAZORPAY_KEY_ID&&process.env.RAZORPAY_KEY_SECRET&&process.env.RAZORPAY_WEBHOOK_SECRET&&process.env.SUPABASE_SERVICE_ROLE_KEY);
export async function handleAPI(req:NextRequest){try{return await route(req);}catch(error:any){if(error instanceof ApiError)return json({error:error.message,...error.details},error.status);if(error.code==='42501')return json({error:'You do not have access to this action.'},403);if(error.code==='23505')return json({error:'This request has already been completed. Please refresh.'},409);if(error.code==='P0001')return json({error:error.message},400);if(error.code?.startsWith('22')||error.code==='23514'||error.code==='23503')return json({error:'Please check the values and try again.'},400);if(error.code==='42P01'||error.code==='PGRST205'||error.code==='PGRST202')return json({error:'The Supabase schema is not ready. Apply the database migrations first.'},503);console.error('Local Mate API error:',error.code||error.name);return json({error:'We could not complete this request. Please try again.'},500)}}
async function route(req:NextRequest){
 const p=req.nextUrl.pathname.slice(4),method=req.method;
 if(method!=='GET'&&p!=='/payments/webhook'){
  const origin=req.headers.get('origin');if(!sameOrigin(origin,req.url,req.headers.get('host')))throw new ApiError('This request is not permitted.',403);
  if(!(req.headers.get('content-type')||'').includes('application/json'))throw new ApiError('JSON is required.',415);
 }
 if(p==='/status'){const account=await accountManagementHealth();return json({database:isSupabaseConfigured(),uploads:false,payments:paymentConfigured(),authentication:'username_password',accountManagement:account.ready,accountManagementConfigured:account.configured,accountManagementIssue:account.issue,realtime:isSupabaseConfigured()});}
 if(!isSupabaseConfigured()){
  if(p==='/catalog')return json({services:starterServices.map(s=>({...s,available:false})),locations:starterLocations,configured:false});
  if(p==='/providers')return json([]);
  if(p==='/website')return json({content:{},maintenance_mode:false,customer_portal_enabled:true,provider_portal_enabled:true,registration_enabled:true,bookings_enabled:true});
  throw new ApiError('Supabase is not connected yet. Add the project URL and publishable key in Vercel environment settings.',503);
 }
 if(p==='/payments/webhook'&&method==='POST')return paymentWebhook(req);
 const supabase=await createClient();
 let body:any={};if(!['GET','HEAD','DELETE'].includes(method)){
  if(Number(req.headers.get('content-length')||0)>100000)throw new ApiError('Request is too large.',413);const raw=await req.text();if(raw.length>100000)throw new ApiError('Request is too large.',413);
  try{body=JSON.parse(raw)}catch{throw new ApiError('Invalid JSON request.')}
 }
 const passwordResponse=await passwordPublicRoute(req,p,body,supabase);if(passwordResponse)return passwordResponse;
 if(p==='/website')return json(await checked(supabase.from('website_configuration').select('*').eq('id',true).single()));
 if(p==='/catalog'){
  const [data,areas]=await Promise.all([checked(supabase.from('services').select('*').eq('active',true).order('category').order('name')),checked(supabase.from('locations').select('name').eq('active',true).order('name'))]);
  return json({services:data.length?data:starterServices.map(s=>({...s,available:false})),locations:areas.map((l:any)=>l.name),configured:data.length>0});
 }
 if(p==='/providers')return json((await checked(supabase.from('public_providers').select('*'))).map(providerDTO));
 const {data:{user},error:authError}=await supabase.auth.getUser();
 if(authError||!user)throw new ApiError('Please sign in to continue.',401);
 if(p==='/auth/signout'&&method==='POST'){const {error}=await supabase.auth.signOut();if(error)throw error;return json({ok:true})}
 const [profile,provider,admin,login]=await Promise.all([checked(supabase.from('users').select('*').eq('id',user.id).single()),checked(supabase.from('provider_profiles').select('*').eq('user_id',user.id).maybeSingle()),checked(supabase.rpc('is_admin')),checked(supabase.rpc('login_state'))]);
 if(p==='/me')return json({...profile,email:user.email,username:login?.username||profile.username,must_change_password:!!login?.must_change_password,provider:providerDTO(provider),admin:!!admin});
 if(profile.is_active===false)throw new ApiError('This account has been suspended. Contact support.',403);
 if(p==='/auth/account'&&method==='POST')return json(await updateCredentials(req,user,login,body));
 if(login?.must_change_password)throw new ApiError('Change your temporary password before continuing.',403);
 const config=await checked(supabase.from('website_configuration').select('*').eq('id',true).single());
 if(!admin&&config.maintenance_mode)throw new ApiError('The website is temporarily paused.',503);
 if(!admin&&!config.provider_portal_enabled&&(p.startsWith('/provider/')||req.nextUrl.searchParams.get('role')==='provider'))throw new ApiError('The provider portal is temporarily paused.',403);
 if(p==='/profile'&&method==='POST'){await checked(supabase.rpc('update_profile',{p_name:required(body.name,100),p_phone:required(body.phone,20)}));return json({ok:true})}
 if(p==='/setup'&&method==='POST'){
  if(!admin)throw new ApiError('Administrator access required.',403);
  const existing=await checked(supabase.from('services').select('id'));const ids=new Set(existing.map((s:any)=>s.id));
  for(const name of starterLocations)await checked(supabase.rpc('admin_save_location',{p_name:name,p_active:true}));
  for(const s of starterServices.filter(s=>!ids.has(s.id)))await checked(supabase.rpc('admin_save_service',{p_data:s}));
  return json({ok:true});
 }
 if(p==='/addresses'){
  if(method==='GET')return json(await checked(supabase.from('addresses').select('*').eq('user_id',user.id).order('created_at')));
  if(method==='POST'){
   const data={label:required(body.label,100),address:required(body.address,1000),location:required(body.location,100)};
   const area=await checked(supabase.from('locations').select('name').eq('name',data.location).eq('active',true).maybeSingle());if(!area)throw new ApiError('Choose a supported town.');
   if(body.id){const rows=await checked(supabase.from('addresses').update(data).eq('id',body.id).eq('user_id',user.id).select('id').single());return json(rows)}
   return json(await checked(supabase.from('addresses').insert({...data,user_id:user.id}).select('id').single()));
  }
 }
 if(p.startsWith('/addresses/')&&method==='DELETE'){await checked(supabase.from('addresses').delete().eq('id',p.split('/').pop()).eq('user_id',user.id));return json({ok:true})}
 if(p==='/provider/register'&&method==='POST'){await checked(supabase.rpc('register_provider',{p_data:body}));return json({ok:true,status:'pending'})}
 if(p==='/provider/availability'&&method==='POST'){await checked(supabase.rpc('set_availability',{p_online:body.online===true,p_schedule:body.schedule||{}}));return json({ok:true})}
 if(p==='/bookings'){
  if(method==='GET')return json(await checked(supabase.rpc('list_bookings',{p_role:req.nextUrl.searchParams.get('role')||'customer'})));
  if(method==='POST')return json({id:await checked(supabase.rpc('create_booking',{p_data:body}))},201);
 }
 const match=p.match(/^\/bookings\/([^/]+)(?:\/(.*))?$/);
 if(match){
  const id=match[1],action=match[2];
  if(action==='messages'){
   if(method==='GET')return json(await checked(supabase.rpc('booking_messages',{p_booking:id})));
   if(method==='POST'){await checked(supabase.rpc('send_message',{p_booking:id,p_body:required(body.body,4000)}));return json({ok:true})}
  }
  const booking=await checked(supabase.from('bookings').select('*,services(name,type)').eq('id',id).maybeSingle());if(!booking)throw new ApiError('Booking not found or unavailable to your account.',404);
  if(!action&&method==='GET'){
   const [history,quotes]=await Promise.all([checked(supabase.from('booking_status_history').select('status,note,created_at').eq('booking_id',id).order('id')),checked(supabase.from('quotations').select('*').eq('booking_id',id).order('created_at',{ascending:false}))]);
   return json({...booking,service_name:booking.services.name,service_type:booking.services.type,history,quotes});
  }
  if(action==='invoice'&&method==='GET'){
   if(booking.customer_id!==user.id&&booking.provider_id!==user.id&&!admin)throw new ApiError('Not permitted.',403);
   return json({booking_id:id,service:booking.services.name,amount:booking.estimated_price,status:booking.payment_status,date:booking.created_at,notice:'Service summary. This is not proof of payment.'});
  }
  if(method==='POST'&&['accept','reject','quote','quote-response','reschedule','status','review'].includes(action))return json(await checked(supabase.rpc('booking_action',{p_booking:id,p_action:action,p_data:body})));
 }
 if(p==='/notifications'){
  if(method==='GET')return json(await checked(supabase.from('notifications').select('*').eq('user_id',user.id).order('id',{ascending:false}).limit(100)));
  if(method==='POST'){await checked(supabase.from('notifications').update({is_read:true}).eq('user_id',user.id));return json({ok:true})}
 }
 if(p==='/support'){
  if(method==='GET')return json(await checked(supabase.from('support_tickets').select('*').order('created_at',{ascending:false})));
  if(method==='POST')return json(await checked(supabase.from('support_tickets').insert({user_id:user.id,subject:required(body.subject,200),body:required(body.body,4000),booking_id:body.booking_id||null}).select('id').single()));
 }
 if(p==='/favourites'){
  if(method==='GET')return json(await checked(supabase.from('favourites').select('provider_id').eq('user_id',user.id)));
  if(method==='POST'){
   if(body.remove)await checked(supabase.from('favourites').delete().eq('user_id',user.id).eq('provider_id',body.provider_id));
   else{const {error}=await supabase.from('favourites').insert({user_id:user.id,provider_id:body.provider_id});if(error&&error.code!=='23505')throw error;}
   return json({ok:true});
  }
 }
 if(p==='/payments'&&method==='GET')return json(await checked(supabase.from('payments').select('*').order('created_at',{ascending:false})));
 if(p==='/payments/order'&&method==='POST'){
  if(!paymentConfigured())throw new ApiError('Online payments are not configured. Pay after service is available.',503);
  const reservation=await checked(supabase.rpc('reserve_payment',{p_booking:body.booking_id}));
  if(reservation.gateway_order_id)return json({order_id:reservation.gateway_order_id,key_id:process.env.RAZORPAY_KEY_ID,amount:reservation.amount*100});
  const gateway=await fetch('https://api.razorpay.com/v1/orders',{method:'POST',headers:{Authorization:'Basic '+Buffer.from(process.env.RAZORPAY_KEY_ID+':'+process.env.RAZORPAY_KEY_SECRET).toString('base64'),'Content-Type':'application/json'},body:JSON.stringify({amount:reservation.amount*100,currency:'INR',receipt:reservation.id}),signal:AbortSignal.timeout(15000)});
  if(!gateway.ok)throw new ApiError('The payment gateway could not create an order.',502);const order=await gateway.json();
  const adminClient=createPaymentAdmin();const saved=await checked(adminClient.rpc('attach_payment_order',{p_payment:reservation.id,p_order:order.id}));
  return json({order_id:saved,key_id:process.env.RAZORPAY_KEY_ID,amount:reservation.amount*100});
 }
 if(p.startsWith('/admin/')){
  if(!admin)throw new ApiError('Administrator access required.',403);
  if(p==='/admin/website'){
   if(method==='GET')return json(config);
   if(method==='POST'){await checked(supabase.rpc('admin_save_website',{p_data:body}));return json({ok:true});}
  }
  if(p==='/admin/locations'){
   if(method==='GET')return json(await checked(supabase.from('locations').select('*').order('name')));
   if(method==='POST'){await checked(supabase.rpc('admin_save_location',{p_name:required(body.name,100),p_active:body.active===true}));return json({ok:true});}
  }
  if(p==='/admin/account-status'&&method==='POST'){await checked(supabase.rpc('admin_account_status',{p_user:body.user_id,p_active:body.is_active===true}));return json({ok:true});}
  if(p==='/admin/credentials'&&method==='POST')return json(await setManagedCredentials(user.id,body));
  if(p==='/admin/backup'&&method==='POST')return json(await checked(supabase.rpc('export_marketplace')));
  if(p==='/admin/reset'&&method==='POST')return json(await deleteAllData(req,user,supabase,body));
  if(p==='/admin/overview'){
   const [customers,pros,pending,bookings,paid,commission]=await Promise.all([supabase.from('users').select('*',{count:'exact',head:true}),supabase.from('provider_profiles').select('*',{count:'exact',head:true}),supabase.from('provider_profiles').select('*',{count:'exact',head:true}).eq('status','pending'),supabase.from('bookings').select('*',{count:'exact',head:true}),supabase.from('payments').select('amount').eq('status','successful'),supabase.from('settings').select('value').eq('key','commission').maybeSingle()]);
   for(const result of [customers,pros,pending,bookings,paid,commission])if(result.error)throw result.error;
   return json({customers:customers.count||0,providers:pros.count||0,pending:pending.count||0,bookings:bookings.count||0,paid:(paid.data||[]).reduce((sum:number,p:any)=>sum+p.amount,0),commission:commission.data?.value??10});
  }
  if(p==='/admin/providers'&&method==='GET')return json((await checked(supabase.from('provider_profiles').select('*,users(name,email,phone)').order('created_at',{ascending:false}))).map((row:any)=>({...providerDTO(row),...row.users})));
  if(p==='/admin/provider'&&method==='POST'){await checked(supabase.rpc('admin_provider',{p_user:body.user_id,p_status:body.status}));return json({ok:true})}
  if(p==='/admin/users'&&method==='GET')return json(await checked(supabase.from('users').select('*').order('created_at',{ascending:false})));
  if(p==='/admin/services'){
   if(method==='GET')return json(await checked(supabase.from('services').select('*').order('category').order('name')));
   if(method==='POST')return json({id:await checked(supabase.rpc('admin_save_service',{p_data:body}))});
  }
  if(p==='/admin/assign'&&method==='POST'){await checked(supabase.rpc('admin_assign',{p_booking:body.booking_id,p_provider:body.provider_id}));return json({ok:true})}
  if(p==='/admin/commission'&&method==='POST'){await checked(supabase.rpc('admin_commission',{p_percent:body.percent}));return json({ok:true})}
  if(p==='/admin/support'&&method==='POST'){await checked(supabase.rpc('admin_support',{p_ticket:body.id,p_status:body.status,p_resolution:body.resolution}));return json({ok:true})}
  if(p==='/admin/logs')return json(await checked(supabase.from('admin_activity_logs').select('*').order('id',{ascending:false}).limit(100)));
 }
 throw new ApiError('This action is not available.',404);
}
async function paymentWebhook(req:NextRequest){
 if(!paymentConfigured())throw new ApiError('Payment webhooks are not configured.',503);
 const raw=await req.text();if(raw.length>200000)throw new ApiError('Request is too large.',413);
 const signature=req.headers.get('x-razorpay-signature')||'';
 const expected=createHmac('sha256',process.env.RAZORPAY_WEBHOOK_SECRET!).update(raw).digest();
 if(!/^[a-f0-9]{64}$/i.test(signature)||!timingSafeEqual(expected,Buffer.from(signature,'hex')))throw new ApiError('Invalid webhook signature.',403);
 const event=JSON.parse(raw);if(event.event!=='payment.captured')return json({received:true});
 const payment=event.payload?.payment?.entity;if(payment?.currency!=='INR')throw new ApiError('Payment currency does not match.');
 const client=createPaymentAdmin();await checked(client.rpc('record_payment_capture',{p_order:payment.order_id,p_gateway_payment:payment.id,p_amount_paise:payment.amount}));
 return json({received:true});
}
