-- Operational policy, auditable distribution, privacy-safe reads and private media.
create table if not exists public.operations_configuration(id boolean primary key default true check(id),config jsonb not null default '{}',updated_at timestamptz not null default now());
insert into public.operations_configuration(id,config) values(true,'{
 "request_timeout_minutes":60,"request_expiry_mode":"pending","otp_ttl_seconds":300,"otp_max_attempts":5,
 "calling_enabled":true,"call_statuses":["confirmed","on_the_way","arrived","work_started","work_paused"],"ring_seconds":45,"call_max_seconds":3600,"call_heartbeat_seconds":45,"relay_only":false,
 "commission_enabled":true,"commission_percent":10,"commission_fixed_paise":0,"week_start_day":1,"timezone":"Asia/Kolkata","deadline_days":3,"grace_hours":48,"minimum_commission_paise":0,"auto_suspend":true,"auto_reactivate":true,
 "payment_ready_at":null,"payment_instructions":"","payment_methods":["bank_transfer","upi"],"tax_enabled":false,"tax_percent":0,"supplier_name":"","supplier_address":"","tax_registration":"","invoice_terms":"Payment status is recorded separately from this invoice."
}') on conflict do nothing;
alter table public.operations_configuration enable row level security;
revoke all on public.operations_configuration from anon,authenticated;
create or replace function private.ops() returns jsonb language sql stable security definer set search_path='' as $$ select config from public.operations_configuration where id $$;
create or replace function public.operations_config() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.account_active() then raise exception 'Sign in.' using errcode='42501';end if;
 return private.ops();
end $$;
create or replace function public.admin_operations_config(p_data jsonb) returns void language plpgsql security definer set search_path='' as $$
declare cfg jsonb; old_cfg jsonb; k text; n numeric;
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 select config into cfg from public.operations_configuration where id for update;
 for k in select jsonb_object_keys(p_data) loop
  if not cfg ? k then raise exception 'Unknown operational setting.';end if;
 end loop;
 old_cfg:=cfg;
 if p_data ? 'payment_ready_at' then raise exception 'Payment readiness time is server managed.';end if;
 cfg:=cfg||p_data;
 if (cfg->>'timezone'<>old_cfg->>'timezone' or cfg->>'week_start_day'<>old_cfg->>'week_start_day') and exists(select 1 from public.weekly_commission_periods) then raise exception 'Recorded financial periods fix the weekly cycle. An audited period migration is required to change its timezone or start day.';end if;
 if cfg->>'payment_instructions' is distinct from old_cfg->>'payment_instructions' and length(trim(cfg->>'payment_instructions'))>0 then cfg:=cfg||jsonb_build_object('payment_ready_at',now());end if;
 for k in select unnest(array['request_timeout_minutes','otp_ttl_seconds','otp_max_attempts','ring_seconds','call_max_seconds','call_heartbeat_seconds','commission_percent','commission_fixed_paise','week_start_day','deadline_days','grace_hours','minimum_commission_paise','tax_percent']) loop
  n:=(cfg->>k)::numeric;
  if n is null or n<0 or n>100000000 then raise exception 'Invalid numeric setting.';end if;
 end loop;
 if (cfg->>'commission_percent')::numeric>100 or(cfg->>'tax_percent')::numeric>100 or(cfg->>'week_start_day')::int not between 0 and 6 or(cfg->>'otp_ttl_seconds')::int not between 60 and 1800 or(cfg->>'otp_max_attempts')::int not between 1 and 10 or(cfg->>'ring_seconds')::int not between 10 and 120 or(cfg->>'call_max_seconds')::int not between 60 and 14400 or(cfg->>'call_heartbeat_seconds')::int not between 20 and 120 then raise exception 'Setting is outside its supported range.';end if;
 if cfg->>'request_expiry_mode' not in ('pending','expire') or not exists(select 1 from pg_timezone_names where name=cfg->>'timezone') then raise exception 'Choose a valid expiry policy and timezone.';end if;
 if jsonb_typeof(cfg->'call_statuses')<>'array' or jsonb_array_length(cfg->'call_statuses')=0 or exists(select 1 from jsonb_array_elements_text(cfg->'call_statuses') s where s not in ('requested','quote_sent','confirmed','on_the_way','arrived','work_started','work_paused')) then raise exception 'Choose valid call availability statuses.';end if;
 if jsonb_typeof(cfg->'payment_methods')<>'array' or exists(select 1 from jsonb_array_elements_text(cfg->'payment_methods') s where s not in ('bank_transfer','upi','cash')) then raise exception 'Choose supported commission payment methods.';end if;
 for k in select unnest(array['calling_enabled','relay_only','commission_enabled','auto_suspend','auto_reactivate','tax_enabled']) loop
  if jsonb_typeof(cfg->k)<>'boolean' then raise exception 'Invalid switch setting.';end if;
 end loop;
 if length(cfg->>'payment_instructions')>4000 or length(cfg->>'supplier_name')>200 or length(cfg->>'supplier_address')>1000 or length(cfg->>'invoice_terms')>2000 then raise exception 'Setting text is too long.';end if;
 if (cfg->>'tax_enabled')::boolean and(coalesce(cfg->>'tax_registration','')='' or coalesce(cfg->>'supplier_name','')='') then raise exception 'Configure supplier identity and tax registration before enabling tax.';end if;
 update public.operations_configuration set config=cfg,updated_at=now() where id;
 perform private.audit('Update booking, privacy, calling and commission policy');
end $$;
-- Redact contact-like text in legacy records; reject it in newly shared content.
create or replace function private.safe_text(p_text text) returns text language sql immutable set search_path='' as $$
 select regexp_replace(coalesce(p_text,''),'(?:[+]?91[[:space:]().-]*)?[6-9](?:[[:space:]().-]*[0-9]){9}(?![0-9])','[contact details hidden]','g')
$$;
create or replace function private.check_private_text(p_text text) returns void language plpgsql set search_path='' as $$
begin
 if private.safe_text(p_text)<>coalesce(p_text,'') then raise exception 'Please keep phone numbers private. Use Local Mate chat and in-app calls.';end if;
end $$;
create or replace function private.safe_json(p_value jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare result jsonb; item record;
begin
 if jsonb_typeof(p_value)='object' then
  result:='{}';for item in select key,value from jsonb_each(p_value) loop
   if item.key !~* '(phone|mobile|email|contact)' then result:=result||jsonb_build_object(item.key,private.safe_json(item.value));end if;
  end loop;return result;
 elsif jsonb_typeof(p_value)='array' then
  select coalesce(jsonb_agg(private.safe_json(value)),'[]') into result from jsonb_array_elements(p_value);return result;
 elsif jsonb_typeof(p_value)='string' then return to_jsonb(private.safe_text(p_value#>>'{}'));
 else return p_value;end if;
end $$;
alter table public.bookings add column if not exists accepted_at timestamptz;
alter table public.bookings add column if not exists request_expires_at timestamptz;
alter table public.bookings add column if not exists request_expired boolean not null default false;
create table if not exists public.booking_provider_offers(booking_id uuid references public.bookings(id) on delete cascade,provider_id uuid references public.provider_profiles(user_id) on delete cascade,status text not null default 'pending' check(status in ('pending','accepted','lost','rejected','expired')),offered_at timestamptz not null default now(),responded_at timestamptz,primary key(booking_id,provider_id));
create table if not exists public.booking_assignments(booking_id uuid primary key references public.bookings(id) on delete cascade,provider_id uuid not null references public.provider_profiles(user_id),accepted_at timestamptz not null,actor_id uuid not null references public.users(id));
create table if not exists public.booking_assignment_history(id bigint generated always as identity primary key,booking_id uuid references public.bookings(id) on delete cascade,provider_id uuid references public.provider_profiles(user_id),actor_id uuid references public.users(id),event text not null,created_at timestamptz not null default now());
create table if not exists public.booking_events(id bigint generated always as identity primary key,booking_id uuid not null references public.bookings(id) on delete cascade,kind text not null,created_at timestamptz not null default now());
create table if not exists public.message_reads(booking_id uuid references public.bookings(id) on delete cascade,user_id uuid references public.users(id) on delete cascade,last_message_id bigint not null default 0,read_at timestamptz not null default now(),primary key(booking_id,user_id));
create table if not exists public.media_assets(id uuid primary key default gen_random_uuid(),owner_id uuid not null references public.users(id),booking_id uuid references public.bookings(id) on delete cascade,kind text not null check(kind in ('booking','chat','before','after','commission','logo')),object_path text not null unique,mime text not null default 'image/jpeg',byte_size integer not null check(byte_size between 1 and 5242880),review_status text not null default 'pending' check(review_status in ('pending','approved','rejected')),review_note text not null default '',created_at timestamptz not null default now());
alter table public.messages add column if not exists attachment_id uuid references public.media_assets(id) on delete set null;
alter table public.provider_profiles add column if not exists logo_id uuid references public.media_assets(id) on delete set null;
-- New records never share user-entered contact details, including through Realtime.
create or replace function private.enforce_content_privacy() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_table_name='messages' or tg_table_name='reviews' then if tg_op='INSERT' or new.body is distinct from old.body then perform private.check_private_text(new.body);end if;
 elsif tg_table_name='provider_profiles' then if tg_op='INSERT' or new.business_name is distinct from old.business_name then perform private.check_private_text(new.business_name);end if;if tg_op='INSERT' or new.description is distinct from old.description then perform private.check_private_text(new.description);end if;new.publish_phone:=false;
 elsif tg_table_name='bookings' then if tg_op='INSERT' or new.description is distinct from old.description then perform private.check_private_text(new.description);end if;if tg_op='INSERT' or new.address is distinct from old.address then perform private.check_private_text(new.address);end if;if tg_op='INSERT' or new.details is distinct from old.details then perform private.check_private_text(new.details::text);end if;
 elsif tg_table_name='quotations' then if tg_op='INSERT' or new.terms is distinct from old.terms then perform private.check_private_text(new.terms);end if;
 elsif tg_table_name='users' then
  if tg_op='UPDATE' and new.name is not distinct from old.name then return new;end if;
  if tg_op='INSERT' and exists(select 1 from public.users where id=new.id) then return new;end if;
  perform private.check_private_text(new.name);
 end if;return new;
end $$;
do $$ declare t text;begin
 foreach t in array array['messages','reviews','provider_profiles','bookings','quotations','users'] loop
  execute format('drop trigger if exists enforce_content_privacy on public.%I',t);
  execute format('create trigger enforce_content_privacy before insert or update on public.%I for each row execute function private.enforce_content_privacy()',t);
 end loop;
end $$;
create or replace function private.emit_booking_event() returns trigger language plpgsql security definer set search_path='' as $$
declare target uuid;
begin
 if tg_table_name='bookings' then target:=new.id;else target:=new.booking_id;end if;
 insert into public.booking_events(booking_id,kind) values(target,tg_table_name);
 return new;
end $$;
do $$ declare t text;begin
 foreach t in array array['bookings','messages'] loop
  execute format('drop trigger if exists emit_booking_event on public.%I',t);
  execute format('create trigger emit_booking_event after insert or update on public.%I for each row execute function private.emit_booking_event()',t);
 end loop;
end $$;
create or replace function public.booking_contacts(p_booking uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare b public.bookings;
begin
 if not public.account_active() or not public.can_message_booking(p_booking) then raise exception 'This conversation is private.' using errcode='42501';end if;
 select * into b from public.bookings where id=p_booking;
 return jsonb_build_object('customer',jsonb_build_object('name','Customer · '||left(b.id::text,8)),
 'provider',(select jsonb_build_object('name',private.safe_text(coalesce(nullif(p.business_name,''),u.name)),'logo_id',p.logo_id,'verified',p.status='approved') from public.provider_profiles p join public.users u on u.id=p.user_id where p.user_id=b.provider_id));
end $$;
create or replace view public.public_providers with(security_barrier=true) as
 select p.user_id,private.safe_text(p.business_name) business_name,private.safe_text(p.category) category,private.safe_text(p.description) description,p.experience,p.service_ids,p.locations,p.online,private.safe_text(u.name) name,
 (select avg(r.rating) from public.reviews r where r.provider_id=p.user_id) rating,(select count(*) from public.reviews r where r.provider_id=p.user_id) review_count
 from public.provider_profiles p join public.users u on u.id=p.user_id where p.status='approved' and u.is_active;
create or replace function public.provider_directory() returns setof jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',p.user_id,'name',private.safe_text(coalesce(nullif(p.business_name,''),u.name)),'business_name',private.safe_text(p.business_name),'category',private.safe_text(p.category),'description',private.safe_text(p.description),'experience',p.experience,'service_ids',p.service_ids,'locations',p.locations,'online',p.online,'logo_id',p.logo_id,
 'assessment_rating',p.assessment_rating,'rating_source',private.safe_text(p.rating_source),'rating',(select avg(r.rating) from public.reviews r where r.provider_id=p.user_id),'review_count',(select count(*) from public.reviews r where r.provider_id=p.user_id),'completed_job_count',(select count(*) from public.bookings b where b.provider_id=p.user_id and b.status='work_completed'),
 'offerings',coalesce((select jsonb_agg(to_jsonb(o)-'provider_id') from public.provider_offerings o join public.services s on s.id=o.service_id and s.active where o.provider_id=p.user_id),'[]'::jsonb))
 from public.provider_profiles p join public.users u on u.id=p.user_id cross join public.website_configuration cfg where p.status='approved' and u.is_active and cfg.id and not cfg.maintenance_mode and cfg.provider_portal_enabled order by p.business_name;
$$;
-- Read receipts expose booking identities only, never profile contact information.
create or replace function public.conversation_messages(p_booking uuid) returns setof jsonb language plpgsql security definer set search_path='' as $$
begin
 if not public.account_active() or not public.can_message_booking(p_booking) then raise exception 'You cannot access this conversation.' using errcode='42501';end if;
 insert into public.message_reads(booking_id,user_id,last_message_id) select p_booking,auth.uid(),coalesce(max(id),0) from public.messages where booking_id=p_booking on conflict(booking_id,user_id) do update set last_message_id=excluded.last_message_id,read_at=now();
 return query select jsonb_build_object('id',m.id,'booking_id',m.booking_id,'sender_id',m.sender_id,'body',private.safe_text(m.body),'created_at',m.created_at,'attachment_id',m.attachment_id,
 'sender_name',case when m.sender_id=b.customer_id then 'Customer · '||left(b.id::text,8) else private.safe_text(coalesce(nullif(p.business_name,''),'Service provider')) end,
 'is_read',exists(select 1 from public.message_reads mr where mr.booking_id=m.booking_id and mr.user_id<>m.sender_id and mr.last_message_id>=m.id))
 from public.messages m join public.bookings b on b.id=m.booking_id left join public.provider_profiles p on p.user_id=m.sender_id where m.booking_id=p_booking order by m.id;
end $$;
create or replace function public.booking_messages(p_booking uuid) returns table(id bigint,booking_id uuid,sender_id uuid,body text,created_at timestamptz,sender_name text) language sql security definer set search_path='' as $$
 select (v->>'id')::bigint,(v->>'booking_id')::uuid,(v->>'sender_id')::uuid,v->>'body',(v->>'created_at')::timestamptz,v->>'sender_name' from public.conversation_messages(p_booking) v
$$;
create or replace function public.send_message(p_booking uuid,p_body text) returns bigint language plpgsql security definer set search_path='' as $$
declare mid bigint; other_user uuid;
begin
 perform private.take_rate_limit();if not public.can_message_booking(p_booking) then raise exception 'You cannot access this conversation.' using errcode='42501';end if;
 perform private.check_private_text(p_body);
 insert into public.messages(booking_id,sender_id,body) values(p_booking,auth.uid(),trim(p_body)) returning id into mid;
 select case when customer_id=auth.uid() then provider_id else customer_id end into other_user from public.bookings where id=p_booking;
 perform private.notify(other_user,'New Local Mate booking message',p_booking);return mid;
end $$;
create or replace function public.safe_notifications(p_mark_read boolean default false) returns setof jsonb language plpgsql security definer set search_path='' as $$
begin
 if not public.account_active() then raise exception 'Sign in.' using errcode='42501';end if;
 if p_mark_read then update public.notifications set is_read=true where user_id=auth.uid();end if;
 return query select to_jsonb(n)||jsonb_build_object('title',private.safe_text(n.title)) from public.notifications n where user_id=auth.uid() order by id desc limit 100;
end $$;
-- Actual new workflow tables are private-by-default and modified only by checked RPCs.
do $$ declare t text;begin
 foreach t in array array['booking_provider_offers','booking_assignments','booking_assignment_history','booking_events','message_reads','media_assets'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon,authenticated',t);
 end loop;
end $$;
create or replace function public.was_offered_booking(p_booking uuid) returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.booking_provider_offers where booking_id=p_booking and provider_id=auth.uid()) $$;
revoke execute on function public.was_offered_booking(uuid) from public,anon;grant execute on function public.was_offered_booking(uuid) to authenticated;
drop policy if exists events_read on public.booking_events;
create policy events_read on public.booking_events for select to authenticated using(public.account_active() and(public.can_view_booking(booking_id) or public.was_offered_booking(booking_id)));
grant select on public.booking_events to authenticated;
revoke select on public.bookings,public.messages,public.quotations,public.reviews,public.notifications from anon,authenticated;
revoke update on public.notifications from authenticated;
revoke execute on function public.operations_config(),public.admin_operations_config(jsonb),public.safe_notifications(boolean),public.booking_messages(uuid),public.conversation_messages(uuid) from public,anon;
grant execute on function public.operations_config(),public.admin_operations_config(jsonb),public.safe_notifications(boolean),public.booking_messages(uuid),public.conversation_messages(uuid) to authenticated;
revoke execute on all functions in schema private from public,anon,authenticated;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='booking_events') then alter publication supabase_realtime add table public.booking_events;end if;
end $$;
notify pgrst, 'reload schema';
