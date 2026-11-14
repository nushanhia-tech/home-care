-- LOCAL MATE: COMPLETE SUPABASE SQL EDITOR SETUP
-- Generated from the checked-in migrations and starter catalogue.
-- Run this entire file in Supabase Dashboard > SQL Editor as the project owner.
-- The designated administrator is included by the bootstrap migration.
-- Optionally set an additional administrator email below; otherwise leave it blank.
-- Can be rerun for this schema; preserves existing accounts, bookings and service edits.
-- This configures the database only. Add environment variables and Auth callback URLs separately.
-- Use SQL Editor setup OR Supabase CLI migrations. See README before mixing the two workflows.

begin;
select pg_advisory_xact_lock(hashtext('local_mate_database_setup'));
set local app.local_mate_admin_email = '';

-- Migration: 20261114000100_marketplace.sql
-- Local Mate: PostgreSQL schema, transactional workflows, and row-level security.
create schema if not exists private;
revoke all on schema private from public;
create table if not exists private.admin_emails (email text primary key check (email = lower(email)));
create table if not exists public.users (
 id uuid primary key references auth.users(id) on delete cascade,
 email text not null, name text not null default '', phone text not null default '',
 created_at timestamptz not null default now()
);
create table if not exists public.locations (name text primary key, active boolean not null default true);
create table if not exists public.services (
 id text primary key, name text not null check(length(name) between 1 and 100),
 category text not null, description text not null, price integer not null default 0 check(price>=0),
 type text not null check(type in ('fixed','quote','transport','goods','rental','emergency')),
 icon text not null default '🔧', tone text not null default 'blue', active boolean not null default true
);
create table if not exists public.provider_profiles (
 user_id uuid primary key references public.users(id) on delete cascade,
 business_name text not null default '', category text not null, service_ids text[] not null,
 locations text[] not null, description text not null check(length(description) between 1 and 2000),
 experience integer not null default 0 check(experience between 0 and 70),
 status text not null default 'pending' check(status in ('pending','approved','rejected','suspended')),
 online boolean not null default false, schedule jsonb not null default '{}', created_at timestamptz not null default now()
);
create table if not exists public.addresses (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references public.users(id) on delete cascade,
 label text not null,address text not null,location text not null references public.locations(name),created_at timestamptz not null default now()
);
create table if not exists public.bookings (
 id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.users(id),
 service_id text not null references public.services(id), provider_id uuid references public.provider_profiles(user_id),
 location text not null references public.locations(name),address text not null,scheduled_at timestamptz not null,
 description text not null,details jsonb not null default '{}',
 status text not null default 'requested' check(status in ('requested','quote_sent','confirmed','on_the_way','arrived','work_started','work_paused','work_completed','cancelled','disputed')),
 estimated_price integer not null default 0 check(estimated_price>=0),
 payment_method text not null default 'cash' check(payment_method in ('cash','online')),
 payment_status text not null default 'pending' check(payment_status in ('pending','processing','successful','failed','refunded','partially_refunded')),
 idempotency_key uuid not null,created_at timestamptz not null default now(),unique(customer_id,idempotency_key)
);
create index if not exists bookings_customer on public.bookings(customer_id,created_at desc);
create index if not exists bookings_provider on public.bookings(provider_id,status);
create index if not exists bookings_matching on public.bookings(service_id,location,status) where provider_id is null;
create table if not exists public.booking_status_history (
 id bigint generated always as identity primary key,booking_id uuid not null references public.bookings(id),
 actor_id uuid not null references public.users(id),status text not null,note text not null default '',created_at timestamptz not null default now()
);
create table if not exists public.booking_rejections (booking_id uuid references public.bookings(id),provider_id uuid references public.provider_profiles(user_id),created_at timestamptz not null default now(),primary key(booking_id,provider_id));
create table if not exists public.quotations (
 id uuid primary key default gen_random_uuid(),booking_id uuid not null references public.bookings(id),provider_id uuid not null references public.provider_profiles(user_id),
 labour integer not null check(labour between 0 and 10000000),materials integer not null check(materials between 0 and 10000000),additional integer not null default 0 check(additional between 0 and 10000000),
 terms text not null,status text not null default 'pending' check(status in ('pending','approved','rejected')),created_at timestamptz not null default now()
);
create unique index if not exists one_pending_quote on public.quotations(booking_id) where status='pending';
create table if not exists public.messages (id bigint generated always as identity primary key,booking_id uuid not null references public.bookings(id),sender_id uuid not null references public.users(id),body text not null check(length(body) between 1 and 4000),created_at timestamptz not null default now());
create index if not exists messages_booking on public.messages(booking_id,created_at,id);
create table if not exists public.notifications (id bigint generated always as identity primary key,user_id uuid not null references public.users(id),title text not null,booking_id uuid references public.bookings(id),is_read boolean not null default false,created_at timestamptz not null default now());
create index if not exists notifications_user on public.notifications(user_id,created_at desc);
create table if not exists public.reviews (id uuid primary key default gen_random_uuid(),booking_id uuid not null unique references public.bookings(id),customer_id uuid not null references public.users(id),provider_id uuid not null references public.provider_profiles(user_id),rating integer not null check(rating between 1 and 5),body text not null check(length(body) between 1 and 2000),created_at timestamptz not null default now());
create table if not exists public.payments (id uuid primary key default gen_random_uuid(),booking_id uuid not null unique references public.bookings(id),amount integer not null check(amount>0),gateway_order_id text unique,gateway_payment_id text unique,status text not null default 'pending' check(status in ('pending','processing','successful','failed','refunded','partially_refunded')),created_at timestamptz not null default now());
create table if not exists public.support_tickets (id uuid primary key default gen_random_uuid(),user_id uuid not null references public.users(id),booking_id uuid references public.bookings(id),subject text not null check(length(subject) between 1 and 200),body text not null check(length(body) between 1 and 4000),status text not null default 'open' check(status in ('open','under_review','resolved','closed')),resolution text,created_at timestamptz not null default now());
create table if not exists public.favourites (user_id uuid references public.users(id),provider_id uuid references public.provider_profiles(user_id),primary key(user_id,provider_id));
create table if not exists public.settings (key text primary key,value jsonb not null);
create table if not exists public.admin_activity_logs (id bigint generated always as identity primary key,actor_id uuid not null references public.users(id),action text not null,target_id text,created_at timestamptz not null default now());
create table if not exists private.request_windows (user_id uuid references public.users(id),window_start bigint,hits integer not null default 0,primary key(user_id,window_start));

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.users u join private.admin_emails a on a.email=lower(u.email) where u.id=auth.uid() and u.email_confirmed_at is not null)
$$;
create or replace function private.sync_user() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.users(id,email,name) values(new.id,new.email,coalesce(nullif(new.raw_user_meta_data->>'full_name',''),split_part(new.email,'@',1)))
 on conflict(id) do update set email=excluded.email;
 return new;
end $$;
do $setup_trigger$ begin
 if not exists(select 1 from pg_trigger where tgrelid='auth.users'::regclass and tgname='on_auth_user_created') then
  create trigger on_auth_user_created after insert or update of email on auth.users for each row execute function private.sync_user();
 end if;
end $setup_trigger$;

create or replace function private.take_rate_limit() returns void language plpgsql security definer set search_path='' as $$
declare count_now integer; minute_now bigint := floor(extract(epoch from now())/60);
begin
 if auth.uid() is null then raise exception 'Please sign in.' using errcode='42501';end if;
 insert into private.request_windows(user_id,window_start,hits) values(auth.uid(),minute_now,1)
 on conflict(user_id,window_start) do update set hits=private.request_windows.hits+1 where private.request_windows.hits<60 returning hits into count_now;
 if count_now is null then raise exception 'Too many updates. Please try again in a minute.' using errcode='P0001';end if;
end $$;
create or replace function public.provider_eligible(p_provider uuid,p_service text,p_location text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.provider_profiles p where p.user_id=p_provider and p.status='approved' and p.online and p_service=any(p.service_ids) and p_location=any(p.locations))
$$;
create or replace function public.can_view_booking(p_booking uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.bookings b where b.id=p_booking and (public.is_admin() or b.customer_id=auth.uid() or b.provider_id=auth.uid() or (b.provider_id is null and b.status='requested' and public.provider_eligible(auth.uid(),b.service_id,b.location) and not exists(select 1 from public.booking_rejections r where r.booking_id=b.id and r.provider_id=auth.uid()))))
$$;
create or replace function public.can_message_booking(p_booking uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.bookings b where b.id=p_booking and (public.is_admin() or b.customer_id=auth.uid() or b.provider_id=auth.uid()))
$$;
create or replace function private.notify(p_user uuid,p_title text,p_booking uuid default null) returns void language sql security definer set search_path='' as $$
 insert into public.notifications(user_id,title,booking_id) select p_user,p_title,p_booking where p_user is not null
$$;
create or replace function private.record_history(p_booking uuid,p_status text,p_note text default '') returns void language sql security definer set search_path='' as $$
 insert into public.booking_status_history(booking_id,actor_id,status,note) values(p_booking,auth.uid(),p_status,p_note)
$$;
create or replace function private.audit(p_action text,p_target text default '') returns void language sql security definer set search_path='' as $$
 insert into public.admin_activity_logs(actor_id,action,target_id) values(auth.uid(),p_action,p_target)
$$;

create or replace function public.update_profile(p_name text,p_phone text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.take_rate_limit();
 if length(trim(p_name)) not between 1 and 100 or p_phone !~ '^(\+91)?[6-9][0-9]{9}$' then raise exception 'Enter your name and a valid Indian mobile number.';end if;
 update public.users set name=trim(p_name),phone=p_phone where id=auth.uid();
end $$;
create or replace function public.register_provider(p_data jsonb) returns void language plpgsql security definer set search_path='' as $$
declare ids text[]; areas text[];
begin
 perform private.take_rate_limit();
 if not exists(select 1 from public.users where id=auth.uid() and phone<>'') then raise exception 'Add your mobile number to your profile first.';end if;
 if exists(select 1 from public.provider_profiles where user_id=auth.uid()) then raise exception 'Your provider application already exists.';end if;
 ids:=array(select jsonb_array_elements_text(p_data->'service_ids'));areas:=array(select jsonb_array_elements_text(p_data->'locations'));
 if coalesce(array_length(ids,1),0)=0 or exists(select 1 from unnest(ids) as chosen(service_id) where not exists(select 1 from public.services s where s.id=chosen.service_id and s.active)) then raise exception 'Choose active services.';end if;
 if coalesce(array_length(areas,1),0)=0 or exists(select 1 from unnest(areas) area where not exists(select 1 from public.locations l where l.name=area and l.active)) then raise exception 'Choose supported service areas.';end if;
 insert into public.provider_profiles(user_id,business_name,category,service_ids,locations,description,experience) values(auth.uid(),left(coalesce(p_data->>'business_name',''),100),p_data->>'category',ids,areas,p_data->>'description',(p_data->>'experience')::integer);
end $$;
create or replace function public.set_availability(p_online boolean,p_schedule jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.take_rate_limit();
 if not exists(select 1 from public.provider_profiles where user_id=auth.uid()) then raise exception 'Provider registration is required.';end if;
 if coalesce((p_schedule->>'max_daily')::integer,5) not between 1 and 30 then raise exception 'Maximum daily bookings must be between 1 and 30.';end if;
 update public.provider_profiles set online=p_online,schedule=p_schedule where user_id=auth.uid();
end $$;
create or replace function public.create_booking(p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare s public.services; b_id uuid; candidate uuid; scheduled timestamptz;
begin
 perform private.take_rate_limit();
 select id into b_id from public.bookings where customer_id=auth.uid() and idempotency_key=(p_data->>'idempotency_key')::uuid;
 if b_id is not null then return b_id;end if;
 select * into s from public.services where id=p_data->>'service_id' and active;
 if s.id is null then raise exception 'This service is not available.';end if;
 if not exists(select 1 from public.locations where name=p_data->>'location' and active) then raise exception 'Choose a supported location.';end if;
 scheduled:=(p_data->>'scheduled_at')::timestamptz;
 if scheduled is null or scheduled<=now() then raise exception 'Choose a future date and time.';end if;
 if length(trim(coalesce(p_data->>'address',''))) not between 1 and 1000 or length(trim(coalesce(p_data->>'description',''))) not between 1 and 4000 then raise exception 'Enter your address and job details.';end if;
 if p_data->>'payment_method'<>'cash' then raise exception 'Choose pay after service.';end if;
 if s.type in ('transport','goods') and coalesce(p_data->'details'->>'destination','')='' then raise exception 'Enter your destination.';end if;
 if s.type='rental' and (coalesce(p_data->'details'->>'end_date','')='' or (p_data->'details'->>'end_date')::timestamptz<scheduled) then raise exception 'Choose a valid rental end date.';end if;
 if not exists(select 1 from public.provider_profiles p where public.provider_eligible(p.user_id,s.id,p_data->>'location')) then raise exception 'No approved, online provider is available for this service in your town yet.';end if;
 insert into public.bookings(customer_id,service_id,location,address,scheduled_at,description,details,estimated_price,idempotency_key)
 values(auth.uid(),s.id,p_data->>'location',trim(p_data->>'address'),scheduled,trim(p_data->>'description'),coalesce(p_data->'details','{}'),s.price,(p_data->>'idempotency_key')::uuid)
 on conflict(customer_id,idempotency_key) do nothing returning id into b_id;
 if b_id is null then select id into b_id from public.bookings where customer_id=auth.uid() and idempotency_key=(p_data->>'idempotency_key')::uuid;return b_id;end if;
 perform private.record_history(b_id,'requested');perform private.notify(auth.uid(),'Your booking request has been created',b_id);
 for candidate in select user_id from public.provider_profiles where public.provider_eligible(user_id,s.id,p_data->>'location') loop perform private.notify(candidate,'New '||s.name||' request in '||(p_data->>'location'),b_id);end loop;
 return b_id;
end $$;
create or replace function public.booking_action(p_booking uuid,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.bookings;s public.services;q public.quotations;candidate boolean;assigned boolean;customer boolean;next_status text;quote_id uuid;new_date timestamptz;capacity integer;
begin
 perform private.take_rate_limit();
 select * into b from public.bookings where id=p_booking for update;
 if b.id is null or not public.can_view_booking(b.id) then raise exception 'You do not have access to this booking.' using errcode='42501';end if;
 select * into s from public.services where id=b.service_id;
 customer:=b.customer_id=auth.uid();assigned:=coalesce(b.provider_id=auth.uid(),false);
 candidate:=b.provider_id is null and b.status='requested' and public.provider_eligible(auth.uid(),b.service_id,b.location) and not exists(select 1 from public.booking_rejections where booking_id=b.id and provider_id=auth.uid());
 if p_action='accept' then
  if not candidate then raise exception 'This request is no longer available.';end if;
  if s.type='quote' then raise exception 'Send a quotation for this project first.';end if;
  -- Serialize assignments by provider as well as booking before enforcing daily capacity.
  perform 1 from public.provider_profiles where user_id=auth.uid() for update;
  select coalesce((schedule->>'max_daily')::integer,5) into capacity from public.provider_profiles where user_id=auth.uid();
  if (select count(*) from public.bookings where provider_id=auth.uid() and status not in ('cancelled','disputed') and (scheduled_at at time zone 'Asia/Kolkata')::date=(b.scheduled_at at time zone 'Asia/Kolkata')::date)>=capacity then raise exception 'Your daily booking limit has been reached.';end if;
  update public.bookings set provider_id=auth.uid(),status='confirmed' where id=b.id;
  perform private.record_history(b.id,'confirmed');perform private.notify(b.customer_id,'Your provider has accepted your booking',b.id);
 elsif p_action='reject' then
  if not candidate then raise exception 'This request is no longer available.';end if;
  insert into public.booking_rejections(booking_id,provider_id) values(b.id,auth.uid()) on conflict do nothing;
 elsif p_action='quote' then
  if not(candidate or assigned) or b.status not in ('requested','confirmed') then raise exception 'A quotation cannot be sent now.';end if;
  insert into public.quotations(booking_id,provider_id,labour,materials,additional,terms) values(b.id,auth.uid(),(p_data->>'labour')::integer,(p_data->>'materials')::integer,coalesce((p_data->>'additional')::integer,0),p_data->>'terms') returning id into quote_id;
  if length(trim(coalesce(p_data->>'terms',''))) not between 1 and 2000 then raise exception 'Add scope, terms and estimated completion time.';end if;
  update public.bookings set provider_id=auth.uid(),status='quote_sent' where id=b.id;
  perform private.record_history(b.id,'quote_sent');perform private.notify(b.customer_id,'A quotation is ready for your approval',b.id);
  return jsonb_build_object('id',quote_id);
 elsif p_action='quote-response' then
  if not customer or b.status<>'quote_sent' then raise exception 'Only the customer can respond to a pending quotation.' using errcode='42501';end if;
  select * into q from public.quotations where id=(p_data->>'quote_id')::uuid and booking_id=b.id and status='pending' for update;
  if q.id is null then raise exception 'Quotation is no longer pending.';end if;
  if (p_data->>'accept')::boolean then
   update public.quotations set status='approved' where id=q.id;
   update public.bookings set status='confirmed',estimated_price=q.labour+q.materials+q.additional where id=b.id;
   perform private.record_history(b.id,'confirmed');perform private.notify(q.provider_id,'Your quotation was approved',b.id);
  else
   update public.quotations set status='rejected' where id=q.id;
   insert into public.booking_rejections(booking_id,provider_id) values(b.id,q.provider_id) on conflict do nothing;
   update public.bookings set status='requested',provider_id=null where id=b.id;
   perform private.record_history(b.id,'requested','Quotation declined');perform private.notify(q.provider_id,'Your quotation was declined',b.id);
  end if;
 elsif p_action='reschedule' then
  if not customer or b.status not in ('requested','confirmed') then raise exception 'This booking cannot be rescheduled.';end if;
  new_date:=(p_data->>'scheduled_at')::timestamptz;if new_date is null or new_date<=now() then raise exception 'Choose a future date and time.';end if;
  update public.bookings set scheduled_at=new_date where id=b.id;perform private.record_history(b.id,b.status,'Rescheduled to '||new_date::text);perform private.notify(b.provider_id,'A booking has been rescheduled',b.id);
 elsif p_action='status' then
  next_status:=p_data->>'status';
  if not assigned and not public.is_admin() and not(customer and next_status in ('cancelled','disputed')) then raise exception 'This status update is not permitted.' using errcode='42501';end if;
  if not(
   (next_status='cancelled' and b.status in ('requested','quote_sent','confirmed','on_the_way','arrived') and (customer or assigned or public.is_admin())) or
   (next_status='disputed' and b.status in ('work_started','work_paused','work_completed')) or
   (next_status='on_the_way' and b.status='confirmed') or (next_status='arrived' and b.status='on_the_way') or
   (next_status='work_started' and b.status in ('arrived','work_paused')) or (next_status='work_paused' and b.status='work_started') or
   (next_status='work_completed' and b.status='work_started')
  ) then raise exception 'This status change is not permitted.';end if;
  update public.bookings set status=next_status where id=b.id;
  if next_status='cancelled' then update public.quotations set status='rejected' where booking_id=b.id and status='pending';end if;
  perform private.record_history(b.id,next_status);perform private.notify(case when customer then b.provider_id else b.customer_id end,'Booking update: '||replace(next_status,'_',' '),b.id);
 elsif p_action='review' then
  if not customer or b.status<>'work_completed' or b.provider_id is null then raise exception 'Reviews require an owned, completed booking.' using errcode='42501';end if;
  insert into public.reviews(booking_id,customer_id,provider_id,rating,body) values(b.id,auth.uid(),b.provider_id,(p_data->>'rating')::integer,trim(p_data->>'body'));
 else raise exception 'Unknown booking action.';
 end if;
 return jsonb_build_object('ok',true);
end $$;

create or replace function public.send_message(p_booking uuid,p_body text) returns bigint language plpgsql security definer set search_path='' as $$
declare message_id bigint;b public.bookings;
begin
 perform private.take_rate_limit();
 if not public.can_message_booking(p_booking) then raise exception 'You cannot access this conversation.' using errcode='42501';end if;
 select * into b from public.bookings where id=p_booking;
 insert into public.messages(booking_id,sender_id,body) values(p_booking,auth.uid(),trim(p_body)) returning id into message_id;
 perform private.notify(case when b.customer_id=auth.uid() then b.provider_id else b.customer_id end,'New message about your booking',p_booking);
 return message_id;
end $$;
create or replace function public.list_bookings(p_role text default 'customer') returns setof jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Please sign in.' using errcode='42501';end if;
 if p_role='admin' and not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 return query select to_jsonb(b)||jsonb_build_object('service_name',s.name,'customer_name',c.name,'provider_name',p.name)
 from public.bookings b join public.services s on s.id=b.service_id join public.users c on c.id=b.customer_id left join public.users p on p.id=b.provider_id
 where case p_role when 'admin' then public.is_admin() when 'provider' then b.provider_id=auth.uid() or (b.provider_id is null and b.status='requested' and public.provider_eligible(auth.uid(),b.service_id,b.location) and not exists(select 1 from public.booking_rejections r where r.booking_id=b.id and r.provider_id=auth.uid())) else b.customer_id=auth.uid() end
 order by b.created_at desc;
end $$;
create or replace function public.booking_messages(p_booking uuid) returns table(id bigint,booking_id uuid,sender_id uuid,body text,created_at timestamptz,sender_name text) language plpgsql stable security definer set search_path='' as $$
begin
 if not public.can_message_booking(p_booking) then raise exception 'You cannot access this conversation.' using errcode='42501';end if;
 return query select m.id,m.booking_id,m.sender_id,m.body,m.created_at,u.name from public.messages m join public.users u on u.id=m.sender_id where m.booking_id=p_booking order by m.id;
end $$;
create or replace function public.admin_provider(p_user uuid,p_status text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 if p_status not in ('pending','approved','rejected','suspended') then raise exception 'Invalid status.';end if;
 update public.provider_profiles set status=p_status,online=case when p_status='approved' then online else false end where user_id=p_user;
 if not found then raise exception 'Provider not found.';end if;
 perform private.audit('Provider '||p_status,p_user::text);perform private.notify(p_user,'Your provider application is '||p_status);
end $$;
create or replace function public.admin_assign(p_booking uuid,p_provider uuid) returns void language plpgsql security definer set search_path='' as $$
declare b public.bookings;kind text;new_status text;
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 select * into b from public.bookings where id=p_booking for update;
 if b.id is null or b.status not in ('requested','confirmed','quote_sent') or not public.provider_eligible(p_provider,b.service_id,b.location) then raise exception 'Choose an available, approved provider matching this service and area.';end if;
 select type into kind from public.services where id=b.service_id;new_status:=case when kind='quote' then 'requested' else 'confirmed' end;
 update public.quotations set status='rejected' where booking_id=b.id and status='pending';
 update public.bookings set provider_id=p_provider,status=new_status where id=b.id;
 perform private.record_history(b.id,new_status,'Assigned by administrator');perform private.audit('Assign booking',b.id::text);
 perform private.notify(p_provider,'A booking has been assigned to you',b.id);perform private.notify(b.customer_id,'Your booking has been assigned',b.id);
end $$;
create or replace function public.admin_save_service(p_data jsonb) returns text language plpgsql security definer set search_path='' as $$
declare service_id text:=coalesce(nullif(p_data->>'id',''),gen_random_uuid()::text);
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 insert into public.services(id,name,category,description,price,type,icon,tone,active) values(service_id,trim(p_data->>'name'),p_data->>'category',p_data->>'description',(p_data->>'price')::integer,p_data->>'type',coalesce(p_data->>'icon','🔧'),coalesce(p_data->>'tone','blue'),coalesce((p_data->>'active')::boolean,true))
 on conflict(id) do update set name=excluded.name,category=excluded.category,description=excluded.description,price=excluded.price,type=excluded.type,active=excluded.active;
 perform private.audit('Save service',service_id);return service_id;
end $$;
create or replace function public.admin_commission(p_percent numeric) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 if p_percent is null or p_percent<0 or p_percent>100 then raise exception 'Commission must be between 0 and 100.';end if;
 insert into public.settings(key,value) values('commission',to_jsonb(p_percent)) on conflict(key) do update set value=excluded.value;perform private.audit('Update commission');
end $$;
create or replace function public.admin_support(p_ticket uuid,p_status text,p_resolution text) returns void language plpgsql security definer set search_path='' as $$
declare ticket public.support_tickets;
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 if p_status not in ('open','under_review','resolved','closed') or length(trim(p_resolution)) not between 1 and 4000 then raise exception 'Choose a status and add a response.';end if;
 update public.support_tickets set status=p_status,resolution=trim(p_resolution) where id=p_ticket returning * into ticket;
 perform private.audit('Update support ticket',p_ticket::text);perform private.notify(ticket.user_id,'Your support request has an update');
end $$;

-- Public profiles deliberately omit contact details, identity records and payout data.
create or replace view public.public_providers with(security_barrier=true) as
 select p.user_id,p.business_name,p.category,p.description,p.experience,p.service_ids,p.locations,p.online,u.name,
 (select avg(r.rating) from public.reviews r where r.provider_id=p.user_id) as rating,
 (select count(*) from public.reviews r where r.provider_id=p.user_id) as review_count
 from public.provider_profiles p join public.users u on u.id=p.user_id where p.status='approved';

-- Every table in the exposed schema has RLS; writes to protected workflow tables use RPCs.
alter table public.users enable row level security;
alter table public.locations enable row level security;
alter table public.services enable row level security;
alter table public.provider_profiles enable row level security;
alter table public.addresses enable row level security;
alter table public.bookings enable row level security;
alter table public.booking_status_history enable row level security;
alter table public.booking_rejections enable row level security;
alter table public.quotations enable row level security;
alter table public.messages enable row level security;
alter table public.notifications enable row level security;
alter table public.reviews enable row level security;
alter table public.payments enable row level security;
alter table public.support_tickets enable row level security;
alter table public.favourites enable row level security;
alter table public.settings enable row level security;
alter table public.admin_activity_logs enable row level security;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='users' and policyname='users_read') then
  create policy users_read on public.users for select to authenticated using(id=auth.uid() or public.is_admin());
 end if;
end $setup_policy$;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='locations' and policyname='locations_read') then
  create policy locations_read on public.locations for select using(active or public.is_admin());
 end if;
end $setup_policy$;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='services' and policyname='services_read') then
  create policy services_read on public.services for select using(active or public.is_admin());
 end if;
end $setup_policy$;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='provider_profiles' and policyname='providers_read') then
  create policy providers_read on public.provider_profiles for select to authenticated using(user_id=auth.uid() or public.is_admin());
 end if;
end $setup_policy$;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='addresses' and policyname='addresses_owner') then
  create policy addresses_owner on public.addresses for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
 end if;
end $setup_policy$;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='bookings' and policyname='bookings_read') then
  create policy bookings_read on public.bookings for select to authenticated using(public.can_view_booking(id));
 end if;
end $setup_policy$;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='booking_status_history' and policyname='history_read') then
  create policy history_read on public.booking_status_history for select to authenticated using(public.can_message_booking(booking_id));
 end if;
end $setup_policy$;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='booking_rejections' and policyname='rejections_read') then
  create policy rejections_read on public.booking_rejections for select to authenticated using(provider_id=auth.uid() or public.is_admin());
 end if;
end $setup_policy$;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='quotations' and policyname='quotes_read') then
  create policy quotes_read on public.quotations for select to authenticated using(public.can_message_booking(booking_id));
 end if;
end $setup_policy$;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='messages' and policyname='messages_read') then
  create policy messages_read on public.messages for select to authenticated using(public.can_message_booking(booking_id));
 end if;
end $setup_policy$;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='notifications' and policyname='notifications_read') then
  create policy notifications_read on public.notifications for select to authenticated using(user_id=auth.uid());
 end if;
end $setup_policy$;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='notifications' and policyname='notifications_mark_read') then
  create policy notifications_mark_read on public.notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
 end if;
end $setup_policy$;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='reviews' and policyname='reviews_read') then
  create policy reviews_read on public.reviews for select using(true);
 end if;
end $setup_policy$;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='payments' and policyname='payments_read') then
  create policy payments_read on public.payments for select to authenticated using(exists(select 1 from public.bookings b where b.id=booking_id and(b.customer_id=auth.uid() or b.provider_id=auth.uid() or public.is_admin())));
 end if;
end $setup_policy$;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='support_tickets' and policyname='tickets_read') then
  create policy tickets_read on public.support_tickets for select to authenticated using(user_id=auth.uid() or public.is_admin());
 end if;
end $setup_policy$;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='support_tickets' and policyname='tickets_create') then
  create policy tickets_create on public.support_tickets for insert to authenticated with check(user_id=auth.uid() and status='open' and resolution is null and(booking_id is null or exists(select 1 from public.bookings b where b.id=booking_id and(b.customer_id=auth.uid() or b.provider_id=auth.uid()))));
 end if;
end $setup_policy$;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='favourites' and policyname='favourites_owner') then
  create policy favourites_owner on public.favourites for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid() and exists(select 1 from public.public_providers p where p.user_id=provider_id));
 end if;
end $setup_policy$;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='settings' and policyname='settings_read') then
  create policy settings_read on public.settings for select to authenticated using(public.is_admin());
 end if;
end $setup_policy$;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='admin_activity_logs' and policyname='audit_read') then
  create policy audit_read on public.admin_activity_logs for select to authenticated using(public.is_admin());
 end if;
end $setup_policy$;

revoke all on all tables in schema public from anon,authenticated;
grant select on public.locations,public.services,public.public_providers,public.reviews to anon,authenticated;
grant select on public.users,public.provider_profiles,public.bookings,public.booking_status_history,public.booking_rejections,public.quotations,public.messages,public.notifications,public.payments,public.support_tickets,public.favourites,public.settings,public.admin_activity_logs to authenticated;
grant select,insert,update,delete on public.addresses to authenticated;
grant insert on public.support_tickets to authenticated;
grant select,insert,delete on public.favourites to authenticated;
grant update(is_read) on public.notifications to authenticated;
revoke execute on all functions in schema public from public,anon,authenticated;
grant execute on function public.is_admin(),public.provider_eligible(uuid,text,text),public.can_view_booking(uuid),public.can_message_booking(uuid) to authenticated;
grant execute on function public.is_admin() to anon;
grant execute on function public.update_profile(text,text),public.register_provider(jsonb),public.set_availability(boolean,jsonb),public.create_booking(jsonb),public.booking_action(uuid,text,jsonb),public.send_message(uuid,text),public.list_bookings(text),public.booking_messages(uuid),public.admin_provider(uuid,text),public.admin_assign(uuid,uuid),public.admin_save_service(jsonb),public.admin_commission(numeric),public.admin_support(uuid,text,text) to authenticated;
revoke execute on all functions in schema private from public,anon,authenticated;

-- Only the message and notification tables are published, and RLS still limits delivery.
do $setup_realtime$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='messages') then
   alter publication supabase_realtime add table public.messages;
  end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='notifications') then
   alter publication supabase_realtime add table public.notifications;
  end if;
 end if;
end $setup_realtime$;

-- Migration: 20261114000200_payment_integrity.sql
create or replace function public.reserve_payment(p_booking uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.bookings;p public.payments;
begin
 perform private.take_rate_limit();
 select * into b from public.bookings where id=p_booking and customer_id=auth.uid() for update;
 if b.id is null or b.status<>'work_completed' or b.payment_status<>'pending' or b.estimated_price<=0 then raise exception 'This booking is not ready for online payment.';end if;
 insert into public.payments(booking_id,amount) values(b.id,b.estimated_price) on conflict(booking_id) do nothing;
 select * into p from public.payments where booking_id=b.id;
 if p.status<>'pending' then raise exception 'This payment has already been processed.';end if;
 return to_jsonb(p);
end $$;
create or replace function public.attach_payment_order(p_payment uuid,p_order text) returns text language plpgsql security definer set search_path='' as $$
declare record public.payments;
begin
 if auth.role()<>'service_role' then raise exception 'Server payment authorization required.' using errcode='42501';end if;
 select * into record from public.payments where id=p_payment for update;
 if record.id is null or record.status<>'pending' then raise exception 'Payment is unavailable.';end if;
 if record.gateway_order_id is not null then return record.gateway_order_id;end if;
 update public.payments set gateway_order_id=p_order where id=p_payment;return p_order;
end $$;
create or replace function public.record_payment_capture(p_order text,p_gateway_payment text,p_amount_paise bigint) returns void language plpgsql security definer set search_path='' as $$
declare record public.payments;customer uuid;
begin
 if auth.role()<>'service_role' then raise exception 'Server payment authorization required.' using errcode='42501';end if;
 select * into record from public.payments where gateway_order_id=p_order for update;
 if record.id is null or record.amount::bigint*100<>p_amount_paise then raise exception 'Payment amount does not match.';end if;
 if record.status='successful' then
  if record.gateway_payment_id<>p_gateway_payment then raise exception 'Payment identity does not match.';end if;
  return;
 end if;
 update public.payments set status='successful',gateway_payment_id=p_gateway_payment where id=record.id;
 update public.bookings set payment_status='successful',payment_method='online' where id=record.booking_id returning customer_id into customer;
 perform private.notify(customer,'Your online payment has been verified',record.booking_id);
end $$;
revoke execute on function public.reserve_payment(uuid),public.attach_payment_order(uuid,text),public.record_payment_capture(text,text,bigint) from public,anon,authenticated;
grant execute on function public.reserve_payment(uuid) to authenticated;
grant execute on function public.attach_payment_order(uuid,text),public.record_payment_capture(text,text,bigint) to service_role;

-- Migration: 20261114000300_bootstrap_administrator.sql
-- Owner-designated administrator. Supabase Auth must confirm this email before access is granted.
-- This creates an allowlist entry only; it never creates an account or bypasses sign-in.
insert into private.admin_emails(email)
values ('mueenptb@gmail.com')
on conflict(email) do nothing;


-- Initial supported towns and editable services. Existing catalogue edits are preserved.
-- Initial catalogue. Admin membership is provisioned separately by the project owner.
insert into public.locations(name) values ('Pattambi'),('Ottapalam'),('Thrithala'),('Shoranur'),('Cherpulassery'),('Perinthalmanna') on conflict do nothing;
insert into public.services(id,name,category,description,price,type,icon,tone) values ('cleaning','House cleaning','Home care','A fresh start for every corner of your home.',499,'fixed','🧹','mint') on conflict do nothing;
insert into public.services(id,name,category,description,price,type,icon,tone) values ('plumbing','Plumbing','Home care','Leaks, taps, pipes. Leave it to a local expert.',249,'fixed','🔧','blue') on conflict do nothing;
insert into public.services(id,name,category,description,price,type,icon,tone) values ('electrical','Electrical','Home care','Safe fixes for switches, wiring and fittings.',199,'fixed','💡','yellow') on conflict do nothing;
insert into public.services(id,name,category,description,price,type,icon,tone) values ('ac','AC service & repair','Home care','Keep your cool with a little professional care.',499,'fixed','❄️','lilac') on conflict do nothing;
insert into public.services(id,name,category,description,price,type,icon,tone) values ('painting','Painting','Home care','A new colour. A whole new feeling.',0,'quote','🎨','peach') on conflict do nothing;
insert into public.services(id,name,category,description,price,type,icon,tone) values ('carpentry','Carpentry','Home care','Thoughtful repairs and custom woodwork.',0,'quote','🧰','sand') on conflict do nothing;
insert into public.services(id,name,category,description,price,type,icon,tone) values ('taxi','Auto & taxi','Transport','Get where you need to be, with a local driver.',0,'transport','🚕','yellow') on conflict do nothing;
insert into public.services(id,name,category,description,price,type,icon,tone) values ('delivery','Pickup & delivery','Transport','A helping hand getting things from A to B.',0,'transport','📦','peach') on conflict do nothing;
insert into public.services(id,name,category,description,price,type,icon,tone) values ('lorry','Goods transport','Transport','Room for bigger things. Local goods transport.',0,'goods','🚚','blue') on conflict do nothing;
insert into public.services(id,name,category,description,price,type,icon,tone) values ('groceries','Grocery assistance','Daily needs','Help with your neighbourhood shopping list.',0,'transport','🛒','mint') on conflict do nothing;
insert into public.services(id,name,category,description,price,type,icon,tone) values ('laundry','Laundry & ironing','Daily needs','Fresh clothes, one less thing on your list.',0,'fixed','👕','lilac') on conflict do nothing;
insert into public.services(id,name,category,description,price,type,icon,tone) values ('carwash','Vehicle washing','Vehicle care','A little shine for your everyday ride.',399,'fixed','🚙','blue') on conflict do nothing;
insert into public.services(id,name,category,description,price,type,icon,tone) values ('roadside','Roadside assistance','Vehicle care','Request help from an available local technician.',0,'emergency','🔧','yellow') on conflict do nothing;
insert into public.services(id,name,category,description,price,type,icon,tone) values ('masonry','Masonry & tile work','Construction','Skilled hands for your next building project.',0,'quote','🧱','peach') on conflict do nothing;
insert into public.services(id,name,category,description,price,type,icon,tone) values ('equipment','Tools & equipment','Rentals','The right tools, for just as long as you need.',0,'rental','🧰','sand') on conflict do nothing;
insert into public.services(id,name,category,description,price,type,icon,tone) values ('events','Event equipment','Rentals','Chairs, tables and equipment for your gathering.',0,'rental','🎉','lilac') on conflict do nothing;
insert into public.services(id,name,category,description,price,type,icon,tone) values ('photography','Photography','Personal & events','Keep the moments that matter, beautifully.',0,'quote','📷','mint') on conflict do nothing;
insert into public.services(id,name,category,description,price,type,icon,tone) values ('computer','Computer repair','Personal & events','Get your everyday technology working again.',299,'fixed','💻','blue') on conflict do nothing;


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
   raise exception 'Enter a valid administrator email address.';
  end if;
  insert into private.admin_emails(email) values(admin_email) on conflict do nothing;
 end if;
end $setup_admin$;
commit;

select 'Local Mate database setup completed' as result,
 (select count(*) from public.services) as services,
 (select count(*) from public.locations) as locations,
 (select count(*) from private.admin_emails) as administrator_emails;
