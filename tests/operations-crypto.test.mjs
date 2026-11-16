import {test} from 'node:test';import assert from 'node:assert/strict';import {createHmac} from 'node:crypto';
import {makeOTP,decryptOTP,otpHash,iceConfiguration} from '../lib/operations/crypto.mjs';
import {toPaise} from '../lib/operations/money.mjs';
const secret='test_only_otp_key_longer_than_32_characters';
test('job OTP ciphertext is authenticated and its HMAC is tied to the booking',()=>{const value=makeOTP('booking-one',secret),code=decryptOTP(value.cipher,secret);assert.match(code,/^\d{6}$/);assert.equal(otpHash(code,'booking-one',secret),value.hash);assert.notEqual(otpHash(code,'booking-two',secret),value.hash);assert.throws(()=>decryptOTP(value.cipher,secret+'wrong'));assert.throws(()=>makeOTP('booking-one','short'));});
test('Coturn credentials are temporary HMAC credentials and never include the shared secret',()=>{const cfg=iceConfiguration({TURN_URLS:'turn:relay.example:3478?transport=udp,turns:relay.example:5349?transport=tcp',TURN_SHARED_SECRET:secret},'user-one',{relay_only:true,call_max_seconds:3600},1000000);assert.equal(cfg.iceTransportPolicy,'relay');const turn=cfg.iceServers.find(s=>s.username);assert.equal(turn.username,'4900:user-one');assert.equal(turn.credential,createHmac('sha1',secret).update(turn.username).digest('base64'));assert.ok(!JSON.stringify(cfg).includes(secret));assert.throws(()=>iceConfiguration({},'user',{relay_only:true}),/TURN/);});
test('billing converts exact INR decimals to paise without trusting floating-point totals',()=>{assert.equal(toPaise('10000'),1000000);assert.equal(toPaise('1.01'),101);assert.equal(toPaise('0.10'),10);for(const input of ['-1','1.001','1e3','NaN','Infinity','',100000001])assert.throws(()=>toPaise(input));});

import {execFileSync} from 'node:child_process';
test('invoice PDF supports Malayalam shaping alongside Latin text',()=>{
 const output=execFileSync(process.execPath,['--experimental-strip-types','--input-type=module','-e',`
 import {invoicePDF} from './lib/operations/pdf.ts';
 const bytes=await invoicePDF({number:'LOCAL-UNICODE-TEST',issued_at:new Date().toISOString(),status:'issued',payment_status:'pending',snapshot:{platform_name:'LOCAL MATE',booking_id:'test-only',customer_name:'മുഈൻ Customer',customer_address:'പട്ടാമ്പി',provider_name:'നമ്മുടെ കമ്പനി',provider_locations:['പട്ടാമ്പി'],service_name:'വീട്ടുജോലി Service',description:'ടെസ്റ്റ് ജോലി',total_paise:120000,payment_method:'cash',terms:'Test invoice only.'},items:[{label:'Labour',amount_paise:120000}]});
 if(bytes.subarray(0,5).toString()!=='%PDF-'||bytes.length<2000)throw new Error('Invalid PDF');
 console.log('valid multilingual PDF');
 `],{cwd:new URL('..',import.meta.url),encoding:'utf8'});
 assert.match(output,/valid multilingual PDF/);
});
