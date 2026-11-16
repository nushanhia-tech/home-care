import {bootstrap,scalar,call,booking,ids,OTP_SECRET} from './helpers/operations-db.mjs';
import {makeOTP,decryptOTP,otpHash} from '../lib/operations/crypto.mjs';
import assert from 'node:assert/strict';
const pool=await bootstrap();const check=[];
try{
 const id=await scalar(pool,'customer','create_booking',[booking()]);
 assert.equal((await pool.query('select * from public.booking_provider_offers where booking_id=$1',[id])).rowCount,5);
 for(const who of ['p1','p2','p3','p4','p5'])assert.ok((await call(pool,who,'list_bookings',['provider'])).some(b=>b.id===id));check.push('all five eligible providers receive one request');
 const results=await Promise.all(['p3','p2'].map(who=>scalar(pool,who,'accept_booking',[id])));assert.equal(results.filter(x=>x.ok).length,1);const winner=results[0].ok?'p3':'p2';
 assert.equal((await pool.query('select * from public.booking_assignments where booking_id=$1',[id])).rowCount,1);check.push('real concurrent PostgreSQL acceptance assigns exactly once');
 const safe=await scalar(pool,winner,'booking_detail',[id]);assert.ok(!JSON.stringify(safe).includes('987654'));assert.ok(!JSON.stringify(await scalar(pool,'customer','booking_contacts',[id])).includes('phone'));check.push('booking and contact responses exclude counterparty phone numbers');
 await assert.rejects(scalar(pool,winner,'booking_action',[id,'status',{status:'work_started'}]),/OTP/);
 await scalar(pool,winner,'booking_action',[id,'status',{status:'on_the_way'}]);await scalar(pool,winner,'booking_action',[id,'status',{status:'arrived'}]);
 const otp=makeOTP(id,OTP_SECRET);await scalar(pool,'service','service_issue_job_otp',[ids[winner],id,otp.hash,otp.cipher]);
 await assert.rejects(scalar(pool,winner,'service_customer_job_otp',[ids.customer,id]),/permission denied|authorization/);
 let value=await scalar(pool,'service','service_verify_job_otp',[ids[winner],id,'wrong']);assert.equal(value.ok,false);
 const code=decryptOTP(otp.cipher,OTP_SECRET);value=await scalar(pool,'service','service_verify_job_otp',[ids[winner],id,otpHash(code,id,OTP_SECRET)]);assert.equal(value.ok,true);check.push('OTP cannot be bypassed, incorrect attempts persist, correct OTP starts work');
 const charge=await scalar(pool,winner,'request_additional_charge',[id,10000,'Approved extra work']);await scalar(pool,'customer','respond_additional_charge',[charge,'approved']);
 const bill=await scalar(pool,winner,'submit_final_bill',[id,{labour_paise:80000,materials_paise:30000,discount_paise:0,additional_paise:999999,description:'Actual completed test-only work'}]);
 assert.equal((await pool.query('select total_paise from public.job_bills where id=$1',[bill])).rows[0].total_paise,'120000');
 const invoice=await scalar(pool,'customer','respond_final_bill',[bill,'confirm','']);assert.ok(invoice.invoice_id);await scalar(pool,'customer','respond_final_bill',[bill,'confirm','']);assert.equal((await pool.query('select * from public.invoices where bill_id=$1',[bill])).rowCount,1);check.push('approved extras only, exact INR 1200 total, one actual invoice');
 const dashboard=await scalar(pool,winner,'commission_dashboard');assert.equal(dashboard.statements[0].commission_paise,12000);check.push('confirmed bill accrues commission exactly once');

 // Isolate the INR 10,000 / 10% commission case on another provider.
 await scalar(pool,'admin','admin_service_provider',[ids.p4,'plumbing',true,10000,'visit']);
 const second=await scalar(pool,'customer','create_booking',[booking()]);await scalar(pool,'p4','accept_booking',[second]);
 for(const status of ['on_the_way','arrived'])await scalar(pool,'p4','booking_action',[second,'status',{status}]);
 const startCode=makeOTP(second,OTP_SECRET);await scalar(pool,'service','service_issue_job_otp',[ids.p4,second,startCode.hash,startCode.cipher]);
 await scalar(pool,'service','service_verify_job_otp',[ids.p4,second,startCode.hash]);
 const secondBill=await scalar(pool,'p4','submit_final_bill',[second,{labour_paise:1000000,materials_paise:0,discount_paise:0,description:'Completed actual test service'}]);await scalar(pool,'customer','respond_final_bill',[secondBill,'confirm','']);
 const statement=(await scalar(pool,'p4','commission_dashboard')).statements[0];assert.equal(statement.commission_paise,100000);check.push('INR 10000 at 10 percent produces exactly INR 1000');
 const proof=await scalar(pool,'service','service_register_media',[ids.p4,{kind:'commission',object_path:ids.p4+'/test-proof.jpg',byte_size:100}]);
 const payment=await scalar(pool,'p4','submit_commission_payment',[{period_id:statement.period_id,amount_paise:100000,method:'bank_transfer',reference:'TEST-bank-ref-first',paid_at:new Date().toISOString(),proof_id:proof}]);
 assert.equal((await pool.query('select status from public.provider_commission_payments where id=$1',[payment])).rows[0].status,'awaiting_verification');check.push('payment proof never auto-approves commission');
 await scalar(pool,'admin','admin_review_commission',[payment,false,'The actual bank credit could not be verified']);
 const retry=await scalar(pool,'p4','submit_commission_payment',[{period_id:statement.period_id,amount_paise:100000,method:'bank_transfer',reference:'TEST-bank-ref-valid',paid_at:new Date().toISOString(),proof_id:proof}]);
 // Set only the test financial period's deadline in the past.
 await pool.query("update public.weekly_commission_periods set deadline_at=now()-interval '2 hours',grace_until=now()-interval '1 hour' where id=$1",[statement.period_id]);
 await scalar(pool,'service','service_maintenance');assert.equal(await scalar(pool,'p4','provider_eligible',[ids.p4,'plumbing','Pattambi']),false);check.push('earned unpaid overdue commission restricts only new jobs');
 const noJobs=await scalar(pool,'p5','commission_dashboard');assert.deepEqual(noJobs.statements,[]);assert.equal(noJobs.current_commission_blocked,false);assert.equal(await scalar(pool,'p5','provider_eligible',[ids.p5,'plumbing','Pattambi']),true);check.push('zero-job provider owes zero and stays eligible');
 await scalar(pool,'admin','admin_review_commission',[retry,true,'Verified actual bank credit in the test ledger']);
 assert.equal((await scalar(pool,'p4','commission_dashboard')).statements[0].status,'paid');assert.equal(await scalar(pool,'p4','provider_eligible',[ids.p4,'plumbing','Pattambi']),true);check.push('admin verification marks paid and clears only the commission restriction');
 // A genuine unresolved customer dispute holds commission and removes its restriction.
 await scalar(pool,'customer','respond_final_bill',[bill,'dispute','Customer disputes the previously approved extra amount']);
 await scalar(pool,'service','service_maintenance');assert.equal((await scalar(pool,winner,'commission_dashboard')).current_commission_blocked,false);check.push('legitimate disputed commission is held and cannot suspend eligibility');
 await assert.rejects(scalar(pool,'other','booking_detail',[id]),/unavailable|access/);await assert.rejects(scalar(pool,'p5','conversation_messages',[id]),/conversation/);check.push('unrelated users cannot access booking data or messages');
 // Quote rejection reopens the same request without a stale assignment.
 const quoted=await scalar(pool,'customer','create_booking',[booking({service_id:'painting'})]);
 await scalar(pool,'p5','accept_booking',[quoted]);
 const quote=await scalar(pool,'p5','booking_action',[quoted,'quote',{labour:700,materials:100,additional:0,terms:'Actual painting scope for the test.'}]);
 await scalar(pool,'customer','booking_action',[quoted,'quote-response',{quote_id:quote.id,accept:false}]);
 assert.equal((await pool.query('select * from public.booking_assignments where booking_id=$1',[quoted])).rowCount,0);
 assert.equal((await scalar(pool,'p1','accept_booking',[quoted])).ok,true);check.push('declined quote reopens broadcast and allows exactly one fresh assignment');
 // Refund verification can only reflect real paid funds and holds commission.
 await scalar(pool,'admin','admin_verify_cash',[second,1000000,'TEST-verified-cash-payment']);
 await assert.rejects(scalar(pool,'other','admin_verify_refund',[second,100,'TEST-no-access','Actual refund reason']),/Administrator/);
 await assert.rejects(scalar(pool,'admin','admin_verify_refund',[second,1000001,'TEST-too-large','Actual refund reason']),/actual paid/);
 await scalar(pool,'admin','admin_verify_refund',[second,1000000,'TEST-actual-full-refund','Actual cash refund reconciled for this test']);
 assert.equal((await scalar(pool,'customer','booking_detail',[second])).payment_status,'refunded');
 assert.equal((await pool.query('select status from public.provider_commissions where booking_id=$1',[second])).rows[0].status,'held');check.push('verified refunds are bounded by actual payment and hold commission');
 // Exercise the destructive reset only inside a rolled-back local test transaction.
 const resetClient=await pool.connect();
 try {
  await resetClient.query('BEGIN');await resetClient.query('SET LOCAL ROLE service_role');
  await resetClient.query("select set_config('request.jwt.claim.role','service_role',true)");
  await resetClient.query("select public.service_reset_marketplace($1,'DELETE ALL DATA')",[ids.admin]);
  await resetClient.query('RESET ROLE');
  assert.equal((await resetClient.query('select count(*)::int n from public.bookings')).rows[0].n,0);
  assert.equal((await resetClient.query('select is_active from public.users where id=$1',[ids.admin])).rows[0].is_active,true);
  check.push('full financial-data reset preserves administrator and runs transactionally');
 }finally{await resetClient.query('ROLLBACK');resetClient.release()}
 // Prepare an accepted live booking for the actual HTTP/WebRTC browser test.
 const live=await scalar(pool,'customer','create_booking',[booking()]);await scalar(pool,'p1','accept_booking',[live]);
 await scalar(pool,'admin','admin_operations_config',[{calling_enabled:true,relay_only:false}]);
 const unanswered=await scalar(pool,'customer','start_voice_call',[live]);
 await pool.query("update public.voice_calls set created_at=now()-interval '2 minutes' where id=$1",[unanswered.id]);
 assert.equal((await scalar(pool,'p1','voice_call_state',[unanswered.id])).status,'missed');
 assert.ok((await call(pool,'p1','safe_notifications')).some(n=>n.booking_id===live));check.push('unanswered calls expire as missed with persisted metadata/notification');
 await pool.query("notify pgrst,'reload schema'");
 console.log(JSON.stringify({passed:check,live_booking:live,live_provider:ids.p1},null,2));
}catch(e){console.error('FAILED AFTER',check,e);process.exitCode=1}finally{await pool.end()}
