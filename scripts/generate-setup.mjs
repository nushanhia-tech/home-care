import {readFile,readdir,writeFile} from 'node:fs/promises';
const root=new URL('../',import.meta.url);
const names=(await readdir(new URL('supabase/migrations/',root))).filter(n=>n.endsWith('.sql')).sort();
let schema='';
for(const name of names){schema+='\n-- Migration: '+name+'\n'+await readFile(new URL('supabase/migrations/'+name,root),'utf8');}
schema=schema
 .replace(/\bcreate table (?!if not exists)/g,'create table if not exists ')
 .replace(/\bcreate unique index (?!if not exists)/g,'create unique index if not exists ')
 .replace(/\bcreate index (?!if not exists)/g,'create index if not exists ')
 .replace(/\bcreate function /g,'create or replace function ')
 .replace(/\bcreate view /g,'create or replace view ')
 .replace(/^create trigger on_auth_user_created[^\n]+;$/m,statement=>`do $setup_trigger$ begin
 if not exists(select 1 from pg_trigger where tgrelid='auth.users'::regclass and tgname='on_auth_user_created') then
  ${statement}
 end if;
end $setup_trigger$;`)
 .replace(/^create policy (\w+) on public\.(\w+)[^\n]+;$/gm,(statement,name,table)=>`do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='${table}' and policyname='${name}') then
  ${statement}
 end if;
end $setup_policy$;`)
 .replace(/do \$\$ begin\n if exists\(select 1 from pg_publication[\s\S]*?end \$\$;/,`do $setup_realtime$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='messages') then
   alter publication supabase_realtime add table public.messages;
  end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='notifications') then
   alter publication supabase_realtime add table public.notifications;
  end if;
 end if;
end $setup_realtime$;`);
const seed=await readFile(new URL('supabase/seed.sql',root),'utf8');
const output=`-- LOCAL MATE: COMPLETE SUPABASE SQL EDITOR SETUP
-- Generated from the checked-in migrations and starter catalogue.
-- Run this entire file in Supabase Dashboard > SQL Editor as the project owner.
-- Replace YOUR_ADMIN_EMAIL below with your confirmed administrator email first.
-- Can be rerun for this schema; preserves existing accounts, bookings and service edits.
-- This configures the database only. Add environment variables and Auth callback URLs separately.
-- Use SQL Editor setup OR Supabase CLI migrations. See README before mixing the two workflows.

begin;
select pg_advisory_xact_lock(hashtext('local_mate_database_setup'));
set local app.local_mate_admin_email = 'YOUR_ADMIN_EMAIL';
${schema}

-- Initial supported towns and editable services. Existing catalogue edits are preserved.
${seed}

-- Backfill accounts created before the Local Mate auth trigger was installed.
insert into public.users(id,email,name)
 select id,email,coalesce(nullif(raw_user_meta_data->>'full_name',''),split_part(email,'@',1))
 from auth.users where email is not null
 on conflict(id) do update set email=excluded.email;

-- Administrator membership is private and still requires a confirmed account email.
do $setup_admin$
declare admin_email text := lower(trim(current_setting('app.local_mate_admin_email',true)));
begin
 if admin_email is not null and admin_email not in ('','your_admin_email') then
  if admin_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
   raise exception 'Replace YOUR_ADMIN_EMAIL with a valid administrator email address.';
  end if;
  insert into private.admin_emails(email) values(admin_email) on conflict do nothing;
 end if;
end $setup_admin$;
commit;

select 'Local Mate database setup completed' as result,
 (select count(*) from public.services) as services,
 (select count(*) from public.locations) as locations,
 (select count(*) from private.admin_emails) as administrator_emails;
`;
if(process.argv.includes('--check')){
 const current=await readFile(new URL('supabase/setup.sql',root),'utf8');
 if(current!==output)throw new Error('supabase/setup.sql is stale. Run npm run db:setup:generate.');
 console.log('supabase/setup.sql matches the current migrations.');
}else{
 await writeFile(new URL('supabase/setup.sql',root),output);
 console.log('Generated supabase/setup.sql');
}
