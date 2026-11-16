import pg from 'pg';
import {readFile,readdir} from 'node:fs/promises';
import {createHmac} from 'node:crypto';
export const JWT_SECRET='local_mate_test_jwt_secret_at_least_32_characters';
export const OTP_SECRET='local_mate_otp_test_key_at_least_32_characters';
export const ids={admin:'30000000-0000-4000-8000-000000000001',customer:'30000000-0000-4000-8000-000000000002',p1:'30000000-0000-4000-8000-000000000011',p2:'30000000-0000-4000-8000-000000000012',p3:'30000000-0000-4000-8000-000000000013',p4:'30000000-0000-4000-8000-000000000014',p5:'30000000-0000-4000-8000-000000000015',other:'30000000-0000-4000-8000-000000000099'};
export function jwt(who){const payload={role:who==='service'?'service_role':who?'authenticated':'anon',...(ids[who]?{sub:ids[who],email:who+'@qa.example'}:{}),exp:Math.floor(Date.now()/1000)+7200,iat:Math.floor(Date.now()/1000),aud:'authenticated'};const head=Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url'),body=Buffer.from(JSON.stringify(payload)).toString('base64url');return head+'.'+body+'.'+createHmac('sha256',JWT_SECRET).update(head+'.'+body).digest('base64url');}
export async function bootstrap(){
 const admin=new pg.Client({connectionString:'postgres://postgres:local_test_only@127.0.0.1:15432/postgres'});await admin.connect();await admin.query('DROP DATABASE IF EXISTS localmate_test WITH (FORCE)');await admin.query('CREATE DATABASE localmate_test');await admin.end();
 const pool=new pg.Pool({connectionString:'postgres://postgres:local_test_only@127.0.0.1:15432/localmate_test',max:12});
 await pool.query(`do $$begin if not exists(select 1 from pg_roles where rolname='anon') then create role anon;end if;if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated;end if;if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role bypassrls;end if;end$$;
 create schema auth;grant usage on schema auth,public to anon,authenticated,service_role;
 create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',email_confirmed_at timestamptz default now());
 create function auth.uid() returns uuid language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claim.sub',true),''),nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid$$;
 create function auth.role() returns text language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claim.role',true),''),nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role')$$;
 `);
 const dir=new URL('../../supabase/migrations/',import.meta.url);for(const name of(await readdir(dir)).filter(n=>n.endsWith('.sql')).sort()){try{await pool.query(await readFile(new URL(name,dir),'utf8'))}catch(e){throw new Error(name+': '+e.message)}}
 await pool.query(await readFile(new URL('../../supabase/seed.sql',import.meta.url),'utf8'));
 await pool.query("insert into private.admin_emails(email) values('admin@qa.example') on conflict do nothing");
 for(const [who,id]of Object.entries(ids)){await pool.query('insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)',[id,who+'@qa.example',{full_name:who==='customer'?'Test Customer':who==='admin'?'Test Administrator':'Test Provider '+who}]);await call(pool,who,'update_profile',['Test '+who,'+91'+(who==='customer'?'9876543210':'98765432'+String(Object.keys(ids).indexOf(who)).padStart(2,'0'))]);}
 for(const who of ['p1','p2','p3','p4','p5']){
  await call(pool,'admin','save_provider',[{name:'Test Provider '+who,phone:'+9198765432'+who.slice(1).padStart(2,'0'),business_name:'Test Company '+who,category:'Home care',description:'Test-only qualified provider.',experience:5,locations:['Pattambi'],offerings:[{service_id:'plumbing',price:1100,pricing_unit:'visit'},{service_id:'painting',price:null,pricing_unit:'quote'}],status:'approved',online:true,publish_phone:false},ids[who]]);
  await call(pool,who,'set_availability',[true,{max_daily:30}]);
 }
 await call(pool,'admin','admin_operations_config',[{payment_instructions:'Test-only business bank details',commission_percent:10,grace_hours:0,deadline_days:0}]);
 return pool;
}
export async function call(pool,who,name,args=[]){const client=await pool.connect();try{await client.query('BEGIN');const role=who==='service'?'service_role':who?'authenticated':'anon';await client.query('SET LOCAL ROLE '+role);await client.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role',$2,true),set_config('request.jwt.claims',$3,true)",[ids[who]||'',role,JSON.stringify({sub:ids[who]||null,role})]);const result=await client.query(`select public.${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) result`,args);await client.query('COMMIT');return result.rows.map(r=>r.result)}catch(e){await client.query('ROLLBACK');throw e}finally{client.release()}}
export async function scalar(pool,who,name,args=[]){return(await call(pool,who,name,args))[0]}
export const booking=extra=>({service_id:'plumbing',location:'Pattambi',address:'Test house, Pattambi, PIN 679303',scheduled_at:new Date(Date.now()+86400000).toISOString(),description:'Test-only job description.',payment_method:'cash',idempotency_key:crypto.randomUUID(),...extra});
