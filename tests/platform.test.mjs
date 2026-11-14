import {test,beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import worker from '../dist/server/index.js';
let env;
function adapter(db) {
 return {
  prepare(q) {
   return {bind(...args) {
    return {
     async first() {return db.prepare(q).get(...args)||null;},
     async all() {return {results:db.prepare(q).all(...args)};},
     async run() {const r=db.prepare(q).run(...args);return {meta:{changes:Number(r.changes)}};}
    };
   }};
  },
  async batch(queries) {
   db.exec('BEGIN');
   try {const out=[];for(const q of queries) out.push(await q.run());db.exec('COMMIT');return out;}
   catch(e) {db.exec('ROLLBACK');throw e;}
  }
 };
}
beforeEach(()=>{const db=new DatabaseSync(':memory:');db.exec(readFileSync(new URL('../migrations/0001_initial.sql',import.meta.url),'utf8'));env={DB:adapter(db),ADMIN_EMAILS:'admin@example.com'};});
async function call(path,{user='customer',body,method,extraHeaders={}}={}){const headers={'origin':'https://local.test',...extraHeaders};if(user){headers['oai-authenticated-user-id']=user;headers['oai-authenticated-user-email']=user==='admin'?'admin@example.com':user+'@example.com';}if(body)headers['content-type']='application/json';const r=await worker.fetch(new Request('https://local.test/api'+path,{method:method||(body?'POST':'GET'),headers,body:body?JSON.stringify(body):undefined}),env);return {status:r.status,data:await r.json()}}
const post=(path,body,user='customer')=>call(path,{user,body});
async function setup(){assert.equal((await post('/setup',{},'admin')).status,200);await call('/me');await post('/profile',{name:'Local technician',phone:'+919876543210'},'pro');await post('/provider/register',{category:'Home care',service_ids:['plumbing','painting'],locations:['Pattambi'],description:'Local plumbing and painting services',experience:5},'pro');}
async function approve(){await post('/admin/provider',{user_id:'pro',status:'approved'},'admin');await post('/provider/availability',{online:true},'pro')}
const booking=(service='plumbing',key=crypto.randomUUID())=>({service_id:service,location:'Pattambi',address:'Test home, Pattambi',scheduled_at:new Date(Date.now()+86400000).toISOString(),description:'A tap needs attention.',payment_method:'cash',idempotency_key:key});
test('anonymous users cannot read private records; admin role never comes from a request body',async()=>{assert.equal((await call('/bookings',{user:null})).status,401);assert.equal((await post('/setup',{admin:true})).status,403);assert.equal((await call('/admin/users')).status,403);assert.equal((await call('/me')).data.admin,false)});
test('catalogue initializes without fabricated people or reviews',async()=>{await setup();const cat=await call('/catalog');assert.ok(cat.data.services.length>=18);assert.deepEqual((await call('/providers')).data,[]);assert.equal((await call('/admin/overview',{user:'admin'})).data.paid,0)});
test('pending and offline providers cannot receive bookings',async()=>{await setup();assert.equal((await post('/bookings',booking())).status,400);await post('/admin/provider',{user_id:'pro',status:'approved'},'admin');assert.equal((await post('/bookings',booking())).status,400);await post('/provider/availability',{online:true},'pro');assert.equal((await post('/bookings',booking())).status,201)});
test('booking creation is idempotent, matching is scoped, and assignment is exclusive',async()=>{await setup();await approve();const input=booking(),created=await post('/bookings',input);assert.equal(created.status,201);assert.equal((await post('/bookings',input)).data.id,created.data.id);assert.equal((await call('/bookings?role=provider',{user:'pro'})).data.length,1);assert.equal((await call('/bookings/'+created.data.id,{user:'stranger'})).status,403);assert.equal((await post('/bookings/'+created.data.id+'/accept',{},'pro')).status,200);assert.equal((await post('/bookings/'+created.data.id+'/accept',{},'pro')).status,409);const history=(await call('/bookings/'+created.data.id)).data.history;assert.equal(history.length,2);assert.equal(history[1].status,'confirmed')});
test('rejection removes a request from that provider without cancelling the customer booking',async()=>{await setup();await approve();const id=(await post('/bookings',booking())).data.id;await post('/bookings/'+id+'/reject',{},'pro');assert.equal((await call('/bookings?role=provider',{user:'pro'})).data.length,0);assert.equal((await call('/bookings/'+id)).data.status,'requested');assert.equal((await post('/bookings/'+id+'/accept',{},'pro')).status,403)});
test('quotes require customer approval before work; messaging stays within the booking',async()=>{await setup();await approve();const id=(await post('/bookings',booking('painting'))).data.id;assert.equal((await post('/bookings/'+id+'/messages',{body:'Hello'},'pro')).status,403);assert.equal((await post('/bookings/'+id+'/accept',{},'pro')).status,400);const quote=await post('/bookings/'+id+'/quote',{labour:1500,materials:500,additional:0,terms:'One room, two coats, one day.'},'pro');assert.equal(quote.status,200);assert.equal((await post('/bookings/'+id+'/status',{status:'work_started'},'pro')).status,409);assert.equal((await post('/bookings/'+id+'/quote-response',{quote_id:quote.data.id,accept:true},'pro')).status,403);assert.equal((await post('/bookings/'+id+'/quote-response',{quote_id:quote.data.id,accept:true})).status,200);const b=(await call('/bookings/'+id)).data;assert.equal(b.estimated_price,2000);assert.equal(b.status,'confirmed');assert.equal((await post('/bookings/'+id+'/messages',{body:'Thank you'})).status,200);assert.equal((await call('/bookings/'+id+'/messages',{user:'stranger'})).status,403);assert.equal((await call('/bookings/'+id+'/messages',{user:'pro'})).data.length,1)});
test('only completed, owned bookings can produce one verified review',async()=>{await setup();await approve();const id=(await post('/bookings',booking())).data.id;assert.equal((await post('/bookings/'+id+'/review',{rating:5,body:'Good work'})).status,403);await post('/bookings/'+id+'/accept',{},'pro');for(const status of ['on_the_way','arrived','work_started','work_completed'])assert.equal((await post('/bookings/'+id+'/status',{status},'pro')).status,200);assert.equal((await post('/bookings/'+id+'/review',{rating:5,body:'Good work'})).status,200);assert.equal((await post('/bookings/'+id+'/review',{rating:5,body:'Again'})).status,400);assert.equal((await call('/providers')).data[0].review_count,1)});
test('payments cannot be marked successful by browser or unsigned webhooks',async()=>{await setup();assert.equal((await post('/payments/order',{booking_id:'invalid'})).status,503);env.RAZORPAY_WEBHOOK_SECRET='test-webhook-secret';const bad=await call('/payments/webhook',{user:null,body:{event:'payment.captured'},extraHeaders:{'x-razorpay-signature':'0'.repeat(64)}});assert.equal(bad.status,403)});
test('cross-origin writes and invalid addresses are rejected',async()=>{await setup();assert.equal((await call('/profile',{body:{name:'Name',phone:'+919876543210'},extraHeaders:{origin:'https://evil.test'}})).status,403);await post('/addresses',{label:'Home',address:'Test address',location:'Pattambi'});assert.deepEqual((await call('/addresses',{user:'stranger'})).data,[]);assert.equal((await post('/addresses',{id:(await call('/addresses')).data[0].id,label:'Other',address:'Other home',location:'Pattambi'},'stranger')).status,404)});
