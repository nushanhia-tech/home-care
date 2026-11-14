import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
const admin='mueenptb@gmail.com';
const account='10000000-0000-4000-8000-000000000001';
async function bootstrap(db){
 await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;grant usage on schema auth,public to anon,authenticated,service_role;
 create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',email_confirmed_at timestamptz default now());
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.role() returns text language sql stable as $$select current_setting('request.jwt.claim.role',true)$$;
 create publication supabase_realtime;`);
}
async function run(db,sql){try{return await db.exec(sql)}catch(error){throw new Error(error.message)}}
test('single-file Supabase setup installs fresh, backfills accounts, and can rerun without losing data',async()=>{
 const db=new PGlite();
 try{
  await bootstrap(db);
  await db.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,null)',[account,admin]);
  const setup=await readFile(new URL('../supabase/setup.sql',import.meta.url),'utf8');
  await run(db,setup);
  assert.equal((await db.query('select count(*) n from public.services')).rows[0].n,18);
  assert.equal((await db.query('select count(*) n from public.locations')).rows[0].n,6);
  assert.equal((await db.query('select count(*) n from public.provider_profiles')).rows[0].n,0);
  assert.equal((await db.query('select email from public.users where id=$1',[account])).rows[0].email,admin);
  assert.equal((await db.query('select email from private.admin_emails')).rows[0].email,admin);
  const administrator=()=>db.transaction(async tx=>{await tx.exec('set local role authenticated');await tx.query("select set_config('request.jwt.claim.sub',$1,true)",[account]);return (await tx.query('select public.is_admin() allowed')).rows[0].allowed});
  assert.equal(await administrator(),false,'Unconfirmed email must not grant administrator access.');
  await db.query('update auth.users set email_confirmed_at=now() where id=$1',[account]);
  assert.equal(await administrator(),true,'Confirmed designated email grants administrator access.');
  await db.query("update public.services set price=350 where id='plumbing'");
  await run(db,setup);
  assert.equal((await db.query("select price from public.services where id='plumbing'")).rows[0].price,350);
  assert.equal((await db.query('select count(*) n from private.admin_emails')).rows[0].n,1);
  assert.equal((await db.query("select count(*) n from pg_publication_tables where pubname='supabase_realtime'")).rows[0].n,2);
  assert.equal((await db.query("select count(*) n from pg_trigger where tgname='on_auth_user_created'")).rows[0].n,1);
 }finally{await db.close()}
});
test('single-file setup also works after the individual database scripts were applied',async()=>{
 const db=new PGlite();
 try{
  await bootstrap(db);
  const directory=new URL('../supabase/migrations/',import.meta.url);
  for(const name of (await readdir(directory)).filter(n=>n.endsWith('.sql')).sort())await run(db,await readFile(new URL(name,directory),'utf8'));
  await run(db,await readFile(new URL('../supabase/seed.sql',import.meta.url),'utf8'));
  await db.exec("update public.services set price=850 where id='cleaning'");
  await run(db,await readFile(new URL('../supabase/setup.sql',import.meta.url),'utf8'));
  assert.equal((await db.query("select price from public.services where id='cleaning'")).rows[0].price,850);
  assert.equal((await db.query('select count(*) n from private.admin_emails')).rows[0].n,1);
  assert.equal((await db.query('select email from private.admin_emails')).rows[0].email,admin);
 }finally{await db.close()}
});
