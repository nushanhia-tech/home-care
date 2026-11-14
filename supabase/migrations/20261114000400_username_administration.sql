-- Username/password login uses Supabase Auth. Only trusted server credentials can manage login mappings.
alter table public.users add column if not exists username text;
alter table public.users add column if not exists is_active boolean not null default true;
create unique index users_username on public.users(lower(username)) where username is not null;
create table private.login_accounts (
 username text primary key check(username=lower(username) and username ~ '^[a-z0-9][a-z0-9_.-]{2,31}$'),
 user_id uuid not null unique references auth.users(id) on delete cascade,
 must_change_password boolean not null default false
);
create table private.initial_admin_bootstrap (singleton boolean primary key default true check(singleton),completed boolean not null default false);
insert into private.initial_admin_bootstrap(singleton) values(true) on conflict do nothing;
create table private.auth_attempts (bucket text primary key,attempts integer not null default 0,expires_at timestamptz not null);
create table public.website_configuration (
 id boolean primary key default true check(id),
 content jsonb not null default '{"site_name":"Local Mate","hero_line_1":"Your home.","hero_line_2":"Our people.","hero_line_3":"Consider it done.","hero_description":"From a leaky tap to a fresh coat of paint. Find a trusted helping hand, close to home.","tagline":"Your neighbourhood. Your trusted helpers.","announcement":"A little help, right around the corner.","contact_phone":"","contact_address":"Pattambi, Kerala, India"}',
 maintenance_mode boolean not null default false,customer_portal_enabled boolean not null default true,
 provider_portal_enabled boolean not null default true,registration_enabled boolean not null default true,
 bookings_enabled boolean not null default true,updated_at timestamptz not null default now()
);
insert into public.website_configuration(id) values(true) on conflict do nothing;
alter table public.website_configuration enable row level security;
create policy website_configuration_read on public.website_configuration for select using(true);
revoke all on public.website_configuration from anon,authenticated;
grant select on public.website_configuration to anon,authenticated;

create function public.account_active() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.users where id=auth.uid() and is_active)
$$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.users u join private.admin_emails a on a.email=lower(u.email)
 join public.users profile on profile.id=u.id
 where u.id=auth.uid() and u.email_confirmed_at is not null and profile.is_active
 and not exists(select 1 from private.login_accounts l where l.user_id=u.id and l.must_change_password))
$$;
create or replace function private.take_rate_limit() returns void language plpgsql security definer set search_path='' as $$
declare count_now integer;minute_now bigint:=floor(extract(epoch from now())/60);
begin
 if auth.uid() is null or not public.account_active() then raise exception 'Your account is unavailable.' using errcode='42501';end if;
 insert into private.request_windows(user_id,window_start,hits) values(auth.uid(),minute_now,1)
 on conflict(user_id,window_start) do update set hits=private.request_windows.hits+1 where private.request_windows.hits<60 returning hits into count_now;
 if count_now is null then raise exception 'Too many updates. Please try again in a minute.';end if;
end $$;
create function public.login_state() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('username',username,'must_change_password',must_change_password) from private.login_accounts where user_id=auth.uid()
$$;
create function public.service_auth_attempt(p_key text,p_action text) returns void language plpgsql security definer set search_path='' as $$
declare hits integer;bucket_key text;seconds integer;maximum integer;
begin
 if auth.role()<>'service_role' then raise exception 'Server authorization required.' using errcode='42501';end if;
 seconds:=case when p_action='signup' then 3600 else 60 end;maximum:=case when p_action='signup' then 5 else 12 end;
 bucket_key:=p_action||':'||p_key||':'||floor(extract(epoch from now())/seconds)::text;
 insert into private.auth_attempts(bucket,attempts,expires_at) values(bucket_key,1,now()+make_interval(secs=>seconds))
 on conflict(bucket) do update set attempts=private.auth_attempts.attempts+1 where private.auth_attempts.attempts<maximum returning attempts into hits;
 if hits is null then raise exception 'Too many sign-in attempts. Please wait and try again.';end if;
 delete from private.auth_attempts where expires_at<now()-interval '1 day';
end $$;
create function public.service_resolve_username(p_username text) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role()<>'service_role' then raise exception 'Server authorization required.' using errcode='42501';end if;
 return (select jsonb_build_object('user_id',u.id,'email',u.email,'must_change_password',l.must_change_password,'is_active',p.is_active)
 from private.login_accounts l join auth.users u on u.id=l.user_id join public.users p on p.id=u.id where l.username=lower(p_username));
end $$;
create function public.service_bootstrap_state() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role()<>'service_role' then raise exception 'Server authorization required.' using errcode='42501';end if;
 return jsonb_build_object('completed',(select completed from private.initial_admin_bootstrap where singleton),
 'candidate_id',(select id from auth.users where email='admin@localmate.invalid' and raw_app_meta_data->>'local_mate_bootstrap'='true'));
end $$;
create function public.service_finish_bootstrap(p_user uuid) returns void language plpgsql security definer set search_path='' as $$
declare done boolean;
begin
 if auth.role()<>'service_role' then raise exception 'Server authorization required.' using errcode='42501';end if;
 select completed into done from private.initial_admin_bootstrap where singleton for update;
 if done then raise exception 'Administrator setup is already complete.';end if;
 if not exists(select 1 from auth.users where id=p_user and email='admin@localmate.invalid' and email_confirmed_at is not null and raw_app_meta_data->>'local_mate_bootstrap'='true') then raise exception 'Invalid administrator account.';end if;
 insert into private.login_accounts(username,user_id,must_change_password) values('admin',p_user,true);
 update public.users set username='admin',name='Administrator' where id=p_user;
 insert into private.admin_emails(email) values('admin@localmate.invalid') on conflict do nothing;
 update private.initial_admin_bootstrap set completed=true where singleton;
end $$;
create function public.service_set_login(p_user uuid,p_username text,p_change_password boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.role()<>'service_role' then raise exception 'Server authorization required.' using errcode='42501';end if;
 perform 1 from public.website_configuration where id for share;
 if not p_change_password and not exists(select 1 from private.login_accounts where user_id=p_user) and exists(select 1 from public.website_configuration where id and(maintenance_mode or not registration_enabled)) then raise exception 'Registration is temporarily paused.';end if;
 insert into private.login_accounts(username,user_id,must_change_password) values(lower(p_username),p_user,p_change_password)
 on conflict(user_id) do update set username=excluded.username,must_change_password=excluded.must_change_password;
 update public.users set username=lower(p_username) where id=p_user;
end $$;
create function public.admin_save_website(p_data jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 if coalesce(jsonb_typeof(p_data->'content'),'')<>'object' or length(p_data::text)>60000 then raise exception 'Invalid website settings.';end if;
 if exists(select 1 from jsonb_each(p_data->'content') field where jsonb_typeof(field.value)<>'string') then raise exception 'Website content fields must be text.';end if;
 update public.website_configuration set content=p_data->'content',maintenance_mode=coalesce((p_data->>'maintenance_mode')::boolean,false),
 customer_portal_enabled=coalesce((p_data->>'customer_portal_enabled')::boolean,true),provider_portal_enabled=coalesce((p_data->>'provider_portal_enabled')::boolean,true),
 registration_enabled=coalesce((p_data->>'registration_enabled')::boolean,true),bookings_enabled=coalesce((p_data->>'bookings_enabled')::boolean,true),updated_at=now() where id;
 perform private.audit('Update website and portal controls');
end $$;
create function public.admin_save_location(p_name text,p_active boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 if length(trim(p_name)) not between 1 and 100 then raise exception 'Enter a location name.';end if;
 insert into public.locations(name,active) values(trim(p_name),p_active) on conflict(name) do update set active=excluded.active;
 perform private.audit('Save location',p_name);
end $$;
create function public.admin_account_status(p_user uuid,p_active boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 if p_user=auth.uid() then raise exception 'Your current administrator account must stay active.';end if;
 update public.users set is_active=p_active where id=p_user;perform private.audit('Change account status',p_user::text);
end $$;
create function public.export_marketplace() returns jsonb language plpgsql security definer set search_path='' as $$
declare table_name text;data jsonb;all_data jsonb:='{}';
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 perform private.audit('Download application data backup');
 foreach table_name in array array['users','provider_profiles','locations','services','addresses','bookings','booking_status_history','booking_rejections','quotations','messages','notifications','reviews','payments','support_tickets','favourites','settings','website_configuration','admin_activity_logs'] loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb) from public.%I t',table_name) into data;
  all_data:=all_data||jsonb_build_object(table_name,data);
 end loop;
 return jsonb_build_object('format','local-mate-application-backup','version',1,'created_at',now(),'tables',all_data,
 'scope','Application records only. Auth passwords, sessions, uploaded files, and project secrets are not included.');
end $$;
create function public.service_reset_marketplace(p_actor uuid,p_confirmation text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.role()<>'service_role' or not exists(select 1 from auth.users u join private.admin_emails a on a.email=lower(u.email) join public.users p on p.id=u.id where u.id=p_actor and p.is_active and u.email_confirmed_at is not null and not exists(select 1 from private.login_accounts l where l.user_id=p_actor and l.must_change_password)) then raise exception 'Server administrator authorization required.' using errcode='42501';end if;
 if p_confirmation<>'DELETE ALL DATA' then raise exception 'Type DELETE ALL DATA to confirm.';end if;
 delete from public.reviews;delete from public.payments;delete from public.favourites;delete from public.messages;delete from public.notifications;
 delete from public.booking_status_history;delete from public.booking_rejections;delete from public.quotations;delete from public.support_tickets;
 delete from public.bookings;delete from public.addresses;delete from public.provider_profiles;delete from public.services;delete from public.locations;
 delete from public.settings;delete from public.admin_activity_logs;delete from public.website_configuration;
 delete from private.request_windows where user_id<>p_actor;
 insert into public.website_configuration(id,maintenance_mode,registration_enabled,customer_portal_enabled,provider_portal_enabled,bookings_enabled) values(true,true,false,false,false,false);
 insert into public.admin_activity_logs(actor_id,action) values(p_actor,'Delete all marketplace data');
end $$;
-- Server-only reset continuation, after reauthentication, reports account deletion progress without exposing a browser service key.
create function public.service_reset_progress(p_actor uuid,p_note text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.role()<>'service_role' then raise exception 'Server authorization required.' using errcode='42501';end if;
 insert into public.admin_activity_logs(actor_id,action,target_id) values(p_actor,'Account cleanup',p_note);
end $$;

-- Suspend access to private data for inactive accounts, including direct PostgREST requests.
do $$ declare table_name text;begin
 foreach table_name in array array['users','provider_profiles','addresses','bookings','booking_status_history','booking_rejections','quotations','messages','notifications','payments','support_tickets','favourites','settings','admin_activity_logs'] loop
  if not exists(select 1 from pg_policies where schemaname='public' and tablename=table_name and policyname='active_account_required') then
   execute format('create policy active_account_required on public.%I as restrictive for all to authenticated using(public.account_active()) with check(public.account_active())',table_name);
  end if;
 end loop;
end $$;

-- Enforce website booking and provider-registration switches inside database workflows too.
create function private.enforce_portal_switches() returns trigger language plpgsql security definer set search_path='' as $$
declare cfg public.website_configuration;
begin
 select * into cfg from public.website_configuration where id;
 if public.is_admin() then return new;end if;
 if cfg.maintenance_mode then raise exception 'The website is temporarily paused.';end if;
 if tg_table_name='bookings' and (not cfg.customer_portal_enabled or not cfg.bookings_enabled) then raise exception 'New bookings are temporarily paused.';end if;
 if tg_table_name='provider_profiles' and not cfg.provider_portal_enabled then raise exception 'Provider registration is temporarily paused.';end if;
 return new;
end $$;
do $$ begin
 if not exists(select 1 from pg_trigger where tgname='enforce_booking_switches' and tgrelid='public.bookings'::regclass) then
  create trigger enforce_booking_switches before insert on public.bookings for each row execute function private.enforce_portal_switches();
 end if;
 if not exists(select 1 from pg_trigger where tgname='enforce_provider_switches' and tgrelid='public.provider_profiles'::regclass) then
  create trigger enforce_provider_switches before insert on public.provider_profiles for each row execute function private.enforce_portal_switches();
 end if;
end $$;
revoke execute on function public.account_active(),public.login_state() from public,anon;
grant execute on function public.account_active(),public.login_state() to authenticated;
revoke execute on function public.service_auth_attempt(text,text),public.service_resolve_username(text),public.service_bootstrap_state(),public.service_finish_bootstrap(uuid),public.service_set_login(uuid,text,boolean),public.service_reset_progress(uuid,text) from public,anon,authenticated;
grant execute on function public.service_auth_attempt(text,text),public.service_resolve_username(text),public.service_bootstrap_state(),public.service_finish_bootstrap(uuid),public.service_set_login(uuid,text,boolean),public.service_reset_progress(uuid,text) to service_role;
revoke execute on function public.admin_save_website(jsonb),public.admin_save_location(text,boolean),public.admin_account_status(uuid,boolean),public.export_marketplace() from public,anon;
grant execute on function public.admin_save_website(jsonb),public.admin_save_location(text,boolean),public.admin_account_status(uuid,boolean),public.export_marketplace() to authenticated;
revoke execute on function private.enforce_portal_switches() from public,anon,authenticated;
create or replace function public.provider_eligible(p_provider uuid,p_service text,p_location text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.provider_profiles p join public.users u on u.id=p.user_id cross join public.website_configuration c
 where c.id and not c.maintenance_mode and c.provider_portal_enabled and u.is_active and p.user_id=p_provider and p.status='approved' and p.online and p_service=any(p.service_ids) and p_location=any(p.locations))
$$;
create function private.enforce_job_switches() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.provider_id=auth.uid() and not public.is_admin() and exists(select 1 from public.website_configuration where id and(maintenance_mode or not provider_portal_enabled)) then
  raise exception 'Provider jobs are temporarily paused.';
 end if;
 return new;
end $$;
do $$ begin
 if not exists(select 1 from pg_trigger where tgname='enforce_job_switches' and tgrelid='public.bookings'::regclass) then
  create trigger enforce_job_switches before update on public.bookings for each row execute function private.enforce_job_switches();
 end if;
end $$;
revoke execute on function private.enforce_job_switches() from public,anon,authenticated;

revoke execute on function public.service_reset_marketplace(uuid,text) from public,anon,authenticated;
grant execute on function public.service_reset_marketplace(uuid,text) to service_role;

notify pgrst, 'reload schema';
