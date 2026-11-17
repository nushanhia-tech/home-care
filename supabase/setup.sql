-- LOCAL MATE: COMPLETE SUPABASE SQL EDITOR SETUP
-- Generated from the checked-in migrations and starter catalogue.
-- Run this entire file in Supabase Dashboard > SQL Editor as the project owner.
-- The owner-selected legacy administrator is included by the bootstrap migration.
-- Username admin is provisioned at first sign-in after the server-only key is configured;
-- the initial password must be changed before administrator controls unlock.
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

-- Migration: 20261114000400_username_administration.sql
-- Username/password login uses Supabase Auth. Only trusted server credentials can manage login mappings.
alter table public.users add column if not exists username text;
alter table public.users add column if not exists is_active boolean not null default true;
create unique index if not exists users_username on public.users(lower(username)) where username is not null;
create table if not exists private.login_accounts (
 username text primary key check(username=lower(username) and username ~ '^[a-z0-9][a-z0-9_.-]{2,31}$'),
 user_id uuid not null unique references auth.users(id) on delete cascade,
 must_change_password boolean not null default false
);
create table if not exists private.initial_admin_bootstrap (singleton boolean primary key default true check(singleton),completed boolean not null default false);
insert into private.initial_admin_bootstrap(singleton) values(true) on conflict do nothing;
create table if not exists private.auth_attempts (bucket text primary key,attempts integer not null default 0,expires_at timestamptz not null);
create table if not exists public.website_configuration (
 id boolean primary key default true check(id),
 content jsonb not null default '{"site_name":"Local Mate","hero_line_1":"Your home.","hero_line_2":"Our people.","hero_line_3":"Consider it done.","hero_description":"From a leaky tap to a fresh coat of paint. Find a trusted helping hand, close to home.","tagline":"Your neighbourhood. Your trusted helpers.","announcement":"A little help, right around the corner.","contact_phone":"","contact_address":"Pattambi, Kerala, India"}',
 maintenance_mode boolean not null default false,customer_portal_enabled boolean not null default true,
 provider_portal_enabled boolean not null default true,registration_enabled boolean not null default true,
 bookings_enabled boolean not null default true,updated_at timestamptz not null default now()
);
insert into public.website_configuration(id) values(true) on conflict do nothing;
alter table public.website_configuration enable row level security;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='website_configuration' and policyname='website_configuration_read') then
  create policy website_configuration_read on public.website_configuration for select using(true);
 end if;
end $setup_policy$;
revoke all on public.website_configuration from anon,authenticated;
grant select on public.website_configuration to anon,authenticated;

create or replace function public.account_active() returns boolean language sql stable security definer set search_path='' as $$
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
create or replace function public.login_state() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('username',username,'must_change_password',must_change_password) from private.login_accounts where user_id=auth.uid()
$$;
create or replace function public.service_auth_attempt(p_key text,p_action text) returns void language plpgsql security definer set search_path='' as $$
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
create or replace function public.service_resolve_username(p_username text) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role()<>'service_role' then raise exception 'Server authorization required.' using errcode='42501';end if;
 return (select jsonb_build_object('user_id',u.id,'email',u.email,'must_change_password',l.must_change_password,'is_active',p.is_active)
 from private.login_accounts l join auth.users u on u.id=l.user_id join public.users p on p.id=u.id where l.username=lower(p_username));
end $$;
create or replace function public.service_bootstrap_state() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role()<>'service_role' then raise exception 'Server authorization required.' using errcode='42501';end if;
 return jsonb_build_object('completed',(select completed from private.initial_admin_bootstrap where singleton),
 'candidate_id',(select id from auth.users where email='admin@localmate.invalid' and raw_app_meta_data->>'local_mate_bootstrap'='true'));
end $$;
create or replace function public.service_finish_bootstrap(p_user uuid) returns void language plpgsql security definer set search_path='' as $$
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
create or replace function public.service_set_login(p_user uuid,p_username text,p_change_password boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.role()<>'service_role' then raise exception 'Server authorization required.' using errcode='42501';end if;
 perform 1 from public.website_configuration where id for share;
 if not p_change_password and not exists(select 1 from private.login_accounts where user_id=p_user) and exists(select 1 from public.website_configuration where id and(maintenance_mode or not registration_enabled)) then raise exception 'Registration is temporarily paused.';end if;
 insert into private.login_accounts(username,user_id,must_change_password) values(lower(p_username),p_user,p_change_password)
 on conflict(user_id) do update set username=excluded.username,must_change_password=excluded.must_change_password;
 update public.users set username=lower(p_username) where id=p_user;
end $$;
create or replace function public.admin_save_website(p_data jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 if coalesce(jsonb_typeof(p_data->'content'),'')<>'object' or length(p_data::text)>60000 then raise exception 'Invalid website settings.';end if;
 if exists(select 1 from jsonb_each(p_data->'content') field where jsonb_typeof(field.value)<>'string') then raise exception 'Website content fields must be text.';end if;
 update public.website_configuration set content=p_data->'content',maintenance_mode=coalesce((p_data->>'maintenance_mode')::boolean,false),
 customer_portal_enabled=coalesce((p_data->>'customer_portal_enabled')::boolean,true),provider_portal_enabled=coalesce((p_data->>'provider_portal_enabled')::boolean,true),
 registration_enabled=coalesce((p_data->>'registration_enabled')::boolean,true),bookings_enabled=coalesce((p_data->>'bookings_enabled')::boolean,true),updated_at=now() where id;
 perform private.audit('Update website and portal controls');
end $$;
create or replace function public.admin_save_location(p_name text,p_active boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 if length(trim(p_name)) not between 1 and 100 then raise exception 'Enter a location name.';end if;
 insert into public.locations(name,active) values(trim(p_name),p_active) on conflict(name) do update set active=excluded.active;
 perform private.audit('Save location',p_name);
end $$;
create or replace function public.admin_account_status(p_user uuid,p_active boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 if p_user=auth.uid() then raise exception 'Your current administrator account must stay active.';end if;
 update public.users set is_active=p_active where id=p_user;perform private.audit('Change account status',p_user::text);
end $$;
create or replace function public.export_marketplace() returns jsonb language plpgsql security definer set search_path='' as $$
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
create or replace function public.service_reset_marketplace(p_actor uuid,p_confirmation text) returns void language plpgsql security definer set search_path='' as $$
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
create or replace function public.service_reset_progress(p_actor uuid,p_note text) returns void language plpgsql security definer set search_path='' as $$
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
create or replace function private.enforce_portal_switches() returns trigger language plpgsql security definer set search_path='' as $$
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
create or replace function private.enforce_job_switches() returns trigger language plpgsql security definer set search_path='' as $$
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

-- Migration: 20261115000100_provider_directory_tracking.sql
-- Provider prices, explicit directory ratings, precise places, and private foreground GPS.
alter table public.provider_profiles add column if not exists publish_phone boolean not null default false;
alter table public.provider_profiles add column if not exists assessment_rating numeric(2,1) check(assessment_rating between 0 and 5);
alter table public.provider_profiles add column if not exists rating_source text not null default '' check(length(rating_source)<=200);
create table if not exists public.provider_offerings (
 provider_id uuid references public.provider_profiles(user_id) on delete cascade,
 service_id text references public.services(id) on delete cascade,
 price integer check(price>=0), pricing_unit text not null default 'quote' check(pricing_unit in ('visit','hour','day','quote')),
 primary key(provider_id,service_id),check(pricing_unit='quote' or price is not null)
);
insert into public.provider_offerings(provider_id,service_id)
 select p.user_id,s.id from public.provider_profiles p join public.services s on s.id=any(p.service_ids) on conflict do nothing;
alter table public.provider_offerings enable row level security;
drop policy if exists offerings_owner on public.provider_offerings;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='provider_offerings' and policyname='offerings_owner') then
  create policy offerings_owner on public.provider_offerings for select to authenticated using(public.account_active() and(provider_id=auth.uid() or public.is_admin()));
 end if;
end $setup_policy$;
revoke all on public.provider_offerings from anon,authenticated;
grant select on public.provider_offerings to authenticated;
alter table public.addresses add column if not exists latitude double precision check(latitude between -90 and 90);
alter table public.addresses add column if not exists longitude double precision check(longitude between -180 and 180);
alter table public.bookings add column if not exists requested_provider_id uuid references public.provider_profiles(user_id) on delete set null;
alter table public.bookings add column if not exists requires_quote boolean not null default false;
alter table public.bookings add column if not exists latitude double precision check(latitude between -90 and 90);
alter table public.bookings add column if not exists longitude double precision check(longitude between -180 and 180);
alter table public.bookings add column if not exists destination_latitude double precision check(destination_latitude between -90 and 90);
alter table public.bookings add column if not exists destination_longitude double precision check(destination_longitude between -180 and 180);

create or replace function public.provider_directory() returns setof jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',p.user_id,'name',u.name,'business_name',p.business_name,'category',p.category,'description',p.description,'experience',p.experience,'service_ids',p.service_ids,'locations',p.locations,'online',p.online,
 'phone',case when p.publish_phone then u.phone else null end,'assessment_rating',p.assessment_rating,'rating_source',p.rating_source,
 'rating',(select avg(r.rating) from public.reviews r where r.provider_id=p.user_id),'review_count',(select count(*) from public.reviews r where r.provider_id=p.user_id),
 'offerings',coalesce((select jsonb_agg(to_jsonb(o)-'provider_id') from public.provider_offerings o join public.services s on s.id=o.service_id and s.active where o.provider_id=p.user_id),'[]'::jsonb))
 from public.provider_profiles p join public.users u on u.id=p.user_id cross join public.website_configuration cfg
 where p.status='approved' and u.is_active and cfg.id and not cfg.maintenance_mode and cfg.provider_portal_enabled order by p.business_name,u.name;
$$;
create or replace function public.admin_provider_directory() returns setof jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 return query select to_jsonb(p)||jsonb_build_object('name',u.name,'username',u.username,'phone',u.phone,'is_active',u.is_active,
 'offerings',coalesce((select jsonb_agg(to_jsonb(o)-'provider_id') from public.provider_offerings o where o.provider_id=p.user_id),'[]'::jsonb))
 from public.provider_profiles p join public.users u on u.id=p.user_id order by p.created_at desc;
end $$;
create or replace function public.save_provider(p_data jsonb,p_user uuid default null) returns void language plpgsql security definer set search_path='' as $$
declare target uuid:=coalesce(p_user,auth.uid()); p public.provider_profiles; item jsonb; areas text[]; ids text[];
begin
 perform private.take_rate_limit();
 if p_user is not null and not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 select * into p from public.provider_profiles where user_id=target for update;
 if p.user_id is null and not public.is_admin() then raise exception 'Submit a provider application first.';end if;
 if not exists(select 1 from public.users where id=target and is_active) then raise exception 'Choose an active account.';end if;
 if length(trim(coalesce(p_data->>'name',''))) not between 1 and 100 or coalesce(p_data->>'phone','') !~ '^(\+91)?[6-9][0-9]{9}$' then raise exception 'Enter a name and valid Indian mobile number.';end if;
 if length(trim(coalesce(p_data->>'description',''))) not between 1 and 2000 or length(coalesce(p_data->>'business_name',''))>100 or length(coalesce(p_data->>'category','')) not between 1 and 100 then raise exception 'Enter your business category and description.';end if;
 if jsonb_typeof(p_data->'offerings')<>'array' or jsonb_array_length(p_data->'offerings') not between 1 and 100 then raise exception 'Choose at least one service and its price.';end if;
 select array_agg(distinct value) into areas from jsonb_array_elements_text(p_data->'locations');
 if coalesce(array_length(areas,1),0)=0 or exists(select 1 from unnest(areas) a where not exists(select 1 from public.locations l where l.name=a and l.active)) then raise exception 'Choose supported service areas.';end if;
 select array_agg(distinct value->>'service_id') into ids from jsonb_array_elements(p_data->'offerings');
 if coalesce(array_length(ids,1),0)=0 or exists(select 1 from unnest(ids) i where not exists(select 1 from public.services s where s.id=i and s.active)) then raise exception 'Choose active services.';end if;
 update public.users set name=trim(p_data->>'name'),phone=p_data->>'phone' where id=target;
 insert into public.provider_profiles(user_id,business_name,category,service_ids,locations,description,experience,status,online,publish_phone)
 values(target,coalesce(p_data->>'business_name',''),p_data->>'category',ids,areas,trim(p_data->>'description'),coalesce((p_data->>'experience')::int,0),'pending',false,coalesce((p_data->>'publish_phone')::boolean,false))
 on conflict(user_id) do update set business_name=excluded.business_name,category=excluded.category,service_ids=excluded.service_ids,locations=excluded.locations,description=excluded.description,experience=excluded.experience,publish_phone=excluded.publish_phone;
 delete from public.provider_offerings where provider_id=target;
 for item in select value from jsonb_array_elements(p_data->'offerings') loop
  insert into public.provider_offerings(provider_id,service_id,price,pricing_unit) values(target,item->>'service_id',nullif(item->>'price','')::int,coalesce(item->>'pricing_unit','quote'));
 end loop;
 if public.is_admin() then
  if p_data->>'status' not in ('pending','approved','rejected','suspended') then raise exception 'Choose an approval status.';end if;
  if nullif(p_data->>'assessment_rating','') is not null and length(trim(coalesce(p_data->>'rating_source','')))=0 then raise exception 'Add the source or basis of this assessment rating.';end if;
  update public.provider_profiles set status=p_data->>'status',online=case when p_data->>'status'='approved' then coalesce((p_data->>'online')::boolean,false) else false end,
   assessment_rating=nullif(p_data->>'assessment_rating','')::numeric,rating_source=coalesce(p_data->>'rating_source','') where user_id=target;
  perform private.audit('Save provider and prices',target::text);
 end if;
end $$;

-- Only booking participants receive private contact details, never unassigned candidates.
create or replace function public.booking_contacts(p_booking uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare b public.bookings;
begin
 if not public.account_active() or not public.can_message_booking(p_booking) then raise exception 'This contact is private.' using errcode='42501';end if;
 select * into b from public.bookings where id=p_booking;
 return jsonb_build_object('customer',(select jsonb_build_object('name',name,'phone',phone) from public.users where id=b.customer_id),
 'provider',(select jsonb_build_object('name',name,'phone',phone) from public.users where id=b.provider_id));
end $$;
create table if not exists public.booking_locations (
 booking_id uuid primary key references public.bookings(id) on delete cascade,
 provider_id uuid not null references public.provider_profiles(user_id) on delete cascade,
 latitude double precision not null check(latitude between -90 and 90),longitude double precision not null check(longitude between -180 and 180),
 accuracy double precision not null check(accuracy>=0 and accuracy<=100000),recorded_at timestamptz not null default now()
);
alter table public.booking_locations enable row level security;
revoke all on public.booking_locations from anon,authenticated;
-- GPS has a separate throttle: normal booking/chat write limits must not be consumed by GPS.
create table if not exists private.booking_gps_sessions (
 booking_id uuid primary key references public.bookings(id) on delete cascade,
 session_id uuid not null,provider_id uuid not null references public.provider_profiles(user_id) on delete cascade
);
revoke all on private.booking_gps_sessions from public,anon,authenticated;
create or replace function public.share_booking_location(p_booking uuid,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.bookings; previous public.booking_locations; session_uuid uuid:=nullif(p_data->>'session_id','')::uuid;
begin
 if not public.account_active() then raise exception 'Sign in with an active account.' using errcode='42501';end if;
 select * into b from public.bookings where id=p_booking for share;
 if b.provider_id is distinct from auth.uid() then raise exception 'Only the assigned provider can share GPS.' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('booking-gps:'||p_booking::text,0));
 if coalesce((p_data->>'stop')::boolean,false) then
  if exists(select 1 from private.booking_gps_sessions where booking_id=p_booking and session_id=session_uuid and provider_id=auth.uid()) then
   delete from public.booking_locations where booking_id=p_booking;
   delete from private.booking_gps_sessions where booking_id=p_booking;
  end if;return jsonb_build_object('ok',true);
 end if;
 if b.status not in ('confirmed','on_the_way','arrived','work_started','work_paused') then raise exception 'GPS sharing requires an active assigned job.';end if;
 if exists(select 1 from public.website_configuration where id and(maintenance_mode or not provider_portal_enabled)) then raise exception 'GPS sharing is temporarily paused.';end if;
 if not coalesce((p_data->>'consent')::boolean,false) then raise exception 'Choose to share your location first.';end if;
 if session_uuid is null then raise exception 'Start a GPS sharing session first.';end if;
 if coalesce((p_data->>'start')::boolean,false) then
  perform private.take_rate_limit();
  insert into private.booking_gps_sessions(booking_id,session_id,provider_id) values(p_booking,session_uuid,auth.uid())
   on conflict(booking_id) do update set session_id=excluded.session_id,provider_id=excluded.provider_id;
  delete from public.booking_locations where booking_id=p_booking;
  return jsonb_build_object('ok',true);
 end if;
 if not exists(select 1 from private.booking_gps_sessions where booking_id=p_booking and session_id=session_uuid and provider_id=auth.uid()) then raise exception 'GPS sharing has stopped. Start it again to continue.';end if;
 if p_data->>'latitude' is null or p_data->>'longitude' is null or p_data->>'accuracy' is null then raise exception 'A real GPS position is required.';end if;
 select * into previous from public.booking_locations where booking_id=p_booking;
 if previous.recorded_at>now()-interval '8 seconds' then return jsonb_build_object('ok',true);end if;
 insert into public.booking_locations(booking_id,provider_id,latitude,longitude,accuracy)
 values(p_booking,auth.uid(),(p_data->>'latitude')::double precision,(p_data->>'longitude')::double precision,(p_data->>'accuracy')::double precision)
 on conflict(booking_id) do update set provider_id=excluded.provider_id,latitude=excluded.latitude,longitude=excluded.longitude,accuracy=excluded.accuracy,recorded_at=now();
 return jsonb_build_object('ok',true);
end $$;
create or replace function public.booking_tracking(p_booking uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.account_active() or not public.can_message_booking(p_booking) then raise exception 'This GPS position is private.' using errcode='42501';end if;
 if exists(select 1 from public.website_configuration where id and(maintenance_mode or not provider_portal_enabled)) then return null;end if;
 return (select to_jsonb(l) from public.booking_locations l join public.bookings b on b.id=l.booking_id join public.users u on u.id=l.provider_id
 where l.booking_id=p_booking and l.provider_id=b.provider_id and u.is_active and b.status in ('confirmed','on_the_way','arrived','work_started','work_paused') and l.recorded_at>now()-interval '2 minutes');
end $$;
create or replace function private.booking_location_cleanup() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status in ('cancelled','work_completed','disputed') or new.provider_id is distinct from old.provider_id then delete from public.booking_locations where booking_id=new.id;delete from private.booking_gps_sessions where booking_id=new.id;end if;
 return new;
end $$;
drop trigger if exists booking_location_cleanup on public.bookings;
create trigger booking_location_cleanup after update on public.bookings for each row execute function private.booking_location_cleanup();

-- A selected provider controls who receives the initial request. Other customers cannot see it.
create or replace function public.can_view_booking(p_booking uuid) returns boolean language sql stable security definer set search_path='' as $$
 select public.account_active() and exists(select 1 from public.bookings b where b.id=p_booking and(public.is_admin() or b.customer_id=auth.uid() or b.provider_id=auth.uid() or(b.provider_id is null and b.status='requested' and(b.requested_provider_id is null or b.requested_provider_id=auth.uid()) and public.provider_eligible(auth.uid(),b.service_id,b.location) and not exists(select 1 from public.booking_rejections r where r.booking_id=b.id and r.provider_id=auth.uid()))))
$$;
create or replace function private.validate_booking_places() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.provider_id=new.customer_id and(tg_op='INSERT' or new.provider_id is distinct from old.provider_id) then raise exception 'A provider cannot accept their own booking.';end if;
 if (new.latitude is null)<>(new.longitude is null) or(new.destination_latitude is null)<>(new.destination_longitude is null) then raise exception 'Choose both latitude and longitude for each place.';end if;
 if tg_op='UPDATE' and new.status='requested' and old.provider_id is not null and new.provider_id is null then new.requested_provider_id:=null;end if;
 if new.requires_quote and new.status='confirmed' and not exists(select 1 from public.quotations where booking_id=new.id and provider_id=new.provider_id and status='approved') then raise exception 'Send a quotation and obtain customer approval before confirmation.';end if;
 return new;
end $$;
drop trigger if exists validate_booking_places on public.bookings;
create trigger validate_booking_places before insert or update on public.bookings for each row execute function private.validate_booking_places();
create or replace function private.release_declined_provider() returns trigger language plpgsql security definer set search_path='' as $$
declare b public.bookings;candidate uuid;
begin
 select * into b from public.bookings where id=new.booking_id for update;
 if b.requested_provider_id=new.provider_id then
  update public.bookings set requested_provider_id=null,requires_quote=true where id=b.id;
  perform private.notify(b.customer_id,'Your chosen provider declined. Your request is now open to other eligible providers.',b.id);
  for candidate in select user_id from public.provider_profiles where user_id<>new.provider_id and public.provider_eligible(user_id,b.service_id,b.location) loop perform private.notify(candidate,'A service request is available in '||b.location,b.id);end loop;
 end if;return new;
end $$;
drop trigger if exists release_declined_provider on public.booking_rejections;
create trigger release_declined_provider after insert on public.booking_rejections for each row execute function private.release_declined_provider();

revoke execute on function public.provider_directory(),public.admin_provider_directory(),public.save_provider(jsonb,uuid),public.booking_contacts(uuid),public.share_booking_location(uuid,jsonb),public.booking_tracking(uuid) from public,anon,authenticated;
grant execute on function public.provider_directory() to anon,authenticated;
grant execute on function public.admin_provider_directory(),public.save_provider(jsonb,uuid),public.booking_contacts(uuid),public.share_booking_location(uuid,jsonb),public.booking_tracking(uuid) to authenticated;
revoke execute on function private.booking_location_cleanup(),private.validate_booking_places(),private.release_declined_provider() from public,anon,authenticated;

create or replace function public.create_booking(p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare s public.services; b_id uuid; candidate uuid; scheduled timestamptz; chosen uuid; offer public.provider_offerings; needs_quote boolean;
begin
 perform private.take_rate_limit();
 select id into b_id from public.bookings where customer_id=auth.uid() and idempotency_key=(p_data->>'idempotency_key')::uuid;
 if b_id is not null then return b_id;end if;
 select * into s from public.services where id=p_data->>'service_id' and active;
 if s.id is null then raise exception 'This service is not available.';end if;
 if not exists(select 1 from public.locations where name=p_data->>'location' and active) then raise exception 'Choose a supported location.';end if;
 chosen:=nullif(p_data->>'provider_id','')::uuid;
 if chosen=auth.uid() then raise exception 'Choose another provider for your own booking.';end if;
 if chosen is not null and not public.provider_eligible(chosen,s.id,p_data->>'location') then raise exception 'This provider is not available for this service and area.';end if;
 select * into offer from public.provider_offerings where provider_id=chosen and service_id=s.id;
 needs_quote:=s.type='quote' or (chosen is not null and (offer.provider_id is null or offer.pricing_unit<>'visit'));
 scheduled:=(p_data->>'scheduled_at')::timestamptz;
 if scheduled is null or scheduled<=now() then raise exception 'Choose a future date and time.';end if;
 if length(trim(coalesce(p_data->>'address',''))) not between 1 and 1000 or length(trim(coalesce(p_data->>'description',''))) not between 1 and 4000 then raise exception 'Enter your address and job details.';end if;
 if p_data->>'payment_method'<>'cash' then raise exception 'Choose pay after service.';end if;
 if s.type in ('transport','goods') and coalesce(p_data->'details'->>'destination','')='' then raise exception 'Enter your destination.';end if;
 if s.type='rental' and (coalesce(p_data->'details'->>'end_date','')='' or (p_data->'details'->>'end_date')::timestamptz<scheduled) then raise exception 'Choose a valid rental end date.';end if;
 if not exists(select 1 from public.provider_profiles p where p.user_id<>auth.uid() and public.provider_eligible(p.user_id,s.id,p_data->>'location')) then raise exception 'No approved, online provider is available for this service in your town yet.';end if;
 insert into public.bookings(customer_id,service_id,location,address,scheduled_at,description,details,estimated_price,idempotency_key,requested_provider_id,requires_quote,latitude,longitude,destination_latitude,destination_longitude)
 values(auth.uid(),s.id,p_data->>'location',trim(p_data->>'address'),scheduled,trim(p_data->>'description'),coalesce(p_data->'details','{}'),coalesce(offer.price,s.price),(p_data->>'idempotency_key')::uuid,chosen,needs_quote,nullif(p_data->>'latitude','')::double precision,nullif(p_data->>'longitude','')::double precision,nullif(p_data->>'destination_latitude','')::double precision,nullif(p_data->>'destination_longitude','')::double precision)
 on conflict(customer_id,idempotency_key) do nothing returning id into b_id;
 if b_id is null then select id into b_id from public.bookings where customer_id=auth.uid() and idempotency_key=(p_data->>'idempotency_key')::uuid;return b_id;end if;
 perform private.record_history(b_id,'requested');perform private.notify(auth.uid(),'Your booking request has been created',b_id);
 for candidate in select user_id from public.provider_profiles where user_id<>auth.uid() and (chosen is null or user_id=chosen) and public.provider_eligible(user_id,s.id,p_data->>'location') loop perform private.notify(candidate,'New '||s.name||' request in '||(p_data->>'location'),b_id);end loop;
 return b_id;
end $$;

create or replace function public.list_bookings(p_role text default 'customer') returns setof jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Please sign in.' using errcode='42501';end if;
 if p_role='admin' and not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 return query select to_jsonb(b)||jsonb_build_object('service_name',s.name,'customer_name',c.name,'provider_name',p.name)
 from public.bookings b join public.services s on s.id=b.service_id join public.users c on c.id=b.customer_id left join public.users p on p.id=b.provider_id
 where case p_role when 'admin' then public.is_admin() when 'provider' then b.provider_id=auth.uid() or (b.provider_id is null and b.customer_id<>auth.uid() and b.status='requested' and (b.requested_provider_id is null or b.requested_provider_id=auth.uid()) and public.provider_eligible(auth.uid(),b.service_id,b.location) and not exists(select 1 from public.booking_rejections r where r.booking_id=b.id and r.provider_id=auth.uid())) else b.customer_id=auth.uid() end
 order by b.created_at desc;
end $$;

create or replace function public.admin_assign(p_booking uuid,p_provider uuid) returns void language plpgsql security definer set search_path='' as $$
declare b public.bookings;kind text;new_status text; offer public.provider_offerings; needs_quote boolean;
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 select * into b from public.bookings where id=p_booking for update;
 if p_provider=b.customer_id then raise exception 'A provider cannot be assigned their own booking.';end if;
 if b.id is null or b.status not in ('requested','confirmed','quote_sent') or not public.provider_eligible(p_provider,b.service_id,b.location) then raise exception 'Choose an available, approved provider matching this service and area.';end if;
 select type into kind from public.services where id=b.service_id;
 select * into offer from public.provider_offerings where provider_id=p_provider and service_id=b.service_id;
 needs_quote:=kind='quote' or offer.provider_id is null or offer.pricing_unit<>'visit';
 new_status:=case when needs_quote then 'requested' else 'confirmed' end;
 update public.quotations set status='rejected' where booking_id=b.id and status='pending';
 update public.bookings set provider_id=p_provider,requested_provider_id=p_provider,requires_quote=needs_quote,estimated_price=coalesce(offer.price,b.estimated_price),status=new_status where id=b.id;
 perform private.record_history(b.id,new_status,'Assigned by administrator');perform private.audit('Assign booking',b.id::text);
 perform private.notify(p_provider,'A booking has been assigned to you',b.id);perform private.notify(b.customer_id,'Your booking has been assigned',b.id);
end $$;

create or replace function public.export_marketplace() returns jsonb language plpgsql security definer set search_path='' as $$
declare table_name text;data jsonb;all_data jsonb:='{}';
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 perform private.audit('Download application data backup');
 foreach table_name in array array['users','provider_profiles','provider_offerings','locations','services','addresses','bookings','booking_status_history','booking_rejections','quotations','messages','notifications','reviews','payments','support_tickets','favourites','settings','website_configuration','admin_activity_logs'] loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb) from public.%I t',table_name) into data;
  all_data:=all_data||jsonb_build_object(table_name,data);
 end loop;
 return jsonb_build_object('format','local-mate-application-backup','version',2,'created_at',now(),'tables',all_data,
 'scope','Application records only. Auth passwords, sessions, uploaded files, live GPS positions, and project secrets are not included.');
end $$;

notify pgrst, 'reload schema';

-- Manage the real provider membership behind service counts.
create or replace function public.admin_service_provider(p_provider uuid,p_service text,p_enabled boolean,p_price integer default null,p_unit text default 'quote') returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 perform 1 from public.provider_profiles where user_id=p_provider for update;
 if not found or not exists(select 1 from public.services where id=p_service and active) then raise exception 'Choose a provider and active service.';end if;
 if p_enabled then
  insert into public.provider_offerings(provider_id,service_id,price,pricing_unit) values(p_provider,p_service,p_price,p_unit)
  on conflict(provider_id,service_id) do update set price=excluded.price,pricing_unit=excluded.pricing_unit;
  update public.provider_profiles set service_ids=(select array_agg(distinct s) from unnest(service_ids||array[p_service]) s) where user_id=p_provider;
 else
  if (select array_length(service_ids,1) from public.provider_profiles where user_id=p_provider)<=1 then raise exception 'Keep at least one service or suspend this provider.';end if;
  delete from public.provider_offerings where provider_id=p_provider and service_id=p_service;
  update public.provider_profiles set service_ids=array_remove(service_ids,p_service) where user_id=p_provider;
 end if;
 perform private.audit('Update service provider',p_service||':'||p_provider::text);
end $$;
create or replace function public.admin_provider_area(p_provider uuid,p_location text,p_enabled boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 perform 1 from public.provider_profiles where user_id=p_provider for update;
 if not found or not exists(select 1 from public.locations where name=p_location and active) then raise exception 'Choose a provider and active location.';end if;
 if p_enabled then update public.provider_profiles set locations=(select array_agg(distinct l) from unnest(locations||array[p_location]) l) where user_id=p_provider;
 else
  if (select array_length(locations,1) from public.provider_profiles where user_id=p_provider)<=1 then raise exception 'Keep at least one service area or suspend this provider.';end if;
  update public.provider_profiles set locations=array_remove(locations,p_location) where user_id=p_provider;
 end if;
 perform private.audit('Update provider service area',p_location||':'||p_provider::text);
end $$;
do $$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.addresses'::regclass and conname='address_coordinate_pair') then
  alter table public.addresses add constraint address_coordinate_pair check((latitude is null)=(longitude is null));
 end if;
end $$;
revoke execute on function public.admin_service_provider(uuid,text,boolean,integer,text),public.admin_provider_area(uuid,text,boolean) from public,anon;
grant execute on function public.admin_service_provider(uuid,text,boolean,integer,text),public.admin_provider_area(uuid,text,boolean) to authenticated;
notify pgrst, 'reload schema';

do $$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.reviews'::regclass and conname='no_self_reviews') then
  alter table public.reviews add constraint no_self_reviews check(customer_id<>provider_id) not valid;
 end if;
end $$;
-- A pause or account suspension ends active sharing sessions immediately.
create or replace function private.stop_disabled_gps() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='website_configuration' then
  if new.maintenance_mode or not new.provider_portal_enabled then delete from public.booking_locations;delete from private.booking_gps_sessions;end if;
 elsif not new.is_active then
  delete from public.booking_locations where provider_id=new.id;
  delete from private.booking_gps_sessions where provider_id=new.id;
 end if;return new;
end $$;
drop trigger if exists pause_gps on public.website_configuration;
create trigger pause_gps after update on public.website_configuration for each row execute function private.stop_disabled_gps();
drop trigger if exists suspend_provider_gps on public.users;
create trigger suspend_provider_gps after update of is_active on public.users for each row execute function private.stop_disabled_gps();
revoke execute on function private.stop_disabled_gps() from public,anon,authenticated;
notify pgrst, 'reload schema';

-- Migration: 20261116000100_operations_foundation.sql
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
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='booking_events' and policyname='events_read') then
  create policy events_read on public.booking_events for select to authenticated using(public.account_active() and(public.can_view_booking(booking_id) or public.was_offered_booking(booking_id)));
 end if;
end $setup_policy$;
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

-- Migration: 20261116000200_financial_records.sql
-- Money is stored in integer paise, with immutable rate snapshots and verified payments.
create table if not exists public.provider_commission_rules(id uuid primary key default gen_random_uuid(),provider_id uuid references public.provider_profiles(user_id) on delete cascade,category text,percent numeric(5,2) not null check(percent between 0 and 100),fixed_paise bigint not null default 0 check(fixed_paise>=0),active boolean not null default true,check((provider_id is not null)<>(category is not null)));
create unique index if not exists one_provider_commission_rule on public.provider_commission_rules(provider_id) where provider_id is not null;
create unique index if not exists one_category_commission_rule on public.provider_commission_rules(category) where category is not null;
create table if not exists public.weekly_commission_periods(id uuid primary key default gen_random_uuid(),starts_at timestamptz not null,ends_at timestamptz not null,timezone text not null,deadline_at timestamptz not null,grace_until timestamptz not null,check(ends_at>starts_at),unique(starts_at,ends_at,timezone));
create table if not exists public.job_start_verifications(booking_id uuid primary key references public.bookings(id) on delete cascade,provider_id uuid not null references public.provider_profiles(user_id),verified_at timestamptz not null default now(),method text not null check(method in ('otp','admin_exception')),actor_id uuid not null references public.users(id),reason text not null default '');
create table if not exists private.job_start_otps(id uuid primary key default gen_random_uuid(),booking_id uuid not null references public.bookings(id) on delete cascade,provider_id uuid not null references public.provider_profiles(user_id),code_hash text not null,ciphertext text not null,expires_at timestamptz not null,attempts integer not null default 0,used_at timestamptz,created_at timestamptz not null default now());
create index if not exists job_otps_booking on private.job_start_otps(booking_id,created_at desc);
create table if not exists public.job_start_otp_logs(id bigint generated always as identity primary key,booking_id uuid not null references public.bookings(id) on delete cascade,provider_id uuid references public.provider_profiles(user_id),actor_id uuid references public.users(id),event text not null,created_at timestamptz not null default now());
create table if not exists public.booking_charge_requests(id uuid primary key default gen_random_uuid(),booking_id uuid not null references public.bookings(id) on delete cascade,provider_id uuid not null references public.provider_profiles(user_id),amount_paise bigint not null check(amount_paise>0 and amount_paise<=1000000000),description text not null check(length(description) between 1 and 1000),status text not null default 'pending' check(status in ('pending','approved','rejected','disputed')),created_at timestamptz not null default now(),responded_at timestamptz);
create table if not exists public.job_bills(id uuid primary key default gen_random_uuid(),booking_id uuid not null references public.bookings(id) on delete cascade,provider_id uuid not null references public.provider_profiles(user_id),revision integer not null default 1,labour_paise bigint not null check(labour_paise>=0),materials_paise bigint not null check(materials_paise>=0),additional_paise bigint not null check(additional_paise>=0),discount_paise bigint not null check(discount_paise>=0),tax_paise bigint not null check(tax_paise>=0),total_paise bigint not null check(total_paise>=0),tax_percent numeric(5,2) not null default 0,description text not null,status text not null default 'submitted' check(status in ('submitted','confirmed','disputed','void')),created_at timestamptz not null default now(),confirmed_at timestamptz,dispute_reason text,unique(booking_id,revision));
create unique index if not exists one_current_bill on public.job_bills(booking_id) where status<>'void';
create table if not exists public.job_completion_records(booking_id uuid primary key references public.bookings(id) on delete cascade,provider_id uuid not null references public.provider_profiles(user_id),completed_at timestamptz not null default now(),description text not null);
create sequence if not exists public.invoice_number_seq;
create table if not exists public.invoices(id uuid primary key default gen_random_uuid(),bill_id uuid not null unique references public.job_bills(id) on delete cascade,booking_id uuid not null references public.bookings(id) on delete cascade,number text not null unique default('LM-'||to_char(now(),'YYYY')||'-'||lpad(nextval('public.invoice_number_seq')::text,7,'0')),snapshot jsonb not null,status text not null default 'issued' check(status in ('issued','void')),issued_at timestamptz not null default now());
create table if not exists public.invoice_items(id bigint generated always as identity primary key,invoice_id uuid not null references public.invoices(id) on delete cascade,label text not null,amount_paise bigint not null);
create table if not exists public.provider_commissions(id uuid primary key default gen_random_uuid(),booking_id uuid not null unique references public.bookings(id) on delete cascade,bill_id uuid not null references public.job_bills(id) on delete cascade,provider_id uuid not null references public.provider_profiles(user_id),period_id uuid not null references public.weekly_commission_periods(id),billable_paise bigint not null check(billable_paise>=0),rate_percent numeric(5,2) not null,fixed_paise bigint not null default 0,commission_paise bigint not null check(commission_paise>=0),rule_snapshot jsonb not null,status text not null default 'due' check(status in ('due','held','void')),created_at timestamptz not null default now());
create table if not exists public.provider_commission_payments(id uuid primary key default gen_random_uuid(),provider_id uuid not null references public.provider_profiles(user_id),period_id uuid not null references public.weekly_commission_periods(id),amount_paise bigint not null check(amount_paise>0),method text not null,reference text not null,paid_at timestamptz not null,proof_id uuid not null references public.media_assets(id),status text not null default 'awaiting_verification' check(status in ('awaiting_verification','approved','rejected')),submitted_at timestamptz not null default now(),reviewed_at timestamptz,reviewed_by uuid references public.users(id),review_note text not null default '',unique(provider_id,reference));
create table if not exists public.provider_suspension_records(id uuid primary key default gen_random_uuid(),provider_id uuid not null references public.provider_profiles(user_id) on delete cascade,reason text not null default 'commission_payment_pending',amount_paise bigint not null,created_at timestamptz not null default now(),resolved_at timestamptz);
create unique index if not exists one_commission_suspension on public.provider_suspension_records(provider_id) where resolved_at is null;
create table if not exists public.provider_reactivation_records(id bigint generated always as identity primary key,provider_id uuid not null references public.provider_profiles(user_id) on delete cascade,suspension_id uuid references public.provider_suspension_records(id) on delete cascade,created_at timestamptz not null default now(),reason text not null);
create table if not exists public.provider_account_status_history(id bigint generated always as identity primary key,provider_id uuid not null references public.provider_profiles(user_id) on delete cascade,status text not null,reason text not null,actor_id uuid references public.users(id),created_at timestamptz not null default now());
create table if not exists public.financial_audit_logs(id bigint generated always as identity primary key,actor_id uuid references public.users(id),booking_id uuid references public.bookings(id) on delete cascade,event text not null,details jsonb not null default '{}',created_at timestamptz not null default now());
create table if not exists public.cash_payment_verifications(id uuid primary key default gen_random_uuid(),booking_id uuid not null unique references public.bookings(id) on delete cascade,amount_paise bigint not null,reference text not null,verified_by uuid not null references public.users(id),verified_at timestamptz not null default now());
-- RLS and no direct browser writes/reads: curated RPCs below are the only interfaces.
do $$ declare t text;begin
 foreach t in array array['provider_commission_rules','weekly_commission_periods','job_start_verifications','job_start_otp_logs','booking_charge_requests','job_bills','job_completion_records','invoices','invoice_items','provider_commissions','provider_commission_payments','provider_suspension_records','provider_reactivation_records','provider_account_status_history','financial_audit_logs','cash_payment_verifications'] loop
  execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from anon,authenticated',t);
 end loop;
end $$;
revoke all on private.job_start_otps from public,anon,authenticated;
create or replace function private.financial_audit(p_event text,p_booking uuid default null,p_details jsonb default '{}',p_actor uuid default auth.uid()) returns void language sql security definer set search_path='' as $$ insert into public.financial_audit_logs(actor_id,booking_id,event,details) values(p_actor,p_booking,p_event,p_details) $$;
create or replace function private.commission_statements(p_provider uuid default null) returns setof jsonb language sql stable security definer set search_path='' as $$
 with amounts as(
  select c.provider_id,c.period_id,count(*) filter(where c.status<>'void') jobs,coalesce(sum(c.billable_paise) filter(where c.status<>'void'),0) billable,
   coalesce(sum(c.commission_paise) filter(where c.status='due'),0) due,coalesce(sum(c.commission_paise) filter(where c.status='held'),0) held,
   jsonb_agg(jsonb_build_object('booking_id',c.booking_id,'billable_paise',c.billable_paise,'commission_paise',c.commission_paise,'rate_percent',c.rate_percent,'fixed_paise',c.fixed_paise,'status',c.status)) entries
  from public.provider_commissions c where p_provider is null or c.provider_id=p_provider group by c.provider_id,c.period_id
 ),paid as(select provider_id,period_id,coalesce(sum(amount_paise) filter(where status='approved'),0) paid,bool_or(status='awaiting_verification') awaiting,bool_or(status='rejected') rejected from public.provider_commission_payments group by provider_id,period_id)
 select jsonb_build_object('provider_id',a.provider_id,'provider_name',private.safe_text(coalesce(nullif(pr.business_name,''),u.name)),'period_id',w.id,'starts_at',w.starts_at,'ends_at',w.ends_at,'deadline_at',case when private.ops()->>'payment_ready_at' is null then w.deadline_at else greatest(w.deadline_at,(private.ops()->>'payment_ready_at')::timestamptz+make_interval(days=>(private.ops()->>'deadline_days')::int)) end,'grace_until',case when private.ops()->>'payment_ready_at' is null then w.grace_until else greatest(w.grace_until,(private.ops()->>'payment_ready_at')::timestamptz+make_interval(days=>(private.ops()->>'deadline_days')::int,hours=>(private.ops()->>'grace_hours')::int)) end,'jobs',a.jobs,'billable_paise',a.billable,'commission_paise',a.due,'held_paise',a.held,'paid_paise',coalesce(p.paid,0),'outstanding_paise',greatest(0,a.due-coalesce(p.paid,0)),'entries',a.entries,
 'status',case when a.due=0 and a.held=0 then 'no_commission_due' when a.due<=coalesce(p.paid,0) and a.held=0 then 'paid' when coalesce(p.awaiting,false) then 'awaiting_verification' when greatest(0,a.due-coalesce(p.paid,0))>0 and (case when private.ops()->>'payment_ready_at' is null then w.grace_until else greatest(w.grace_until,(private.ops()->>'payment_ready_at')::timestamptz+make_interval(days=>(private.ops()->>'deadline_days')::int,hours=>(private.ops()->>'grace_hours')::int)) end)<now() then 'overdue' when coalesce(p.rejected,false) then 'rejected' when a.held>0 and a.due<=coalesce(p.paid,0) then 'disputed' else 'unpaid' end)
 from amounts a join public.weekly_commission_periods w on w.id=a.period_id join public.provider_profiles pr on pr.user_id=a.provider_id join public.users u on u.id=a.provider_id left join paid p on p.provider_id=a.provider_id and p.period_id=a.period_id order by w.starts_at desc;
$$;
create or replace function private.commission_overdue(p_provider uuid) returns bigint language sql stable security definer set search_path='' as $$
 select case when coalesce((private.ops()->>'auto_suspend')::boolean,false) and length(trim(private.ops()->>'payment_instructions'))>0 then
 coalesce((select sum((s->>'outstanding_paise')::bigint) from private.commission_statements(p_provider) s where(s->>'grace_until')::timestamptz<now()),0) else 0 end
$$;
create or replace function private.commission_blocked(p_provider uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.commission_overdue(p_provider)>0 and private.commission_overdue(p_provider)>=coalesce((private.ops()->>'minimum_commission_paise')::bigint,0)
$$;
create or replace function private.reconcile_provider(p_provider uuid) returns void language plpgsql security definer set search_path='' as $$
declare debt bigint; row_id uuid;
begin
 perform 1 from public.provider_profiles where user_id=p_provider for update;
 debt:=private.commission_overdue(p_provider);
 if private.commission_blocked(p_provider) then
  insert into public.provider_suspension_records(provider_id,amount_paise) values(p_provider,debt) on conflict(provider_id) where resolved_at is null do nothing returning id into row_id;
  if row_id is not null then
   insert into public.provider_account_status_history(provider_id,status,reason) values(p_provider,'commission_suspended','Overdue earned commission');
   perform private.notify(p_provider,'New requests paused: earned commission payment is overdue. Existing jobs, support and payment submission remain available.');
  end if;
 elsif coalesce((private.ops()->>'auto_reactivate')::boolean,true) then
  for row_id in select id from public.provider_suspension_records where provider_id=p_provider and resolved_at is null for update loop
   update public.provider_suspension_records set resolved_at=now() where id=row_id;
   insert into public.provider_reactivation_records(provider_id,suspension_id,reason) values(p_provider,row_id,'No overdue undisputed commission remains');
   insert into public.provider_account_status_history(provider_id,status,reason) values(p_provider,'commission_reactivated','Commission restriction cleared; other account restrictions still apply');
   perform private.notify(p_provider,'Your commission restriction has been cleared. New requests resume if your account is otherwise approved and online.');
  end loop;
 end if;
end $$;
create or replace function public.provider_eligible(p_provider uuid,p_service text,p_location text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.provider_profiles p join public.users u on u.id=p.user_id cross join public.website_configuration c where c.id and not c.maintenance_mode and c.provider_portal_enabled and u.is_active and p.user_id=p_provider and p.status='approved' and p.online and p_service=any(p.service_ids) and p_location=any(p.locations) and not private.commission_blocked(p_provider))
$$;
create or replace function public.commission_dashboard() returns jsonb language plpgsql security definer set search_path='' as $$
declare target uuid:=auth.uid(); result jsonb;
begin
 if not public.account_active() then raise exception 'Sign in.' using errcode='42501';end if;
 if public.is_admin() then target:=null;else perform private.reconcile_provider(target);end if;
 select jsonb_build_object('statements',coalesce((select jsonb_agg(s) from private.commission_statements(target) s),'[]'),
 'payments',coalesce((select jsonb_agg(to_jsonb(p)) from public.provider_commission_payments p where target is null or p.provider_id=target),'[]'),
 'suspensions',coalesce((select jsonb_agg(to_jsonb(s)) from public.provider_suspension_records s where target is null or s.provider_id=target),'[]'),
 'rules',case when public.is_admin() then coalesce((select jsonb_agg(to_jsonb(r)) from public.provider_commission_rules r),'[]') else '[]' end,
 'current_commission_blocked',case when target is not null then private.commission_blocked(target) else false end,'config',private.ops()) into result;
 return result;
end $$;
create or replace function public.admin_commission_rule(p_data jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 if nullif(p_data->>'provider_id','') is not null then
  insert into public.provider_commission_rules(provider_id,percent,fixed_paise,active) values((p_data->>'provider_id')::uuid,(p_data->>'percent')::numeric,(p_data->>'fixed_paise')::bigint,coalesce((p_data->>'active')::boolean,true)) on conflict(provider_id) where provider_id is not null do update set percent=excluded.percent,fixed_paise=excluded.fixed_paise,active=excluded.active;
 else
  insert into public.provider_commission_rules(category,percent,fixed_paise,active) values(p_data->>'category',(p_data->>'percent')::numeric,(p_data->>'fixed_paise')::bigint,coalesce((p_data->>'active')::boolean,true)) on conflict(category) where category is not null do update set percent=excluded.percent,fixed_paise=excluded.fixed_paise,active=excluded.active;
 end if;perform private.audit('Update commission rule');
end $$;
revoke execute on function public.commission_dashboard(),public.admin_commission_rule(jsonb) from public,anon;
grant execute on function public.commission_dashboard(),public.admin_commission_rule(jsonb) to authenticated;
revoke execute on all functions in schema private from public,anon,authenticated;

-- Migration: 20261116000300_booking_workflows.sql
-- Broadcast every request and atomically assign its first accepting provider.
create or replace function public.can_view_booking(p_booking uuid) returns boolean language sql stable security definer set search_path='' as $$
 select public.account_active() and exists(select 1 from public.bookings b where b.id=p_booking and(public.is_admin() or b.customer_id=auth.uid() or b.provider_id=auth.uid() or(b.provider_id is null and b.status='requested' and not b.request_expired and public.provider_eligible(auth.uid(),b.service_id,b.location) and exists(select 1 from public.booking_provider_offers o where o.booking_id=b.id and o.provider_id=auth.uid() and o.status='pending'))))
$$;
create or replace function public.create_booking(p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare s public.services;b_id uuid;candidate uuid;scheduled timestamptz;timeout_minutes integer:=(private.ops()->>'request_timeout_minutes')::int;
begin
 perform private.take_rate_limit();
 select id into b_id from public.bookings where customer_id=auth.uid() and idempotency_key=(p_data->>'idempotency_key')::uuid;if b_id is not null then return b_id;end if;
 select * into s from public.services where id=p_data->>'service_id' and active;if s.id is null then raise exception 'This service is not available.';end if;
 if not exists(select 1 from public.locations where name=p_data->>'location' and active) then raise exception 'Choose a supported location.';end if;
 scheduled:=(p_data->>'scheduled_at')::timestamptz;if scheduled is null or scheduled<=now() then raise exception 'Choose a future date and time.';end if;
 if length(trim(coalesce(p_data->>'address',''))) not between 1 and 1000 or length(trim(coalesce(p_data->>'description',''))) not between 1 and 4000 then raise exception 'Enter your address and job details.';end if;
 if p_data->>'payment_method'<>'cash' then raise exception 'Choose pay after service.';end if;
 if s.type in ('transport','goods') and coalesce(p_data->'details'->>'destination','')='' then raise exception 'Enter your destination.';end if;
 if s.type='rental' and(coalesce(p_data->'details'->>'end_date','')='' or(p_data->'details'->>'end_date')::timestamptz<scheduled) then raise exception 'Choose a valid rental end date.';end if;
 if not exists(select 1 from public.provider_profiles p where p.user_id<>auth.uid() and public.provider_eligible(p.user_id,s.id,p_data->>'location')) then raise exception 'No approved, online provider is available for this service in your town yet.';end if;
 insert into public.bookings(customer_id,service_id,location,address,scheduled_at,description,details,estimated_price,idempotency_key,requested_provider_id,requires_quote,latitude,longitude,destination_latitude,destination_longitude,request_expires_at)
 values(auth.uid(),s.id,p_data->>'location',trim(p_data->>'address'),scheduled,trim(p_data->>'description'),coalesce(p_data->'details','{}'),s.price,(p_data->>'idempotency_key')::uuid,null,s.type='quote',nullif(p_data->>'latitude','')::float8,nullif(p_data->>'longitude','')::float8,nullif(p_data->>'destination_latitude','')::float8,nullif(p_data->>'destination_longitude','')::float8,case when timeout_minutes>0 then now()+make_interval(mins=>timeout_minutes) else null end)
 on conflict(customer_id,idempotency_key) do nothing returning id into b_id;
 if b_id is null then select id into b_id from public.bookings where customer_id=auth.uid() and idempotency_key=(p_data->>'idempotency_key')::uuid;return b_id;end if;
 for candidate in select p.user_id from public.provider_profiles p where p.user_id<>auth.uid() and public.provider_eligible(p.user_id,s.id,p_data->>'location') loop
  insert into public.booking_provider_offers(booking_id,provider_id) values(b_id,candidate);
  perform private.notify(candidate,'New '||private.safe_text(s.name)||' request in '||(p_data->>'location'),b_id);
 end loop;
 perform private.record_history(b_id,'requested','Request sent to all eligible providers');perform private.notify(auth.uid(),'Your request was sent to all eligible Local Mate providers',b_id);return b_id;
end $$;
create or replace function public.accept_booking(p_booking uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.bookings;offer public.provider_offerings;next_status text;needs_quote boolean;limit_daily int;
begin
 perform private.take_rate_limit();
 if not exists(select 1 from public.booking_provider_offers where booking_id=p_booking and provider_id=auth.uid()) then raise exception 'You do not have access to this request.' using errcode='42501';end if;
 select * into b from public.bookings where id=p_booking for update;
 if b.provider_id=auth.uid() and b.accepted_at is not null then return jsonb_build_object('ok',true,'already_accepted',true,'accepted_at',b.accepted_at);end if;
 if b.provider_id is not null and b.provider_id<>auth.uid() then
  return jsonb_build_object('ok',false,'code','ALREADY_ASSIGNED','error','This booking has already been accepted by another provider.');
 end if;
 if b.customer_id=auth.uid() then raise exception 'A provider cannot accept their own booking.';end if;
 if b.status<>'requested' or b.request_expired or(private.ops()->>'request_expiry_mode'='expire' and b.request_expires_at<now()) then raise exception 'This request has expired or is no longer available.';end if;
 if not public.provider_eligible(auth.uid(),b.service_id,b.location) or not exists(select 1 from public.booking_provider_offers where booking_id=b.id and provider_id=auth.uid() and status='pending') then raise exception 'This request is not available to your provider account.';end if;
 perform 1 from public.provider_profiles where user_id=auth.uid() for update;
 select coalesce((schedule->>'max_daily')::int,5) into limit_daily from public.provider_profiles where user_id=auth.uid();
 if(select count(*) from public.bookings where provider_id=auth.uid() and id<>b.id and status not in ('cancelled','disputed') and(scheduled_at at time zone(private.ops()->>'timezone'))::date=(b.scheduled_at at time zone(private.ops()->>'timezone'))::date)>=limit_daily then raise exception 'Your daily booking limit has been reached.';end if;
 select * into offer from public.provider_offerings where provider_id=auth.uid() and service_id=b.service_id;
 needs_quote:=(select type='quote' from public.services where id=b.service_id) or(offer.provider_id is not null and offer.pricing_unit<>'visit') or(offer.provider_id is null and b.estimated_price=0);
 next_status:=case when needs_quote then 'requested' else 'confirmed' end;
 update public.bookings set provider_id=auth.uid(),accepted_at=now(),requested_provider_id=null,requires_quote=needs_quote,estimated_price=coalesce(offer.price,estimated_price),status=next_status where id=b.id;
 insert into public.booking_assignments(booking_id,provider_id,accepted_at,actor_id) values(b.id,auth.uid(),now(),auth.uid());
 insert into public.booking_assignment_history(booking_id,provider_id,actor_id,event) values(b.id,auth.uid(),auth.uid(),'accepted');
 update public.booking_provider_offers set status=case when provider_id=auth.uid() then 'accepted' else 'lost' end,responded_at=now() where booking_id=b.id and status='pending';
 perform private.record_history(b.id,next_status,'First provider acceptance recorded');
 perform private.notify(b.customer_id,'A verified Local Mate provider accepted your booking',b.id);
 insert into public.booking_events(booking_id,kind) values(b.id,'assigned');
 return jsonb_build_object('ok',true,'provider_id',auth.uid(),'accepted_at',now());
end $$;
-- Keep the proven quotation/cancellation/review transitions, behind new mandatory guards.
do $$ begin
 if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='legacy_booking_action') then
  alter function public.booking_action(uuid,text,jsonb) set schema private;
  alter function private.booking_action(uuid,text,jsonb) rename to legacy_booking_action;
 end if;
end $$;
create or replace function public.booking_action(p_booking uuid,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.bookings;result jsonb;candidate uuid;
begin
 if p_action='accept' then return public.accept_booking(p_booking);end if;
 if not public.account_active() then raise exception 'Sign in.' using errcode='42501';end if;
 select * into b from public.bookings where id=p_booking;
 if p_action='status' and p_data->>'status'='work_started' then
  if b.status<>'work_paused' or not exists(select 1 from public.job_start_verifications where booking_id=b.id and provider_id=b.provider_id) then raise exception 'Customer OTP verification is required before work starts.';end if;
 elsif p_action='status' and p_data->>'status'='work_completed' then raise exception 'Submit the final bill to mark work completed.';
 elsif p_action='quote' and(b.provider_id is distinct from auth.uid() or b.accepted_at is null) then raise exception 'Accept the request first; only its assigned provider can quote.';
 elsif p_action='reject' then
  perform private.take_rate_limit();
  if b.provider_id is not null or not exists(select 1 from public.booking_provider_offers where booking_id=b.id and provider_id=auth.uid() and status='pending') then raise exception 'This request is no longer available.';end if;
  update public.booking_provider_offers set status='rejected',responded_at=now() where booking_id=b.id and provider_id=auth.uid();return jsonb_build_object('ok',true);
 end if;
 result:=private.legacy_booking_action(p_booking,p_action,p_data);
 if p_action='quote-response' and not (p_data->>'accept')::boolean then
  delete from public.booking_assignments where booking_id=b.id;
  insert into public.booking_assignment_history(booking_id,provider_id,actor_id,event) values(b.id,b.provider_id,auth.uid(),'quote_declined');
  update public.bookings set accepted_at=null,request_expired=false,request_expires_at=case when (private.ops()->>'request_timeout_minutes')::int>0 then now()+make_interval(mins=>(private.ops()->>'request_timeout_minutes')::int) else null end where id=b.id;
  update public.booking_provider_offers set status='rejected',responded_at=now() where booking_id=b.id and provider_id=b.provider_id;
  for candidate in select user_id from public.provider_profiles where user_id<>b.customer_id and user_id<>b.provider_id and public.provider_eligible(user_id,b.service_id,b.location) loop
   insert into public.booking_provider_offers(booking_id,provider_id) values(b.id,candidate) on conflict(booking_id,provider_id) do update set status='pending',offered_at=now(),responded_at=null;
   perform private.notify(candidate,'A Local Mate request is available again',b.id);
  end loop;
  insert into public.booking_events(booking_id,kind) values(b.id,'request_reopened');
 end if;
 return result;
end $$;
create or replace function private.work_verification_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='work_started' and old.status is distinct from new.status and not exists(select 1 from public.job_start_verifications where booking_id=new.id and provider_id=new.provider_id) then raise exception 'Customer OTP verification is required before work starts.';end if;
 if new.status='work_completed' and old.status is distinct from new.status and not exists(select 1 from public.job_bills where booking_id=new.id and provider_id=new.provider_id and status in ('submitted','confirmed')) then raise exception 'A final bill is required before completing work.';end if;
 return new;
end $$;
drop trigger if exists work_verification_guard on public.bookings;
create trigger work_verification_guard before update on public.bookings for each row execute function private.work_verification_guard();
-- Customer locations and identities are shown only after actual acceptance.
create or replace function public.safe_booking(p_booking uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare b public.bookings;full_access boolean;result jsonb;
begin
 if not public.can_view_booking(p_booking) then raise exception 'Booking not found or unavailable to your account.' using errcode='42501';end if;
 select * into b from public.bookings where id=p_booking;
 full_access:=public.is_admin() or b.customer_id=auth.uid() or(b.provider_id=auth.uid() and b.accepted_at is not null);
 result:=jsonb_build_object('id',b.id,'booking_reference',upper(left(b.id::text,8)),'service_id',b.service_id,'service_name',(select name from public.services where id=b.service_id),'service_type',(select type from public.services where id=b.service_id),'service_category',(select category from public.services where id=b.service_id),'provider_id',b.provider_id,'status',b.status,'request_expired',(b.request_expired or(private.ops()->>'request_expiry_mode'='expire' and b.request_expires_at<now())),'request_expires_at',b.request_expires_at,'scheduled_at',b.scheduled_at,'accepted_at',b.accepted_at,'location',b.location,'description',private.safe_text(b.description),'requires_quote',b.requires_quote,'estimated_price',b.estimated_price,'payment_status',b.payment_status,'payment_method',b.payment_method,'created_at',b.created_at,
 'provider_name',(select private.safe_text(coalesce(nullif(p.business_name,''),u.name)) from public.provider_profiles p join public.users u on u.id=p.user_id where p.user_id=b.provider_id),'provider_logo_id',(select logo_id from public.provider_profiles where user_id=b.provider_id),'customer_name','Customer · '||upper(left(b.id::text,8)));
 if full_access then result:=result||jsonb_build_object('customer_id',b.customer_id,'address',private.safe_text(b.address),'latitude',b.latitude,'longitude',b.longitude,'destination_latitude',b.destination_latitude,'destination_longitude',b.destination_longitude,'details',private.safe_json(b.details));else result:=result||jsonb_build_object('address','Exact address available after acceptance','details','{}'::jsonb);end if;
 return result;
end $$;
create or replace function public.list_bookings(p_role text default 'customer') returns setof jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.account_active() then raise exception 'Sign in.' using errcode='42501';end if;
 if p_role='admin' and not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 return query select public.safe_booking(b.id) from public.bookings b where case p_role when 'admin' then public.is_admin() when 'provider' then b.provider_id=auth.uid() or(b.provider_id is null and b.status='requested' and not b.request_expired and public.can_view_booking(b.id)) else b.customer_id=auth.uid() end order by b.created_at desc;
end $$;
create or replace function public.booking_detail(p_booking uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 result:=public.safe_booking(p_booking);
 if public.can_message_booking(p_booking) then
  result:=result||jsonb_build_object('history',coalesce((select jsonb_agg(jsonb_build_object('status',status,'note',private.safe_text(note),'created_at',created_at) order by id) from public.booking_status_history where booking_id=p_booking),'[]'),
   'quotes',coalesce((select jsonb_agg(to_jsonb(q)||jsonb_build_object('terms',private.safe_text(q.terms)) order by q.created_at desc) from public.quotations q where q.booking_id=p_booking),'[]'),
   'otp_verified',exists(select 1 from public.job_start_verifications where booking_id=p_booking));
 else result:=result||jsonb_build_object('history','[]'::jsonb,'quotes','[]'::jsonb,'otp_verified',false);end if;
 return result;
end $$;
create or replace function public.retry_booking(p_booking uuid) returns void language plpgsql security definer set search_path='' as $$
declare b public.bookings;candidate uuid;
begin
 perform private.take_rate_limit();select * into b from public.bookings where id=p_booking for update;
 if b.customer_id is distinct from auth.uid() and not public.is_admin() then raise exception 'Not permitted.' using errcode='42501';end if;
 if b.provider_id is not null or b.status<>'requested' then raise exception 'Only unassigned pending requests can be retried.';end if;
 update public.bookings set request_expired=false,request_expires_at=now()+make_interval(mins=>(private.ops()->>'request_timeout_minutes')::int) where id=b.id;
 for candidate in select user_id from public.provider_profiles where user_id<>b.customer_id and public.provider_eligible(user_id,b.service_id,b.location) loop
  insert into public.booking_provider_offers(booking_id,provider_id) values(b.id,candidate) on conflict(booking_id,provider_id) do update set status='pending',offered_at=now(),responded_at=null;
  perform private.notify(candidate,'A Local Mate request is available again',b.id);
 end loop;perform private.record_history(b.id,'requested','Customer or administrator retried broadcast');
end $$;
-- Only the trusted application server handles OTP ciphertext/hash material.
create or replace function public.service_issue_job_otp(p_actor uuid,p_booking uuid,p_hash text,p_cipher text) returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.bookings;o private.job_start_otps;
begin
 if auth.role()<>'service_role' then raise exception 'Server authorization required.' using errcode='42501';end if;
 select * into b from public.bookings where id=p_booking for update;
 if not exists(select 1 from public.users where id=p_actor and is_active) or(p_actor<>b.customer_id and p_actor is distinct from b.provider_id) then raise exception 'Not permitted.' using errcode='42501';end if;
 if b.status<>'arrived' or b.accepted_at is null then raise exception 'The provider must arrive before start verification.';end if;
 select * into o from private.job_start_otps where booking_id=b.id and provider_id=b.provider_id order by created_at desc limit 1 for update;
 if o.id is not null and o.used_at is null and o.expires_at>now() then return jsonb_build_object('id',o.id,'expires_at',o.expires_at,'existing',true);end if;
 if(select count(*) from private.job_start_otps where booking_id=b.id and created_at>now()-interval '1 hour')>=3 then raise exception 'Too many OTP requests. Contact support or try again later.';end if;
 insert into private.job_start_otps(booking_id,provider_id,code_hash,ciphertext,expires_at) values(b.id,b.provider_id,p_hash,p_cipher,now()+make_interval(secs=>(private.ops()->>'otp_ttl_seconds')::int)) returning * into o;
 insert into public.job_start_otp_logs(booking_id,provider_id,actor_id,event) values(b.id,b.provider_id,p_actor,'issued');
 perform private.notify(b.customer_id,'Your provider requested work-start verification. Open your booking to view the private OTP.',b.id);
 return jsonb_build_object('id',o.id,'expires_at',o.expires_at,'existing',false);
end $$;
create or replace function public.service_customer_job_otp(p_actor uuid,p_booking uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role()<>'service_role' or not exists(select 1 from public.bookings b join public.users u on u.id=b.customer_id where b.id=p_booking and b.customer_id=p_actor and u.is_active) then raise exception 'Customer authorization required.' using errcode='42501';end if;
 return(select jsonb_build_object('ciphertext',o.ciphertext,'expires_at',o.expires_at,'attempts',o.attempts,'locked',o.attempts>=(private.ops()->>'otp_max_attempts')::int) from private.job_start_otps o join public.bookings b on b.id=o.booking_id where o.booking_id=p_booking and o.provider_id=b.provider_id and o.used_at is null and o.expires_at>now() order by o.created_at desc limit 1);
end $$;
create or replace function public.service_verify_job_otp(p_actor uuid,p_booking uuid,p_hash text) returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.bookings;o private.job_start_otps;
begin
 if auth.role()<>'service_role' then raise exception 'Server authorization required.' using errcode='42501';end if;
 select * into b from public.bookings where id=p_booking for update;
 if b.provider_id is distinct from p_actor or not exists(select 1 from public.users where id=p_actor and is_active) then raise exception 'Only the assigned provider can verify.' using errcode='42501';end if;
 if b.status<>'arrived' or b.accepted_at is null then raise exception 'This job cannot be started now.';end if;
 select * into o from private.job_start_otps where booking_id=b.id and provider_id=p_actor order by created_at desc limit 1 for update;
 if o.id is null or o.used_at is not null or o.expires_at<=now() then return jsonb_build_object('ok',false,'error','The OTP expired or has already been used.');end if;
 if o.attempts>=(private.ops()->>'otp_max_attempts')::int then return jsonb_build_object('ok',false,'error','OTP attempt limit reached. Contact support.');end if;
 update private.job_start_otps set attempts=attempts+1 where id=o.id;
 if o.code_hash<>p_hash then
  insert into public.job_start_otp_logs(booking_id,provider_id,actor_id,event) values(b.id,p_actor,p_actor,'incorrect_attempt');
  return jsonb_build_object('ok',false,'error','Incorrect OTP.','attempts_remaining',(private.ops()->>'otp_max_attempts')::int-o.attempts-1);
 end if;
 update private.job_start_otps set used_at=now(),ciphertext='' where id=o.id;
 insert into public.job_start_verifications(booking_id,provider_id,actor_id,method) values(b.id,p_actor,p_actor,'otp');
 update public.bookings set status='work_started' where id=b.id;
 insert into public.booking_status_history(booking_id,actor_id,status,note) values(b.id,p_actor,'work_started','Customer OTP verified');
 insert into public.job_start_otp_logs(booking_id,provider_id,actor_id,event) values(b.id,p_actor,p_actor,'verified');
 perform private.notify(b.customer_id,'Your OTP was verified and work has started',b.id);return jsonb_build_object('ok',true);
end $$;
create or replace function public.admin_start_exception(p_booking uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare b public.bookings;
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 if length(trim(p_reason)) not between 10 and 1000 then raise exception 'Record the reason for this verification exception.';end if;
 select * into b from public.bookings where id=p_booking for update;
 if b.provider_id is null or b.accepted_at is null or b.status<>'arrived' then raise exception 'An accepted, arrived booking is required.';end if;
 insert into public.job_start_verifications(booking_id,provider_id,actor_id,method,reason) values(b.id,b.provider_id,auth.uid(),'admin_exception',p_reason);
 update public.bookings set status='work_started' where id=b.id;
 perform private.record_history(b.id,'work_started','Administrator verification exception');perform private.financial_audit('OTP exception',b.id,jsonb_build_object('reason',p_reason));
 perform private.notify(b.customer_id,'An administrator approved work-start verification for your booking',b.id);
end $$;
-- Existing legitimate assignments keep their historical evidence, without invented times.
update public.bookings b set accepted_at=h.at from(select booking_id,min(h.created_at) at from public.booking_status_history h join public.bookings b on b.id=h.booking_id where h.actor_id=b.provider_id and h.status='confirmed' group by booking_id) h where b.id=h.booking_id and b.accepted_at is null;
insert into public.booking_provider_offers(booking_id,provider_id) select b.id,p.user_id from public.bookings b join public.provider_profiles p on p.user_id<>b.customer_id and public.provider_eligible(p.user_id,b.service_id,b.location) where b.provider_id is null and b.status='requested' on conflict do nothing;
revoke execute on function public.accept_booking(uuid),public.booking_action(uuid,text,jsonb),public.safe_booking(uuid),public.booking_detail(uuid),public.retry_booking(uuid),public.admin_start_exception(uuid,text) from public,anon;
grant execute on function public.accept_booking(uuid),public.booking_action(uuid,text,jsonb),public.safe_booking(uuid),public.booking_detail(uuid),public.retry_booking(uuid),public.admin_start_exception(uuid,text) to authenticated;
revoke execute on function public.service_issue_job_otp(uuid,uuid,text,text),public.service_customer_job_otp(uuid,uuid),public.service_verify_job_otp(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.service_issue_job_otp(uuid,uuid,text,text),public.service_customer_job_otp(uuid,uuid),public.service_verify_job_otp(uuid,uuid,text) to service_role;
revoke execute on all functions in schema private from public,anon,authenticated;
notify pgrst, 'reload schema';

-- Migration: 20261116000400_billing_commissions.sql
create or replace function private.accrue_commission(p_bill uuid) returns void language plpgsql security definer set search_path='' as $$
declare bill public.job_bills;b public.bookings;cfg jsonb:=private.ops();rate numeric;fixed bigint;source text:='default';r public.provider_commission_rules;local_day date;start_day date;start_at timestamptz;end_at timestamptz;period uuid;amount bigint;
begin
 select * into bill from public.job_bills where id=p_bill;
 select * into b from public.bookings where id=bill.booking_id;
 if bill.status<>'confirmed' or b.status<>'work_completed' or b.payment_status in ('refunded','partially_refunded') or not(cfg->>'commission_enabled')::boolean then return;end if;
 if exists(select 1 from public.provider_commissions where booking_id=b.id and status<>'void') then return;end if;
 rate:=(cfg->>'commission_percent')::numeric;fixed:=(cfg->>'commission_fixed_paise')::bigint;
 select * into r from public.provider_commission_rules where provider_id=b.provider_id and active;
 if r.id is null then select * into r from public.provider_commission_rules where category=(select category from public.services where id=b.service_id) and active;source:='category';else source:='provider';end if;
 if r.id is not null then rate:=r.percent;fixed:=r.fixed_paise;else source:='default';end if;
 amount:=case when bill.total_paise>0 then round(bill.total_paise*rate/100)::bigint+fixed else 0 end;
 local_day:=(bill.confirmed_at at time zone(cfg->>'timezone'))::date;
 start_day:=local_day-((extract(dow from local_day)::int-(cfg->>'week_start_day')::int+7)%7);
 start_at:=start_day::timestamp at time zone(cfg->>'timezone');end_at:=(start_day+7)::timestamp at time zone(cfg->>'timezone');
 insert into public.weekly_commission_periods(starts_at,ends_at,timezone,deadline_at,grace_until)
 values(start_at,end_at,cfg->>'timezone',end_at+make_interval(days=>(cfg->>'deadline_days')::int),end_at+make_interval(days=>(cfg->>'deadline_days')::int,hours=>(cfg->>'grace_hours')::int))
 on conflict(starts_at,ends_at,timezone) do update set timezone=excluded.timezone returning id into period;
 insert into public.provider_commissions(booking_id,bill_id,provider_id,period_id,billable_paise,rate_percent,fixed_paise,commission_paise,rule_snapshot)
 values(b.id,bill.id,b.provider_id,period,bill.total_paise,rate,fixed,amount,jsonb_build_object('source',source,'rule_id',r.id,'percent',rate,'fixed_paise',fixed))
 on conflict(booking_id) do update set bill_id=excluded.bill_id,period_id=excluded.period_id,billable_paise=excluded.billable_paise,rate_percent=excluded.rate_percent,fixed_paise=excluded.fixed_paise,commission_paise=excluded.commission_paise,rule_snapshot=excluded.rule_snapshot,status='due' where public.provider_commissions.status='void';
 perform private.financial_audit('Accrue earned commission',b.id,jsonb_build_object('period_id',period,'amount_paise',amount,'rate_percent',rate));
end $$;
create or replace function public.request_additional_charge(p_booking uuid,p_amount bigint,p_description text) returns uuid language plpgsql security definer set search_path='' as $$
declare b public.bookings;charge uuid;
begin
 perform private.take_rate_limit();select * into b from public.bookings where id=p_booking for update;
 if b.provider_id is distinct from auth.uid() or b.accepted_at is null then raise exception 'Only the assigned provider can request additional charges.' using errcode='42501';end if;
 if b.status not in ('confirmed','on_the_way','arrived','work_started','work_paused') then raise exception 'Additional charges cannot be requested now.';end if;
 perform private.check_private_text(p_description);
 insert into public.booking_charge_requests(booking_id,provider_id,amount_paise,description) values(b.id,auth.uid(),p_amount,trim(p_description)) returning id into charge;
 perform private.notify(b.customer_id,'An additional charge needs your approval before it can be billed',b.id);return charge;
end $$;
create or replace function public.respond_additional_charge(p_charge uuid,p_action text) returns void language plpgsql security definer set search_path='' as $$
declare charge public.booking_charge_requests;
begin
 perform private.take_rate_limit();select * into charge from public.booking_charge_requests where id=p_charge for update;
 if not exists(select 1 from public.bookings where id=charge.booking_id and customer_id=auth.uid()) then raise exception 'Only the booking customer can respond.' using errcode='42501';end if;
 if charge.status<>'pending' or p_action not in ('approved','rejected','disputed') then raise exception 'This charge is not pending or the response is invalid.';end if;
 update public.booking_charge_requests set status=p_action,responded_at=now() where id=charge.id;
 perform private.financial_audit('Customer additional charge response',charge.booking_id,jsonb_build_object('charge_id',charge.id,'status',p_action));
 perform private.notify(charge.provider_id,'Additional charge: '||p_action,charge.booking_id);
end $$;
create or replace function public.submit_final_bill(p_booking uuid,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare b public.bookings;bill_id uuid;labour bigint:=(p_data->>'labour_paise')::bigint;materials bigint:=(p_data->>'materials_paise')::bigint;discount bigint:=coalesce((p_data->>'discount_paise')::bigint,0);extra bigint;tax bigint;rate numeric:=0;subtotal bigint;approved_base bigint;revision int;
begin
 perform private.take_rate_limit();select * into b from public.bookings where id=p_booking for update;
 if b.provider_id is distinct from auth.uid() or b.accepted_at is null then raise exception 'Only the assigned provider can bill this job.' using errcode='42501';end if;
 if b.status not in ('work_started','work_completed','disputed') or not exists(select 1 from public.job_start_verifications where booking_id=b.id and provider_id=auth.uid()) then raise exception 'Verified work-start is required before final billing.';end if;
 if exists(select 1 from public.job_bills where booking_id=b.id and status<>'void') then raise exception 'A bill already exists. It cannot be changed without an audited resolution.';end if;
 if labour is null or materials is null or labour<0 or materials<0 or discount<0 or greatest(labour,materials,discount)>1000000000 then raise exception 'Enter valid bill amounts in paise.';end if;
 if length(trim(coalesce(p_data->>'description',''))) not between 1 and 2000 then raise exception 'Describe the completed work.';end if;
 perform private.check_private_text(p_data->>'description');
 select q.labour::bigint*100+q.materials::bigint*100 into approved_base from public.quotations q where q.booking_id=b.id and q.status='approved' order by created_at desc limit 1;
 if approved_base is null then approved_base:=b.estimated_price::bigint*100;end if;
 if labour+materials>approved_base then raise exception 'The base bill exceeds the agreed estimate or quotation. Request customer approval for additional charges first.';end if;
 select coalesce(sum(amount_paise),0) into extra from public.booking_charge_requests where booking_id=b.id and status='approved';
 extra:=extra+coalesce((select additional*100 from public.quotations where booking_id=b.id and status='approved' order by created_at desc limit 1),0);
 subtotal:=labour+materials+extra-discount;if subtotal<0 then raise exception 'Discount exceeds the approved charges.';end if;
 if (private.ops()->>'tax_enabled')::boolean then rate:=(private.ops()->>'tax_percent')::numeric;end if;
 tax:=round(subtotal*rate/100)::bigint;
 select coalesce(max(j.revision),0)+1 into revision from public.job_bills j where booking_id=b.id;
 insert into public.job_bills(booking_id,provider_id,revision,labour_paise,materials_paise,additional_paise,discount_paise,tax_paise,total_paise,tax_percent,description)
 values(b.id,auth.uid(),revision,labour,materials,extra,discount,tax,subtotal+tax,rate,trim(p_data->>'description')) returning id into bill_id;
 insert into public.job_completion_records(booking_id,provider_id,description) values(b.id,auth.uid(),p_data->>'description') on conflict(booking_id) do nothing;
 update public.bookings set status='work_completed' where id=b.id;
 perform private.record_history(b.id,'work_completed','Final bill submitted for customer confirmation');perform private.financial_audit('Submit final bill',b.id,jsonb_build_object('bill_id',bill_id,'total_paise',subtotal+tax));
 perform private.notify(b.customer_id,'Work is completed. Review your final bill in Local Mate.',b.id);return bill_id;
end $$;
create or replace function private.confirm_bill(p_bill uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare bill public.job_bills;b public.bookings;invoice uuid;snapshot jsonb;cfg jsonb:=private.ops();
begin
 select * into bill from public.job_bills where id=p_bill for update;select * into b from public.bookings where id=bill.booking_id for update;
 if bill.status='confirmed' then return(select id from public.invoices where bill_id=bill.id);end if;
 if bill.status not in ('submitted','disputed') then raise exception 'This bill cannot be confirmed.';end if;
 update public.job_bills set status='confirmed',confirmed_at=now(),dispute_reason=null where id=bill.id;
 update public.bookings set status='work_completed' where id=b.id;
 snapshot:=jsonb_build_object('platform_name',coalesce((select content->>'site_name' from public.website_configuration where id),'Local Mate'),'platform_address',cfg->>'supplier_address','customer_name',(select private.safe_text(name) from public.users where id=b.customer_id),'customer_address',private.safe_text(b.address),'provider_name',(select private.safe_text(coalesce(nullif(p.business_name,''),u.name)) from public.provider_profiles p join public.users u on u.id=p.user_id where p.user_id=b.provider_id),'provider_locations',(select locations from public.provider_profiles where user_id=b.provider_id),'service_name',(select name from public.services where id=b.service_id),'description',private.safe_text(bill.description),'booking_id',b.id,'labour_paise',bill.labour_paise,'materials_paise',bill.materials_paise,'additional_paise',bill.additional_paise,'discount_paise',bill.discount_paise,'tax_paise',bill.tax_paise,'tax_percent',bill.tax_percent,'tax_registration',case when bill.tax_paise>0 then cfg->>'tax_registration' else '' end,'total_paise',bill.total_paise,'payment_method',b.payment_method,'terms',cfg->>'invoice_terms');
 insert into public.invoices(bill_id,booking_id,snapshot) values(bill.id,b.id,snapshot) returning id into invoice;
 insert into public.invoice_items(invoice_id,label,amount_paise) values(invoice,'Labour',bill.labour_paise),(invoice,'Materials',bill.materials_paise),(invoice,'Customer-approved additional charges',bill.additional_paise),(invoice,'Discount',-bill.discount_paise),(invoice,'Tax',bill.tax_paise);
 perform private.accrue_commission(bill.id);
 perform private.financial_audit('Confirm bill and issue invoice',b.id,jsonb_build_object('bill_id',bill.id,'invoice_id',invoice),p_actor);
 perform private.notify(b.provider_id,'The final bill was confirmed and its invoice is ready',b.id);return invoice;
end $$;
create or replace function public.respond_final_bill(p_bill uuid,p_action text,p_reason text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare bill public.job_bills;b public.bookings;invoice uuid;
begin
 perform private.take_rate_limit();select * into bill from public.job_bills where id=p_bill for update;select * into b from public.bookings where id=bill.booking_id for update;
 if b.customer_id is distinct from auth.uid() then raise exception 'Only the booking customer can confirm or dispute this bill.' using errcode='42501';end if;
 if p_action='confirm' then
  if bill.status not in ('submitted','confirmed') then raise exception 'A disputed bill needs an audited resolution.';end if;
  invoice:=private.confirm_bill(bill.id,auth.uid());return jsonb_build_object('ok',true,'invoice_id',invoice);
 elsif p_action='dispute' then
  if bill.status not in ('submitted','confirmed') or length(trim(p_reason)) not between 5 and 2000 then raise exception 'Add a reason for the bill dispute.';end if;
  perform private.check_private_text(p_reason);
  update public.job_bills set status='disputed',dispute_reason=p_reason where id=bill.id;
  update public.provider_commissions set status='held' where booking_id=b.id and status='due';
  update public.bookings set status='disputed' where id=b.id;
  perform private.financial_audit('Customer disputed final bill',b.id,jsonb_build_object('reason',p_reason));
  perform private.notify(b.provider_id,'The customer disputed the final bill. Contact Local Mate support.',b.id);
  perform private.reconcile_provider(b.provider_id);return jsonb_build_object('ok',true);
 end if;raise exception 'Choose confirm or dispute.';
end $$;
create or replace function public.admin_resolve_bill(p_bill uuid,p_action text,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare bill public.job_bills;b public.bookings;
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 if length(trim(p_reason)) not between 10 and 2000 then raise exception 'Record the verified resolution and its reason.';end if;
 select * into bill from public.job_bills where id=p_bill for update;select * into b from public.bookings where id=bill.booking_id for update;
 if p_action='confirm' then
  if b.payment_status in ('refunded','partially_refunded') then raise exception 'Reconcile the actual refund and void or correct the bill; refunded commission remains held.';end if;
  if exists(select 1 from public.invoices where bill_id=bill.id) then
   update public.job_bills set status='confirmed' where id=bill.id;update public.bookings set status='work_completed' where id=b.id;update public.provider_commissions set status='due' where booking_id=b.id and status='held';
  else perform private.confirm_bill(bill.id,auth.uid());end if;
 elsif p_action='void' then
  update public.job_bills set status='void' where id=bill.id;update public.invoices set status='void' where bill_id=bill.id;update public.provider_commissions set status='void' where booking_id=b.id;
 else raise exception 'Choose confirm or void. Actual refunds must be reconciled separately.';end if;
 perform private.financial_audit('Administrator bill resolution',b.id,jsonb_build_object('action',p_action,'reason',p_reason));perform private.reconcile_provider(b.provider_id);
 perform private.notify(b.customer_id,'An administrator resolved your bill review',b.id);perform private.notify(b.provider_id,'An administrator resolved the bill review',b.id);
end $$;
create or replace function public.booking_finances(p_booking uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.account_active() or not public.can_message_booking(p_booking) then raise exception 'These billing records are private.' using errcode='42501';end if;
 return jsonb_build_object('charges',coalesce((select jsonb_agg(to_jsonb(c)) from public.booking_charge_requests c where booking_id=p_booking),'[]'),'bills',coalesce((select jsonb_agg(to_jsonb(b) order by revision desc) from public.job_bills b where booking_id=p_booking),'[]'),
 'invoices',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'number',i.number,'status',i.status,'issued_at',i.issued_at,'total_paise',i.snapshot->'total_paise')) from public.invoices i where booking_id=p_booking),'[]'),'verification',
 (select jsonb_build_object('verified_at',v.verified_at,'method',v.method) from public.job_start_verifications v where booking_id=p_booking));
end $$;
create or replace function public.invoice_record(p_invoice uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare inv public.invoices;
begin
 select * into inv from public.invoices where id=p_invoice;
 if not public.account_active() or not public.can_message_booking(inv.booking_id) then raise exception 'Invoice unavailable to your account.' using errcode='42501';end if;
 return to_jsonb(inv)||jsonb_build_object('payment_status',(select payment_status from public.bookings where id=inv.booking_id),'items',(select jsonb_agg(jsonb_build_object('label',label,'amount_paise',amount_paise)) from public.invoice_items where invoice_id=inv.id));
end $$;
create or replace function public.invoice_history() returns setof jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.account_active() then raise exception 'Sign in.' using errcode='42501';end if;
 return query select jsonb_build_object('id',i.id,'booking_id',i.booking_id,'number',i.number,'issued_at',i.issued_at,'status',i.status,'total_paise',i.snapshot->'total_paise','provider_name',i.snapshot->>'provider_name','payment_status',b.payment_status)
 from public.invoices i join public.bookings b on b.id=i.booking_id where b.customer_id=auth.uid() or b.provider_id=auth.uid() or public.is_admin() order by issued_at desc;
end $$;
create or replace function public.submit_commission_payment(p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare statement jsonb;payment uuid;amount bigint:=(p_data->>'amount_paise')::bigint;
begin
 perform private.take_rate_limit();perform 1 from public.provider_profiles where user_id=auth.uid() for update;
 select s into statement from private.commission_statements(auth.uid()) s where s->>'period_id'=p_data->>'period_id';
 if statement is null or amount is null or amount<=0 or amount>(statement->>'outstanding_paise')::bigint then raise exception 'Enter a payment amount within the actual outstanding commission.';end if;
 if exists(select 1 from public.provider_commission_payments where provider_id=auth.uid() and period_id=(p_data->>'period_id')::uuid and status='awaiting_verification') then raise exception 'A payment for this period is already awaiting verification.';end if;
 if not(private.ops()->'payment_methods' ? (p_data->>'method')) or length(trim(private.ops()->>'payment_instructions'))=0 then raise exception 'The administrator must configure the business payment methods and account details.';end if;
 if not exists(select 1 from public.media_assets where id=(p_data->>'proof_id')::uuid and owner_id=auth.uid() and kind='commission') then raise exception 'Upload your private payment proof first.';end if;
 if length(trim(coalesce(p_data->>'reference',''))) not between 3 and 200 or(p_data->>'paid_at')::timestamptz>now()+interval '5 minutes' then raise exception 'Enter the actual transaction reference and date.';end if;
 insert into public.provider_commission_payments(provider_id,period_id,amount_paise,method,reference,paid_at,proof_id) values(auth.uid(),(p_data->>'period_id')::uuid,amount,p_data->>'method',trim(p_data->>'reference'),(p_data->>'paid_at')::timestamptz,(p_data->>'proof_id')::uuid) returning id into payment;
 perform private.financial_audit('Submit commission payment proof',null,jsonb_build_object('payment_id',payment,'amount_paise',amount));return payment;
end $$;
create or replace function public.admin_review_commission(p_payment uuid,p_approve boolean,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare payment public.provider_commission_payments;statement jsonb;
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 select * into payment from public.provider_commission_payments where id=p_payment for update;
 if payment.id is null or payment.status<>'awaiting_verification' then raise exception 'This payment is no longer awaiting verification.';end if;
 perform 1 from public.provider_profiles where user_id=payment.provider_id for update;
 if length(trim(p_reason)) not between 5 and 2000 then raise exception 'Record the verification evidence or rejection reason.';end if;
 select s into statement from private.commission_statements(payment.provider_id) s where s->>'period_id'=payment.period_id::text;
 if p_approve and payment.amount_paise>(statement->>'outstanding_paise')::bigint then raise exception 'The submitted amount exceeds the current undisputed balance. Reject it for reconciliation.';end if;
 update public.provider_commission_payments set status=case when p_approve then 'approved' else 'rejected' end,reviewed_at=now(),reviewed_by=auth.uid(),review_note=p_reason where id=payment.id;
 perform private.financial_audit(case when p_approve then 'Approve verified commission payment' else 'Reject commission payment' end,null,jsonb_build_object('payment_id',payment.id,'provider_id',payment.provider_id,'amount_paise',payment.amount_paise,'reason',p_reason));
 perform private.reconcile_provider(payment.provider_id);
 perform private.notify(payment.provider_id,case when p_approve then 'Your commission payment was verified by the administrator' else 'Commission payment rejected: review the reason and submit valid proof again' end);
end $$;
create or replace function public.admin_verify_cash(p_booking uuid,p_amount bigint,p_reference text) returns void language plpgsql security definer set search_path='' as $$
declare total bigint;
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 perform 1 from public.bookings where id=p_booking for update;
 if exists(select 1 from public.bookings where id=p_booking and payment_status='successful') then raise exception 'Payment has already been verified.';end if;
 select total_paise into total from public.job_bills where booking_id=p_booking and status='confirmed';
 if total is null or p_amount<>total or length(trim(p_reference))<5 then raise exception 'Confirm the exact bill amount and verified cash receipt reference.';end if;
 insert into public.cash_payment_verifications(booking_id,amount_paise,reference,verified_by) values(p_booking,total,p_reference,auth.uid());
 update public.bookings set payment_status='successful',payment_method='cash' where id=p_booking;
 perform private.financial_audit('Verified cash payment',p_booking,jsonb_build_object('amount_paise',total,'reference',p_reference));
end $$;
create or replace function private.hold_disputed_commission() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='disputed' or new.payment_status in ('refunded','partially_refunded') then update public.provider_commissions set status='held' where booking_id=new.id and status='due';end if;return new;
end $$;
drop trigger if exists hold_disputed_commission on public.bookings;
create trigger hold_disputed_commission after update on public.bookings for each row execute function private.hold_disputed_commission();
revoke execute on function public.request_additional_charge(uuid,bigint,text),public.respond_additional_charge(uuid,text),public.submit_final_bill(uuid,jsonb),public.respond_final_bill(uuid,text,text),public.admin_resolve_bill(uuid,text,text),public.booking_finances(uuid),public.invoice_record(uuid),public.invoice_history(),public.submit_commission_payment(jsonb),public.admin_review_commission(uuid,boolean,text),public.admin_verify_cash(uuid,bigint,text) from public,anon;
grant execute on function public.request_additional_charge(uuid,bigint,text),public.respond_additional_charge(uuid,text),public.submit_final_bill(uuid,jsonb),public.respond_final_bill(uuid,text,text),public.admin_resolve_bill(uuid,text,text),public.booking_finances(uuid),public.invoice_record(uuid),public.invoice_history(),public.submit_commission_payment(jsonb),public.admin_review_commission(uuid,boolean,text),public.admin_verify_cash(uuid,bigint,text) to authenticated;
revoke execute on all functions in schema private from public,anon,authenticated;
notify pgrst, 'reload schema';

-- Migration: 20261116000500_private_voice.sql
-- Audio is end-to-end WebRTC media, never uploaded to PostgreSQL or recorded here.
create table if not exists public.voice_calls(id uuid primary key default gen_random_uuid(),booking_id uuid not null references public.bookings(id) on delete cascade,caller_id uuid not null references public.users(id),callee_id uuid not null references public.users(id),status text not null default 'ringing' check(status in ('ringing','accepted','active','ended','rejected','missed','failed')),created_at timestamptz not null default now(),accepted_at timestamptz,connected_at timestamptz,ended_at timestamptz,ended_reason text not null default '',caller_seen_at timestamptz not null default now(),callee_seen_at timestamptz,check(caller_id<>callee_id));
create index if not exists voice_calls_participants on public.voice_calls(caller_id,callee_id,created_at desc);
create index if not exists voice_calls_callee_active on public.voice_calls(callee_id,status);
create table if not exists public.voice_signals(id bigint generated always as identity primary key,call_id uuid not null references public.voice_calls(id) on delete cascade,sender_id uuid not null references public.users(id),recipient_id uuid not null references public.users(id),kind text not null check(kind in ('offer','answer','candidate')),payload jsonb not null,created_at timestamptz not null default now());
create index if not exists voice_signals_delivery on public.voice_signals(call_id,recipient_id,id);
create table if not exists private.voice_user_slots(user_id uuid primary key references public.users(id) on delete cascade,call_id uuid not null references public.voice_calls(id) on delete cascade);
create table if not exists private.voice_rate_windows(user_id uuid,minute bigint,hits int not null,primary key(user_id,minute));
alter table public.voice_calls enable row level security;alter table public.voice_signals enable row level security;
revoke all on public.voice_calls,public.voice_signals from anon,authenticated;
revoke all on private.voice_user_slots,private.voice_rate_windows from public,anon,authenticated;
create or replace function private.call_allowed(p_call uuid,p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.voice_calls c join public.bookings b on b.id=c.booking_id join public.users u on u.id=p_user cross join public.website_configuration w
 where c.id=p_call and u.is_active and not w.maintenance_mode and w.provider_portal_enabled and w.customer_portal_enabled and(private.ops()->>'calling_enabled')::boolean and p_user in (c.caller_id,c.callee_id)
 and b.accepted_at is not null and b.status in(select jsonb_array_elements_text(private.ops()->'call_statuses')) and((c.caller_id=b.customer_id and c.callee_id=b.provider_id) or(c.callee_id=b.customer_id and c.caller_id=b.provider_id)))
$$;
create or replace function private.finish_call(p_call uuid,p_status text,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare c public.voice_calls;
begin
 update public.voice_calls set status=p_status,ended_at=now(),ended_reason=left(p_reason,100) where id=p_call and status in ('ringing','accepted','active') returning * into c;
 if c.id is not null then
  delete from private.voice_user_slots where call_id=c.id;delete from public.voice_signals where call_id=c.id;
  if p_status='missed' then perform private.notify(c.callee_id,'Missed Local Mate booking call',c.booking_id);end if;
 end if;
end $$;
create or replace function private.expire_calls(p_user uuid default null) returns void language plpgsql security definer set search_path='' as $$
declare c public.voice_calls;
begin
 for c in select * from public.voice_calls where status in ('ringing','accepted','active') and(p_user is null or p_user in(caller_id,callee_id)) for update skip locked loop
  if not private.call_allowed(c.id,c.caller_id) or not private.call_allowed(c.id,c.callee_id) then perform private.finish_call(c.id,'ended','booking_or_account_permission_changed');
  elsif c.status='ringing' and c.created_at<now()-make_interval(secs=>(private.ops()->>'ring_seconds')::int) then perform private.finish_call(c.id,'missed','unanswered');
  elsif c.caller_seen_at<now()-make_interval(secs=>(private.ops()->>'call_heartbeat_seconds')::int) or(c.status<>'ringing' and coalesce(c.callee_seen_at,c.accepted_at)<now()-make_interval(secs=>(private.ops()->>'call_heartbeat_seconds')::int)) then perform private.finish_call(c.id,'ended','session_disconnected');
  elsif c.created_at<now()-make_interval(secs=>(private.ops()->>'call_max_seconds')::int) then perform private.finish_call(c.id,'ended','duration_limit');end if;
 end loop;
 delete from public.voice_signals where created_at<now()-interval '10 minutes';
end $$;
create or replace function private.voice_dto(p_call uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',c.id,'booking_id',c.booking_id,'booking_reference',upper(left(c.booking_id::text,8)),'caller_id',c.caller_id,'callee_id',c.callee_id,
 'caller_name',case when c.caller_id=b.customer_id then coalesce(nullif(private.safe_text((select name from public.users where id=b.customer_id)),''),'Customer · '||upper(left(b.id::text,8))) else private.safe_text(coalesce(nullif(p.business_name,''),'Service provider')) end,
 'callee_name',case when c.callee_id=b.customer_id then coalesce(nullif(private.safe_text((select name from public.users where id=b.customer_id)),''),'Customer · '||upper(left(b.id::text,8))) else private.safe_text(coalesce(nullif(p.business_name,''),'Service provider')) end,
 'status',c.status,'created_at',c.created_at,'accepted_at',c.accepted_at,'connected_at',c.connected_at,'ended_at',c.ended_at,'ended_reason',c.ended_reason,
 'duration_seconds',case when c.connected_at is not null then greatest(0,floor(extract(epoch from(coalesce(c.ended_at,now())-c.connected_at)))) else 0 end)
 from public.voice_calls c join public.bookings b on b.id=c.booking_id left join public.provider_profiles p on p.user_id=b.provider_id where c.id=p_call
$$;
create or replace function public.start_voice_call(p_booking uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.bookings;other uuid;call_id uuid;
begin
 perform private.take_rate_limit();perform private.expire_calls(auth.uid());
 select * into b from public.bookings where id=p_booking for share;
 if auth.uid() not in(b.customer_id,b.provider_id) or b.provider_id is null or b.accepted_at is null then raise exception 'Calls are private to the customer and accepting provider.' using errcode='42501';end if;
 if not(private.ops()->>'calling_enabled')::boolean or not(b.status in(select jsonb_array_elements_text(private.ops()->'call_statuses'))) or exists(select 1 from public.website_configuration where id and(maintenance_mode or not customer_portal_enabled or not provider_portal_enabled)) then raise exception 'Calling is unavailable for this booking. Use in-app chat.';end if;
 other:=case when auth.uid()=b.customer_id then b.provider_id else b.customer_id end;
 if not exists(select 1 from public.users where id=other and is_active) then raise exception 'This participant is unavailable.';end if;
 -- Lock participants in a fixed order to prevent double ringing and crossed calls.
 perform pg_advisory_xact_lock(hashtextextended('voice-user:'||least(auth.uid(),other)::text,0));
 perform pg_advisory_xact_lock(hashtextextended('voice-user:'||greatest(auth.uid(),other)::text,0));
 if exists(select 1 from private.voice_user_slots where user_id in(auth.uid(),other)) then raise exception 'One participant is already in a Local Mate call. Try chat or call again later.';end if;
 insert into public.voice_calls(booking_id,caller_id,callee_id) values(b.id,auth.uid(),other) returning id into call_id;
 insert into private.voice_user_slots(user_id,call_id) values(auth.uid(),call_id),(other,call_id);
 perform private.notify(other,'Incoming Local Mate booking call',b.id);return private.voice_dto(call_id);
end $$;
create or replace function public.voice_call_action(p_call uuid,p_action text,p_reason text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.voice_calls;
begin
 if not public.account_active() then raise exception 'Sign in.' using errcode='42501';end if;
 perform private.expire_calls(auth.uid());select * into c from public.voice_calls where id=p_call for update;
 if c.id is null or auth.uid() not in(c.caller_id,c.callee_id) then raise exception 'This call is private.' using errcode='42501';end if;
 if p_action='end' then perform private.finish_call(c.id,'ended',case when p_reason='session_ended' then 'session_ended' else 'participant_ended' end);
 elsif p_action='reject' then
  if c.callee_id<>auth.uid() or c.status<>'ringing' then raise exception 'This call is no longer ringing.';end if;perform private.finish_call(c.id,'rejected','callee_rejected');
 elsif p_action='accept' then
  if c.callee_id<>auth.uid() or c.status<>'ringing' or not private.call_allowed(c.id,auth.uid()) then raise exception 'This call cannot be accepted.';end if;
  update public.voice_calls set status='accepted',accepted_at=now(),callee_seen_at=now() where id=c.id;
 elsif p_action='connected' then
  if c.status not in ('accepted','active') or not private.call_allowed(c.id,auth.uid()) then raise exception 'This call is unavailable.';end if;
  update public.voice_calls set status='active',connected_at=coalesce(connected_at,now()) where id=c.id;
 elsif p_action='failed' then perform private.finish_call(c.id,'failed','connection_failed');
 elsif p_action<>'heartbeat' then raise exception 'Unknown call action.';
 end if;
 if p_action in ('heartbeat','connected','accept') and c.status in ('ringing','accepted','active') then
  if not private.call_allowed(c.id,auth.uid()) then perform private.finish_call(c.id,'ended','permission_changed');
  else update public.voice_calls set caller_seen_at=case when caller_id=auth.uid() then now() else caller_seen_at end,callee_seen_at=case when callee_id=auth.uid() then now() else callee_seen_at end where id=c.id;end if;
 end if;
 return private.voice_dto(c.id);
end $$;
create or replace function public.voice_call_state(p_call uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not public.account_active() or not exists(select 1 from public.voice_calls where id=p_call and auth.uid() in(caller_id,callee_id)) then raise exception 'This call is private.' using errcode='42501';end if;
 perform private.expire_calls(auth.uid());return private.voice_dto(p_call);
end $$;
create or replace function public.voice_call_history(p_booking uuid default null) returns setof jsonb language plpgsql security definer set search_path='' as $$
begin
 if not public.account_active() then raise exception 'Sign in.' using errcode='42501';end if;
 perform private.expire_calls(auth.uid());
 return query select private.voice_dto(c.id) from public.voice_calls c where(p_booking is null or c.booking_id=p_booking) and(auth.uid() in(c.caller_id,c.callee_id) or public.is_admin()) order by c.created_at desc limit 100;
end $$;
create or replace function public.voice_incoming() returns setof jsonb language plpgsql security definer set search_path='' as $$
begin
 if not public.account_active() then raise exception 'Sign in.' using errcode='42501';end if;
 perform private.expire_calls(auth.uid());return query select private.voice_dto(c.id) from public.voice_calls c where c.callee_id=auth.uid() and c.status='ringing' and private.call_allowed(c.id,auth.uid());
end $$;
create or replace function public.send_voice_signal(p_call uuid,p_kind text,p_payload jsonb) returns bigint language plpgsql security definer set search_path='' as $$
declare c public.voice_calls;signal_id bigint;hits int;minute_now bigint:=floor(extract(epoch from now())/60);clean jsonb;
begin
 if not public.account_active() or not private.call_allowed(p_call,auth.uid()) then raise exception 'This call is private.' using errcode='42501';end if;
 select * into c from public.voice_calls where id=p_call for share;
 if c.status not in ('ringing','accepted','active') then raise exception 'This call has ended.';end if;
 if pg_column_size(p_payload)>20000 then raise exception 'Signalling payload is too large.';end if;
 insert into private.voice_rate_windows(user_id,minute,hits) values(auth.uid(),minute_now,1) on conflict(user_id,minute) do update set hits=private.voice_rate_windows.hits+1 where private.voice_rate_windows.hits<180 returning private.voice_rate_windows.hits into hits;
 if hits is null then raise exception 'Too many signalling messages.';end if;
 if p_kind in ('offer','answer') then
  if(p_kind='offer' and(c.caller_id<>auth.uid() or c.status not in ('ringing','accepted'))) or(p_kind='answer' and(c.callee_id<>auth.uid() or c.status<>'accepted')) then raise exception 'Signalling role mismatch.' using errcode='42501';end if;
  if jsonb_typeof(p_payload->'sdp')<>'string' or p_payload->>'type'<>p_kind or(p_payload->>'sdp')!~ E'^v=0[\\r\\n]' or(p_payload->>'sdp')~E'(^|[\\r\\n])m=(video|application)' then raise exception 'An audio-only SDP message is required.';end if;
  clean:=jsonb_build_object('type',p_kind,'sdp',p_payload->>'sdp');
 elsif p_kind='candidate' then
  if jsonb_typeof(p_payload->'candidate')<>'string' or length(p_payload->>'candidate')>4000 then raise exception 'Invalid ICE candidate.';end if;
  clean:=jsonb_build_object('candidate',p_payload->>'candidate','sdpMid',p_payload->'sdpMid','sdpMLineIndex',p_payload->'sdpMLineIndex','usernameFragment',p_payload->'usernameFragment');
 else raise exception 'Unknown signal type.';end if;
 insert into public.voice_signals(call_id,sender_id,recipient_id,kind,payload) values(c.id,auth.uid(),case when c.caller_id=auth.uid() then c.callee_id else c.caller_id end,p_kind,clean) returning id into signal_id;return signal_id;
end $$;
create or replace function public.receive_voice_signals(p_call uuid,p_after bigint default 0) returns setof jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.account_active() or not private.call_allowed(p_call,auth.uid()) then raise exception 'This call is private.' using errcode='42501';end if;
 if not exists(select 1 from public.voice_calls where id=p_call and(status in ('accepted','active') or caller_id=auth.uid())) then return;end if;
 return query select jsonb_build_object('id',s.id,'kind',s.kind,'payload',s.payload) from public.voice_signals s where s.call_id=p_call and s.recipient_id=auth.uid() and s.id>p_after order by s.id limit 100;
end $$;
create or replace function private.stop_unauthorized_calls() returns trigger language plpgsql security definer set search_path='' as $$
declare c public.voice_calls;scope_user uuid;scope_booking uuid;
begin
 if tg_table_name='users' then scope_user:=new.id;elsif tg_table_name='bookings' then scope_booking:=new.id;end if;
 for c in select * from public.voice_calls where(scope_user is null or scope_user in(caller_id,callee_id)) and(scope_booking is null or booking_id=scope_booking) and status in ('ringing','accepted','active') loop
  if not private.call_allowed(c.id,c.caller_id) or not private.call_allowed(c.id,c.callee_id) then perform private.finish_call(c.id,'ended','booking_or_account_permission_changed');end if;
 end loop;return new;
end $$;
do $$ declare t text;begin
 foreach t in array array['users','bookings','website_configuration','operations_configuration'] loop
  execute format('drop trigger if exists stop_unauthorized_calls on public.%I',t);
  execute format('create trigger stop_unauthorized_calls after update on public.%I for each row execute function private.stop_unauthorized_calls()',t);
 end loop;
end $$;
drop policy if exists voice_metadata_read on public.voice_calls;
do $setup_policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='voice_calls' and policyname='voice_metadata_read') then
  create policy voice_metadata_read on public.voice_calls for select to authenticated using(public.account_active() and auth.uid() in(caller_id,callee_id));
 end if;
end $setup_policy$;
grant select(id,booking_id,caller_id,callee_id,status,created_at,accepted_at,connected_at,ended_at,ended_reason) on public.voice_calls to authenticated;
-- Signals are exposed only through participant-checked RPCs. Administrators see metadata, never SDP/audio.
revoke execute on function public.start_voice_call(uuid),public.voice_call_action(uuid,text,text),public.voice_call_state(uuid),public.voice_call_history(uuid),public.voice_incoming(),public.send_voice_signal(uuid,text,jsonb),public.receive_voice_signals(uuid,bigint) from public,anon;
grant execute on function public.start_voice_call(uuid),public.voice_call_action(uuid,text,text),public.voice_call_state(uuid),public.voice_call_history(uuid),public.voice_incoming(),public.send_voice_signal(uuid,text,jsonb),public.receive_voice_signals(uuid,bigint) to authenticated;
revoke execute on all functions in schema private from public,anon,authenticated;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='voice_calls') then alter publication supabase_realtime add table public.voice_calls;end if;
end $$;
notify pgrst, 'reload schema';

-- Migration: 20261116000600_media_and_maintenance.sql
create or replace function public.register_media(p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare kind text:=p_data->>'kind';booking uuid:=nullif(p_data->>'booking_id','')::uuid;asset uuid;
begin
 perform private.take_rate_limit();
 if kind in ('booking','chat','before','after') then
  if not public.can_message_booking(booking) then raise exception 'Only booking participants can upload here.' using errcode='42501';end if;
  if kind='booking' and not exists(select 1 from public.bookings where id=booking and customer_id=auth.uid()) then raise exception 'Only the customer can add request photos.';end if;
 elsif kind in ('commission','logo') then
  if not exists(select 1 from public.provider_profiles where user_id=auth.uid()) then raise exception 'Provider account required.';end if;
 else raise exception 'Unsupported image purpose.';end if;
 if (p_data->>'object_path') not like auth.uid()::text||'/%' then raise exception 'Invalid private upload path.';end if;
 insert into public.media_assets(owner_id,booking_id,kind,object_path,byte_size) values(auth.uid(),booking,kind,p_data->>'object_path',(p_data->>'byte_size')::int) returning id into asset;
 return asset;
end $$;
create or replace function public.read_media(p_asset uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare a public.media_assets;
begin
 if not public.account_active() then raise exception 'Sign in.' using errcode='42501';end if;
 select * into a from public.media_assets where id=p_asset;
 if a.id is null then raise exception 'Image not found.';end if;
 if not(public.is_admin() or a.owner_id=auth.uid() or(a.review_status='approved' and a.kind not in ('commission','logo') and public.can_view_booking(a.booking_id)) or(a.kind='logo' and a.review_status='approved' and exists(select 1 from public.provider_profiles where logo_id=a.id and status='approved'))) then raise exception 'This image is private.' using errcode='42501';end if;
 return jsonb_build_object('id',a.id,'object_path',a.object_path,'mime',a.mime,'review_status',a.review_status,'kind',a.kind);
end $$;
create or replace function public.media_list(p_booking uuid default null) returns setof jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.account_active() then raise exception 'Sign in.' using errcode='42501';end if;
 return query select jsonb_build_object('id',a.id,'booking_id',a.booking_id,'owner_id',a.owner_id,'kind',a.kind,'review_status',a.review_status,'review_note',private.safe_text(a.review_note),'created_at',a.created_at)
 from public.media_assets a where(p_booking is null or a.booking_id=p_booking) and(public.is_admin() or a.owner_id=auth.uid() or(a.kind not in ('commission','logo') and a.review_status='approved' and public.can_view_booking(a.booking_id))) order by a.created_at desc limit 200;
end $$;
create or replace function public.admin_review_media(p_asset uuid,p_approve boolean,p_note text) returns void language plpgsql security definer set search_path='' as $$
declare a public.media_assets;
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 if length(trim(p_note))<5 then raise exception 'Record the privacy review result.';end if;
 select * into a from public.media_assets where id=p_asset for update;
 if a.id is null then raise exception 'Image not found.';end if;
 update public.media_assets set review_status=case when p_approve then 'approved' else 'rejected' end,review_note=p_note where id=a.id;
 if p_approve and a.kind='logo' then update public.provider_profiles set logo_id=a.id where user_id=a.owner_id;end if;
 if a.booking_id is not null then insert into public.booking_events(booking_id,kind) values(a.booking_id,'media_reviewed');end if;
 perform private.audit('Image privacy review',a.id::text);perform private.notify(a.owner_id,'Image privacy review: '||case when p_approve then 'approved' else 'rejected' end,a.booking_id);
end $$;
create or replace function public.send_attachment(p_booking uuid,p_asset uuid,p_body text default 'Image attachment') returns bigint language plpgsql security definer set search_path='' as $$
declare mid bigint;
begin
 perform private.take_rate_limit();if not public.can_message_booking(p_booking) then raise exception 'This conversation is private.' using errcode='42501';end if;
 if not exists(select 1 from public.media_assets where id=p_asset and owner_id=auth.uid() and booking_id=p_booking and kind='chat') then raise exception 'Upload your image to this conversation first.';end if;
 perform private.check_private_text(p_body);
 insert into public.messages(booking_id,sender_id,body,attachment_id) values(p_booking,auth.uid(),p_body,p_asset) returning id into mid;return mid;
end $$;
create or replace function public.provider_job_history() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.account_active() then raise exception 'Sign in.' using errcode='42501';end if;
 return jsonb_build_object('offers',coalesce((select jsonb_agg(jsonb_build_object('booking_id',o.booking_id,'status',o.status,'offered_at',o.offered_at,'responded_at',o.responded_at,'service_name',s.name,'location',b.location,'scheduled_at',b.scheduled_at)) from public.booking_provider_offers o join public.bookings b on b.id=o.booking_id join public.services s on s.id=b.service_id where o.provider_id=auth.uid()),'[]'),
 'jobs',coalesce((select jsonb_agg(public.safe_booking(b.id)) from public.bookings b where b.provider_id=auth.uid()),'[]'));
end $$;
create or replace function public.admin_operations_logs() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 return jsonb_build_object('offers',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from public.booking_provider_offers order by offered_at desc limit 200) x),'[]'),
 'assignments',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from public.booking_assignment_history order by id desc limit 200) x),'[]'),
 'otp',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from public.job_start_otp_logs order by id desc limit 200) x),'[]'),
 'financial',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from public.financial_audit_logs order by id desc limit 200) x),'[]'),
 'suspensions',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from public.provider_suspension_records order by created_at desc limit 200) x),'[]'),
 'reactivations',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from public.provider_reactivation_records order by id desc limit 200) x),'[]'));
end $$;
create or replace function public.admin_reassign_booking(p_booking uuid,p_provider uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare b public.bookings;
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 if length(trim(p_reason))<10 then raise exception 'Record the intervention reason.';end if;
 select * into b from public.bookings where id=p_booking for update;
 if b.status not in ('requested','confirmed','quote_sent') or not public.provider_eligible(p_provider,b.service_id,b.location) or b.customer_id=p_provider then raise exception 'Choose an eligible provider before work begins.';end if;
 update public.quotations set status='rejected' where booking_id=b.id and status='pending';
 update public.bookings set provider_id=p_provider,accepted_at=null,status='requested',requires_quote=true,request_expired=false where id=b.id;
 delete from public.booking_assignments where booking_id=b.id;
 update public.booking_provider_offers set status='lost',responded_at=now() where booking_id=b.id;
 insert into public.booking_provider_offers(booking_id,provider_id) values(b.id,p_provider) on conflict(booking_id,provider_id) do update set status='pending',responded_at=null,offered_at=now();
 insert into public.booking_assignment_history(booking_id,provider_id,actor_id,event) values(b.id,p_provider,auth.uid(),'admin_pending_confirmation');
 perform private.financial_audit('Administrator booking intervention',b.id,jsonb_build_object('provider_id',p_provider,'reason',p_reason));
 perform private.notify(p_provider,'Administrator booking assignment awaits your acceptance',b.id);perform private.notify(b.customer_id,'An administrator is coordinating provider confirmation',b.id);
end $$;
create or replace function public.admin_assign(p_booking uuid,p_provider uuid) returns void language plpgsql security definer set search_path='' as $$ begin raise exception 'Use the audited assignment form and record an intervention reason.';end $$;
create or replace function private.run_maintenance() returns jsonb language plpgsql security definer set search_path='' as $$
declare provider uuid;expired_count int:=0;request_id uuid;
begin
 if private.ops()->>'request_expiry_mode'='expire' then
  for request_id in select id from public.bookings where provider_id is null and status='requested' and not request_expired and request_expires_at<now() for update skip locked loop
   update public.bookings set request_expired=true where id=request_id;
   update public.booking_provider_offers set status='expired',responded_at=now() where booking_id=request_id and status='pending';
   perform private.notify((select customer_id from public.bookings where id=request_id),'No provider accepted before the request deadline. You can retry from your booking.',request_id);expired_count:=expired_count+1;
  end loop;
 end if;
 for provider in select user_id from public.provider_profiles loop perform private.reconcile_provider(provider);end loop;
 perform private.expire_calls();delete from public.booking_locations where recorded_at<now()-interval '2 minutes';
 delete from private.voice_rate_windows where minute<floor(extract(epoch from now())/60)-60;
 update private.job_start_otps set ciphertext='' where expires_at<now() and ciphertext<>'';
 return jsonb_build_object('expired_requests',expired_count,'completed_at',now());
end $$;
create or replace function public.service_maintenance() returns jsonb language plpgsql security definer set search_path='' as $$
begin if auth.role()<>'service_role' then raise exception 'Server authorization required.' using errcode='42501';end if;return private.run_maintenance();end $$;
-- Storage objects are never publicly listed or signed into long-lived URLs.
do $$ begin
 if exists(select 1 from information_schema.tables where table_schema='storage' and table_name='buckets') then
  insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('local-mate-private','local-mate-private',false,5242880,array['image/jpeg']) on conflict(id) do update set public=false;
 end if;
end $$;
revoke execute on function public.register_media(jsonb),public.read_media(uuid),public.media_list(uuid),public.admin_review_media(uuid,boolean,text),public.send_attachment(uuid,uuid,text),public.provider_job_history(),public.admin_operations_logs(),public.admin_reassign_booking(uuid,uuid,text) from public,anon;
grant execute on function public.register_media(jsonb),public.read_media(uuid),public.media_list(uuid),public.admin_review_media(uuid,boolean,text),public.send_attachment(uuid,uuid,text),public.provider_job_history(),public.admin_operations_logs(),public.admin_reassign_booking(uuid,uuid,text) to authenticated;
revoke execute on function public.service_maintenance() from public,anon,authenticated;grant execute on function public.service_maintenance() to service_role;
revoke execute on all functions in schema private from public,anon,authenticated;
notify pgrst, 'reload schema';

-- Migration: 20261116000700_operations_hardening.sql
-- A provider cannot register a nonexistent receipt through a browser RPC.
create or replace function public.service_register_media(p_actor uuid,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare kind text:=p_data->>'kind';booking uuid:=nullif(p_data->>'booking_id','')::uuid;asset uuid;
begin
 if auth.role()<>'service_role' or not exists(select 1 from public.users where id=p_actor and is_active) then raise exception 'Server authorization required.' using errcode='42501';end if;
 if kind in ('booking','chat','before','after') then
  if not exists(select 1 from public.bookings where id=booking and(p_actor=customer_id or p_actor=provider_id)) then raise exception 'Only booking participants can upload here.' using errcode='42501';end if;
  if kind='booking' and not exists(select 1 from public.bookings where id=booking and customer_id=p_actor) then raise exception 'Only the customer can upload request photos.';end if;
 elsif kind in ('commission','logo') then
  if not exists(select 1 from public.provider_profiles where user_id=p_actor) then raise exception 'Provider account required.';end if;
 else raise exception 'Unsupported image purpose.';end if;
 if p_data->>'object_path' not like p_actor::text||'/%' then raise exception 'Invalid upload path.';end if;
 insert into public.media_assets(owner_id,booking_id,kind,object_path,byte_size) values(p_actor,booking,kind,p_data->>'object_path',(p_data->>'byte_size')::int) returning id into asset;return asset;
end $$;
revoke execute on function public.register_media(jsonb) from public,anon,authenticated;
revoke execute on function public.service_register_media(uuid,jsonb) from public,anon,authenticated;grant execute on function public.service_register_media(uuid,jsonb) to service_role;
create or replace function public.admin_financial_overview() returns setof jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 return query select to_jsonb(j)||jsonb_build_object('provider_name',private.safe_text(coalesce(nullif(p.business_name,''),'Service provider'))) from public.job_bills j join public.provider_profiles p on p.user_id=j.provider_id order by j.created_at desc limit 300;
end $$;
revoke execute on function public.admin_financial_overview() from public,anon;grant execute on function public.admin_financial_overview() to authenticated;
-- Existing old payment orders retain their exact historic amount. New orders use the confirmed bill.
alter table public.payments add column if not exists amount_paise bigint check(amount_paise>0);
update public.payments set amount_paise=amount::bigint*100 where amount_paise is null;
create or replace function public.reserve_payment(p_booking uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.bookings;p public.payments;total bigint;
begin
 perform private.take_rate_limit();select * into b from public.bookings where id=p_booking for update;
 if b.customer_id is distinct from auth.uid() then raise exception 'Only the customer can pay this booking.' using errcode='42501';end if;
 select total_paise into total from public.job_bills where booking_id=b.id and status='confirmed';
 if b.status<>'work_completed' or total is null or total<=0 or b.payment_status in ('successful','refunded','partially_refunded') then raise exception 'A confirmed, unpaid final bill is required.';end if;
 insert into public.payments(booking_id,amount,amount_paise) values(b.id,ceil(total/100.0)::int,total) on conflict(booking_id) do nothing;
 select * into p from public.payments where booking_id=b.id for update;
 if coalesce(p.amount_paise,p.amount::bigint*100)<>total then raise exception 'The existing payment order needs administrator reconciliation.';end if;
 return to_jsonb(p);
end $$;
create or replace function public.record_payment_capture(p_order text,p_gateway_payment text,p_amount_paise bigint) returns void language plpgsql security definer set search_path='' as $$
declare p public.payments;
begin
 if auth.role()<>'service_role' then raise exception 'Server authorization required.' using errcode='42501';end if;
 select * into p from public.payments where gateway_order_id=p_order for update;
 if p.id is null or coalesce(p.amount_paise,p.amount::bigint*100)<>p_amount_paise then raise exception 'Captured amount does not match the exact reserved amount.';end if;
 if p.status='successful' and p.gateway_payment_id=p_gateway_payment then return;end if;
 if p.status in ('successful','refunded','partially_refunded') then raise exception 'This payment needs reconciliation.';end if;
 update public.payments set status='successful',gateway_payment_id=p_gateway_payment where id=p.id;
 update public.bookings set payment_status='successful',payment_method='online' where id=p.booking_id;
 perform private.financial_audit('Verified online payment capture',p.booking_id,jsonb_build_object('payment_id',p.id,'amount_paise',p_amount_paise),null);
end $$;
-- Non-overlapping, immutable recorded financial periods prevent timezone/week changes double-counting jobs.
do $$ begin
 if not exists(select 1 from pg_constraint where conname='commission_periods_do_not_overlap' and conrelid='public.weekly_commission_periods'::regclass) then
  alter table public.weekly_commission_periods add constraint commission_periods_do_not_overlap exclude using gist(tstzrange(starts_at,ends_at,'[)') with &&);
 end if;
end $$;
-- Curated provider directory never includes either party's phone, even if an old consent flag is set.
create or replace function public.provider_directory() returns setof jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('user_id',p.user_id,'name',private.safe_text(coalesce(nullif(p.business_name,''),u.name)),'business_name',private.safe_text(p.business_name),'category',private.safe_text(p.category),'description',private.safe_text(p.description),'experience',p.experience,'service_ids',p.service_ids,'locations',p.locations,'online',p.online and not private.commission_blocked(p.user_id),'logo_id',p.logo_id,
 'assessment_rating',p.assessment_rating,'rating_source',private.safe_text(p.rating_source),'rating',(select avg(r.rating) from public.reviews r where r.provider_id=p.user_id),'review_count',(select count(*) from public.reviews r where r.provider_id=p.user_id),'completed_job_count',(select count(*) from public.bookings b where b.provider_id=p.user_id and b.status='work_completed'),
 'offerings',coalesce((select jsonb_agg(to_jsonb(o)-'provider_id') from public.provider_offerings o join public.services s on s.id=o.service_id and s.active where o.provider_id=p.user_id),'[]'::jsonb))
 from public.provider_profiles p join public.users u on u.id=p.user_id cross join public.website_configuration cfg where p.status='approved' and u.is_active and cfg.id and not cfg.maintenance_mode and cfg.provider_portal_enabled order by p.business_name;
$$;
create or replace function public.provider_available_at(p_provider uuid,p_service text,p_location text,p_at timestamptz) returns boolean language sql stable security definer set search_path='' as $$
 select public.provider_eligible(p_provider,p_service,p_location) and(select count(*) from public.bookings b where provider_id=p_provider and status not in ('cancelled','disputed') and(scheduled_at at time zone(private.ops()->>'timezone'))::date=(p_at at time zone(private.ops()->>'timezone'))::date)<coalesce((select case when schedule->>'max_daily' ~ '^[0-9]+$' then (schedule->>'max_daily')::int else 5 end from public.provider_profiles where user_id=p_provider),5)
$$;
revoke execute on function public.provider_available_at(uuid,text,text,timestamptz) from public,anon;grant execute on function public.provider_available_at(uuid,text,text,timestamptz) to authenticated;
create or replace function public.can_view_booking(p_booking uuid) returns boolean language sql stable security definer set search_path='' as $$
 select public.account_active() and exists(select 1 from public.bookings b where b.id=p_booking and(public.is_admin() or b.customer_id=auth.uid() or b.provider_id=auth.uid() or(b.provider_id is null and b.status='requested' and not b.request_expired and(private.ops()->>'request_expiry_mode'='pending' or b.request_expires_at is null or b.request_expires_at>=now()) and public.provider_eligible(auth.uid(),b.service_id,b.location) and exists(select 1 from public.booking_provider_offers o where o.booking_id=b.id and o.provider_id=auth.uid() and o.status='pending'))))
$$;
-- Additive backups include actual business records, never OTP secrets, ICE/SDP, audio or storage bytes.
create or replace function public.export_marketplace() returns jsonb language plpgsql security definer set search_path='' as $$
declare t text;data jsonb;all_data jsonb:='{}';
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 foreach t in array array['users','provider_profiles','provider_offerings','locations','services','addresses','bookings','booking_status_history','booking_rejections','quotations','messages','notifications','reviews','payments','support_tickets','favourites','settings','website_configuration','admin_activity_logs','operations_configuration','booking_provider_offers','booking_assignments','booking_assignment_history','message_reads','media_assets','job_start_verifications','job_start_otp_logs','booking_charge_requests','job_bills','job_completion_records','invoices','invoice_items','provider_commission_rules','provider_commissions','weekly_commission_periods','provider_commission_payments','provider_suspension_records','provider_reactivation_records','provider_account_status_history','financial_audit_logs','cash_payment_verifications','payment_refund_verifications','voice_calls'] loop
  execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.%I x',t) into data;all_data:=all_data||jsonb_build_object(t,data);
 end loop;
 perform private.audit('Download complete application backup');return jsonb_build_object('format','local-mate-application-backup','version',3,'created_at',now(),'tables',all_data,'scope','Application records and call metadata only. No Auth passwords, OTP secrets, call signals/audio, GPS points or private image bytes.');
end $$;
revoke execute on all functions in schema private from public,anon,authenticated;
notify pgrst, 'reload schema';
create or replace function public.admin_overview() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 return jsonb_build_object('customers',(select count(*) from public.users u where not exists(select 1 from public.provider_profiles p where p.user_id=u.id)),'providers',(select count(*) from public.provider_profiles),'pending',(select count(*) from public.provider_profiles where status='pending'),'bookings',(select count(*) from public.bookings),'paid',coalesce((select sum(amount_paise)/100.0 from public.payments where status='successful'),0)+coalesce((select sum(amount_paise)/100.0 from public.cash_payment_verifications),0),'commission',(private.ops()->>'commission_percent')::numeric);
end $$;
revoke execute on function public.admin_overview() from public,anon;grant execute on function public.admin_overview() to authenticated;
create or replace function public.weekly_summary() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cfg jsonb:=private.ops();day date;start_day date;start_at timestamptz;end_at timestamptz;
begin
 if not public.account_active() then raise exception 'Sign in.' using errcode='42501';end if;
 day:=(now() at time zone(cfg->>'timezone'))::date;start_day:=day-((extract(dow from day)::int-(cfg->>'week_start_day')::int+7)%7);start_at:=start_day::timestamp at time zone(cfg->>'timezone');end_at:=(start_day+7)::timestamp at time zone(cfg->>'timezone');
 return jsonb_build_object('starts_at',start_at,'ends_at',end_at,'jobs_completed',(select count(*) from public.job_completion_records where provider_id=auth.uid() and completed_at>=start_at and completed_at<end_at),'billable_paise',coalesce((select sum(c.billable_paise) from public.provider_commissions c join public.weekly_commission_periods w on w.id=c.period_id where c.provider_id=auth.uid() and c.status<>'void' and w.starts_at=start_at),0),'commission_paise',coalesce((select sum(c.commission_paise) from public.provider_commissions c join public.weekly_commission_periods w on w.id=c.period_id where c.provider_id=auth.uid() and c.status='due' and w.starts_at=start_at),0),'next_deadline',end_at+make_interval(days=>(cfg->>'deadline_days')::int));
end $$;
revoke execute on function public.weekly_summary() from public,anon;grant execute on function public.weekly_summary() to authenticated;

-- Migration: 20261116000800_reset_operations.sql
do $$ begin
 if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='legacy_reset_marketplace') then
  alter function public.service_reset_marketplace(uuid,text) set schema private;
  alter function private.service_reset_marketplace(uuid,text) rename to legacy_reset_marketplace;
 end if;
end $$;
create or replace function public.service_reset_marketplace(p_actor uuid,p_confirmation text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.role()<>'service_role' or not exists(select 1 from auth.users u join private.admin_emails a on a.email=lower(u.email) join public.users p on p.id=u.id where u.id=p_actor and p.is_active and u.email_confirmed_at is not null and not exists(select 1 from private.login_accounts l where l.user_id=p_actor and l.must_change_password)) then raise exception 'Server administrator authorization required.' using errcode='42501';end if;
 if p_confirmation<>'DELETE ALL DATA' then raise exception 'Type DELETE ALL DATA to confirm.';end if;
 delete from public.voice_calls;delete from public.provider_commission_payments;delete from public.provider_commissions;delete from public.invoices;delete from public.job_bills;
 delete from public.payment_refund_verifications;delete from public.cash_payment_verifications;delete from public.job_completion_records;delete from public.job_start_otp_logs;delete from public.job_start_verifications;delete from private.job_start_otps;delete from public.booking_charge_requests;
 delete from public.provider_reactivation_records;delete from public.provider_suspension_records;delete from public.provider_account_status_history;delete from public.provider_commission_rules;delete from public.weekly_commission_periods;
 update public.provider_profiles set logo_id=null;delete from public.media_assets;delete from public.financial_audit_logs;delete from public.message_reads;delete from public.booking_provider_offers;delete from public.booking_assignments;delete from public.booking_assignment_history;delete from public.booking_events;
 perform private.legacy_reset_marketplace(p_actor,p_confirmation);
 delete from public.operations_configuration;
 insert into public.operations_configuration(id,config) values(true,'{
 "request_timeout_minutes":60,"request_expiry_mode":"pending","otp_ttl_seconds":300,"otp_max_attempts":5,
 "calling_enabled":true,"call_statuses":["confirmed","on_the_way","arrived","work_started","work_paused"],"ring_seconds":45,"call_max_seconds":3600,"call_heartbeat_seconds":45,"relay_only":false,
 "commission_enabled":true,"commission_percent":10,"commission_fixed_paise":0,"week_start_day":1,"timezone":"Asia/Kolkata","deadline_days":3,"grace_hours":48,"minimum_commission_paise":0,"auto_suspend":true,"auto_reactivate":true,
 "payment_ready_at":null,"payment_instructions":"","payment_methods":["bank_transfer","upi"],"tax_enabled":false,"tax_percent":0,"supplier_name":"","supplier_address":"","tax_registration":"","invoice_terms":"Payment status is recorded separately from this invoice."
}');
end $$;
revoke execute on function public.service_reset_marketplace(uuid,text) from public,anon,authenticated;grant execute on function public.service_reset_marketplace(uuid,text) to service_role;
revoke execute on all functions in schema private from public,anon,authenticated;
notify pgrst,'reload schema';

-- Migration: 20261116000900_session_refund_and_upload_guards.sql
create or replace function public.end_my_voice_calls() returns void language plpgsql security definer set search_path='' as $$
declare c public.voice_calls;
begin
 if auth.uid() is null then raise exception 'Sign in.' using errcode='42501';end if;
 for c in select * from public.voice_calls where auth.uid() in(caller_id,callee_id) and status in ('ringing','accepted','active') for update loop perform private.finish_call(c.id,'ended','session_ended');end loop;
end $$;
create or replace function public.authorize_upload(p_kind text,p_booking uuid default null) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.take_rate_limit();
 if p_kind in ('booking','chat','before','after') then
  if not public.can_message_booking(p_booking) then raise exception 'Only booking participants can upload here.' using errcode='42501';end if;
  if p_kind='booking' and not exists(select 1 from public.bookings where id=p_booking and customer_id=auth.uid()) then raise exception 'Only the customer can upload request photos.';end if;
 elsif p_kind in ('commission','logo') then
  if not exists(select 1 from public.provider_profiles where user_id=auth.uid()) then raise exception 'Provider account required.';end if;
 else raise exception 'Unsupported image purpose.';end if;
end $$;
create table if not exists public.payment_refund_verifications(id uuid primary key default gen_random_uuid(),booking_id uuid not null references public.bookings(id) on delete cascade,amount_paise bigint not null check(amount_paise>0),reference text not null unique,reason text not null,verified_by uuid not null references public.users(id),verified_at timestamptz not null default now());
alter table public.payment_refund_verifications enable row level security;revoke all on public.payment_refund_verifications from anon,authenticated;
create or replace function public.admin_verify_refund(p_booking uuid,p_amount bigint,p_reference text,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare paid bigint;refunded bigint;
begin
 perform private.take_rate_limit();if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 perform 1 from public.bookings where id=p_booking for update;
 select coalesce((select amount_paise from public.cash_payment_verifications where booking_id=p_booking),0)+coalesce((select amount_paise from public.payments where booking_id=p_booking and status in ('successful','refunded','partially_refunded')),0) into paid;
 select coalesce(sum(amount_paise),0) into refunded from public.payment_refund_verifications where booking_id=p_booking;
 if p_amount is null or p_amount<=0 or p_amount+refunded>paid or length(trim(p_reference))<5 or length(trim(p_reason))<10 then raise exception 'Record a verified refund within the actual paid amount, with reference and reason.';end if;
 insert into public.payment_refund_verifications(booking_id,amount_paise,reference,reason,verified_by) values(p_booking,p_amount,p_reference,p_reason,auth.uid());
 update public.bookings set payment_status=case when p_amount+refunded=paid then 'refunded' else 'partially_refunded' end where id=p_booking;
 update public.payments set status=case when p_amount+refunded=paid then 'refunded' else 'partially_refunded' end where booking_id=p_booking;
 perform private.financial_audit('Record verified refund',p_booking,jsonb_build_object('amount_paise',p_amount,'reference',p_reference,'reason',p_reason));
 perform private.reconcile_provider((select provider_id from public.bookings where id=p_booking));
end $$;
revoke execute on function public.end_my_voice_calls(),public.authorize_upload(text,uuid),public.admin_verify_refund(uuid,bigint,text,text) from public,anon;
grant execute on function public.end_my_voice_calls(),public.authorize_upload(text,uuid),public.admin_verify_refund(uuid,bigint,text,text) to authenticated;
revoke execute on all functions in schema private from public,anon,authenticated;

-- Migration: 20261116001000_bootstrap_cardinality_fix.sql
-- Keep server account operations available if an interrupted bootstrap left more than one candidate.
create or replace function public.service_bootstrap_state() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  is_completed boolean;
  candidate uuid;
begin
  if auth.role()<>'service_role' then
    raise exception 'Server authorization required.' using errcode='42501';
  end if;

  select completed into is_completed
  from private.initial_admin_bootstrap
  where singleton;

  if not coalesce(is_completed,false) then
    select id into candidate
    from auth.users
    where email='admin@localmate.invalid'
      and raw_app_meta_data->>'local_mate_bootstrap'='true'
    order by id
    limit 1;
  end if;

  return jsonb_build_object(
    'completed',coalesce(is_completed,false),
    'candidate_id',candidate
  );
end $$;

revoke execute on function public.service_bootstrap_state() from public,anon,authenticated;
grant execute on function public.service_bootstrap_state() to service_role;
notify pgrst,'reload schema';

-- Migration: 20261116001100_fast_portals_and_retention.sql
-- Fast customer updates, short-lived generic admin logs, and completed-chat cleanup.
create index if not exists bookings_customer_created on public.bookings(customer_id,created_at desc);
create index if not exists booking_events_booking_created on public.booking_events(booking_id,created_at desc);
create index if not exists admin_activity_logs_created on public.admin_activity_logs(created_at desc);

create or replace function private.cleanup_short_retention() returns jsonb
language plpgsql security definer set search_path='' as $$
declare removed_logs integer:=0;removed_messages integer:=0;
begin
 delete from public.admin_activity_logs where created_at<now()-interval '30 minutes';
 get diagnostics removed_logs=row_count;
 delete from public.message_reads r using public.bookings b where r.booking_id=b.id and b.status='work_completed';
 delete from public.messages m using public.bookings b where m.booking_id=b.id and b.status='work_completed';
 get diagnostics removed_messages=row_count;
 delete from public.notifications n using public.bookings b
 where n.booking_id=b.id and b.status='work_completed' and n.title='New Local Mate booking message';
 return jsonb_build_object('removed_activity_logs',removed_logs,'removed_completed_messages',removed_messages);
end $$;

create or replace function private.clear_completed_conversation() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.status='work_completed' and old.status is distinct from new.status then
  delete from public.message_reads where booking_id=new.id;
  delete from public.messages where booking_id=new.id;
  delete from public.notifications where booking_id=new.id and title='New Local Mate booking message';
 end if;
 return new;
end $$;
drop trigger if exists clear_completed_conversation on public.bookings;
create trigger clear_completed_conversation after update of status on public.bookings
for each row execute function private.clear_completed_conversation();

-- Existing completed conversations are cleared when this migration is installed.
select private.cleanup_short_retention();

create or replace function public.send_message(p_booking uuid,p_body text) returns bigint
language plpgsql security definer set search_path='' as $$
declare mid bigint;other_user uuid;
begin
 perform private.take_rate_limit();
 if not public.can_message_booking(p_booking) then raise exception 'You cannot access this conversation.' using errcode='42501';end if;
 if exists(select 1 from public.bookings where id=p_booking and status in('work_completed','cancelled')) then raise exception 'This conversation closed when the job ended.';end if;
 perform private.check_private_text(p_body);
 insert into public.messages(booking_id,sender_id,body) values(p_booking,auth.uid(),trim(p_body)) returning id into mid;
 select case when customer_id=auth.uid() then provider_id else customer_id end into other_user from public.bookings where id=p_booking;
 perform private.notify(other_user,'New Local Mate booking message',p_booking);return mid;
end $$;

create or replace function public.send_attachment(p_booking uuid,p_asset uuid,p_body text default 'Image attachment') returns bigint
language plpgsql security definer set search_path='' as $$
declare mid bigint;
begin
 perform private.take_rate_limit();
 if not public.can_message_booking(p_booking) then raise exception 'This conversation is private.' using errcode='42501';end if;
 if exists(select 1 from public.bookings where id=p_booking and status in('work_completed','cancelled')) then raise exception 'This conversation closed when the job ended.';end if;
 if not exists(select 1 from public.media_assets where id=p_asset and owner_id=auth.uid() and booking_id=p_booking and kind='chat') then raise exception 'Upload your image to this conversation first.';end if;
 perform private.check_private_text(p_body);
 insert into public.messages(booking_id,sender_id,body,attachment_id) values(p_booking,auth.uid(),p_body,p_asset) returning id into mid;return mid;
end $$;

create or replace function public.admin_recent_logs() returns setof jsonb
language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 perform private.cleanup_short_retention();
 return query select to_jsonb(l) from public.admin_activity_logs l
 where l.created_at>=now()-interval '30 minutes' order by l.id desc limit 200;
end $$;

create or replace function public.admin_operations_logs() returns jsonb
language plpgsql security definer set search_path='' as $$
declare cutoff timestamptz:=now()-interval '30 minutes';
begin
 if not public.is_admin() then raise exception 'Administrator access required.' using errcode='42501';end if;
 perform private.cleanup_short_retention();
 return jsonb_build_object(
  'offers',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from public.booking_provider_offers where offered_at>=cutoff order by offered_at desc limit 200)x),'[]'),
  'assignments',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from public.booking_assignment_history where created_at>=cutoff order by id desc limit 200)x),'[]'),
  'otp',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from public.job_start_otp_logs where created_at>=cutoff order by id desc limit 200)x),'[]'),
  'financial',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from public.financial_audit_logs where created_at>=cutoff order by id desc limit 200)x),'[]'),
  'suspensions',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from public.provider_suspension_records where created_at>=cutoff order by created_at desc limit 200)x),'[]'),
  'reactivations',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from public.provider_reactivation_records where created_at>=cutoff order by id desc limit 200)x),'[]'));
end $$;

create or replace function public.service_customer_active_otps(p_actor uuid) returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role()<>'service_role' or not exists(select 1 from public.users where id=p_actor and is_active) then raise exception 'Customer authorization required.' using errcode='42501';end if;
 return query select jsonb_build_object('booking_id',o.booking_id,'ciphertext',o.ciphertext,'expires_at',o.expires_at)
 from private.job_start_otps o join public.bookings b on b.id=o.booking_id
 where b.customer_id=p_actor and b.status='arrived' and o.provider_id=b.provider_id and o.used_at is null and o.expires_at>now() and o.ciphertext<>''
 order by o.created_at desc;
end $$;

-- Preserve the established maintenance behavior and add short-retention cleanup.
create or replace function private.run_maintenance() returns jsonb
language plpgsql security definer set search_path='' as $$
declare provider uuid;expired_count int:=0;request_id uuid;cleanup jsonb;
begin
 if private.ops()->>'request_expiry_mode'='expire' then
  for request_id in select id from public.bookings where provider_id is null and status='requested' and not request_expired and request_expires_at<now() for update skip locked loop
   update public.bookings set request_expired=true where id=request_id;
   update public.booking_provider_offers set status='expired',responded_at=now() where booking_id=request_id and status='pending';
   perform private.notify((select customer_id from public.bookings where id=request_id),'No provider accepted before the request deadline. You can retry from your booking.',request_id);expired_count:=expired_count+1;
  end loop;
 end if;
 for provider in select user_id from public.provider_profiles loop perform private.reconcile_provider(provider);end loop;
 perform private.expire_calls();delete from public.booking_locations where recorded_at<now()-interval '2 minutes';
 delete from private.voice_rate_windows where minute<floor(extract(epoch from now())/60)-60;
 update private.job_start_otps set ciphertext='' where expires_at<now() and ciphertext<>'';
 cleanup:=private.cleanup_short_retention();
 return jsonb_build_object('expired_requests',expired_count,'cleanup',cleanup,'completed_at',now());
end $$;

revoke execute on function public.admin_recent_logs(),public.service_customer_active_otps(uuid) from public,anon,authenticated;
grant execute on function public.admin_recent_logs() to authenticated;
grant execute on function public.service_customer_active_otps(uuid) to service_role;
revoke execute on all functions in schema private from public,anon,authenticated;
notify pgrst,'reload schema';
select 'Fast portals, two-second customer OTP display, completed-message cleanup, and 30-minute log retention enabled' as result;

-- Migration: 20261117000100_atomic_marketplace_reset.sql
-- Replace the legacy chained reset with one atomic, repeatable reset.
-- Authentication, administrator membership, and username mappings are preserved.
create or replace function public.service_reset_marketplace(p_actor uuid,p_confirmation text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.role()<>'service_role' or not exists(
  select 1
  from auth.users u
  join private.admin_emails a on a.email=lower(u.email)
  join public.users p on p.id=u.id
  where u.id=p_actor and p.is_active and u.email_confirmed_at is not null
    and not exists(select 1 from private.login_accounts l where l.user_id=p_actor and l.must_change_password)
 ) then
  raise exception 'Server administrator authorization required.' using errcode='42501';
 end if;
 if p_confirmation<>'DELETE ALL DATA' then
  raise exception 'Type DELETE ALL DATA to confirm.';
 end if;

 -- Only one destructive reset can run at a time. Everything remains transactional.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('local-mate-marketplace-reset'));

 -- Truncating the marketplace roots with CASCADE clears every dependent booking,
 -- message, provider, finance, media, GPS, call, and audit table without firing
 -- legacy row triggers. public.users is intentionally not a root and is preserved
 -- until the server deletes every non-administrator Supabase Auth account.
 truncate table
  public.bookings,
  public.provider_profiles,
  public.services,
  public.locations,
  public.addresses,
  public.settings,
  public.admin_activity_logs,
  public.website_configuration,
  public.operations_configuration
 restart identity cascade;

 truncate table private.request_windows,private.auth_attempts,private.voice_rate_windows;
 alter sequence public.invoice_number_seq restart with 1;

 insert into public.website_configuration(
  id,maintenance_mode,registration_enabled,customer_portal_enabled,
  provider_portal_enabled,bookings_enabled
 ) values(true,true,false,false,false,false);

 insert into public.operations_configuration(id,config) values(true,'{
  "request_timeout_minutes":60,"request_expiry_mode":"pending","otp_ttl_seconds":300,"otp_max_attempts":5,
  "calling_enabled":true,"call_statuses":["confirmed","on_the_way","arrived","work_started","work_paused"],"ring_seconds":45,"call_max_seconds":3600,"call_heartbeat_seconds":45,"relay_only":false,
  "commission_enabled":true,"commission_percent":10,"commission_fixed_paise":0,"week_start_day":1,"timezone":"Asia/Kolkata","deadline_days":3,"grace_hours":48,"minimum_commission_paise":0,"auto_suspend":true,"auto_reactivate":true,
  "payment_ready_at":null,"payment_instructions":"","payment_methods":["bank_transfer","upi"],"tax_enabled":false,"tax_percent":0,"supplier_name":"","supplier_address":"","tax_registration":"","invoice_terms":"Payment status is recorded separately from this invoice."
 }');

 insert into public.admin_activity_logs(actor_id,action)
 values(p_actor,'Delete all marketplace data');
end $$;

revoke execute on function public.service_reset_marketplace(uuid,text) from public,anon,authenticated;
grant execute on function public.service_reset_marketplace(uuid,text) to service_role;
notify pgrst,'reload schema';
select 'Reference 21000 marketplace reset fix installed' as result;

-- Migration: 20261117000200_reset_v2_rpc.sql
-- A uniquely named reset RPC avoids stale legacy overloads and makes the
-- installed reset version unambiguous to the application server.
create or replace function public.service_reset_marketplace_v2(p_actor uuid,p_confirmation text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.role()<>'service_role' or not exists(
  select 1
  from auth.users u
  join private.admin_emails a on a.email=lower(u.email)
  join public.users p on p.id=u.id
  where u.id=p_actor and p.is_active and u.email_confirmed_at is not null
    and not exists(select 1 from private.login_accounts l where l.user_id=p_actor and l.must_change_password)
 ) then
  raise exception 'Server administrator authorization required.' using errcode='42501';
 end if;
 if p_confirmation<>'DELETE ALL DATA' then
  raise exception 'Type DELETE ALL DATA to confirm.';
 end if;

 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('local-mate-marketplace-reset'));

 truncate table
  public.bookings,
  public.provider_profiles,
  public.services,
  public.locations,
  public.addresses,
  public.settings,
  public.admin_activity_logs,
  public.website_configuration,
  public.operations_configuration
 restart identity cascade;

 truncate table private.request_windows,private.auth_attempts,private.voice_rate_windows;
 alter sequence public.invoice_number_seq restart with 1;

 insert into public.website_configuration(
  id,maintenance_mode,registration_enabled,customer_portal_enabled,
  provider_portal_enabled,bookings_enabled
 ) values(true,true,false,false,false,false);

 insert into public.operations_configuration(id,config) values(true,'{
  "request_timeout_minutes":60,"request_expiry_mode":"pending","otp_ttl_seconds":300,"otp_max_attempts":5,
  "calling_enabled":true,"call_statuses":["confirmed","on_the_way","arrived","work_started","work_paused"],"ring_seconds":45,"call_max_seconds":3600,"call_heartbeat_seconds":45,"relay_only":false,
  "commission_enabled":true,"commission_percent":10,"commission_fixed_paise":0,"week_start_day":1,"timezone":"Asia/Kolkata","deadline_days":3,"grace_hours":48,"minimum_commission_paise":0,"auto_suspend":true,"auto_reactivate":true,
  "payment_ready_at":null,"payment_instructions":"","payment_methods":["bank_transfer","upi"],"tax_enabled":false,"tax_percent":0,"supplier_name":"","supplier_address":"","tax_registration":"","invoice_terms":"Payment status is recorded separately from this invoice."
 }');

 insert into public.admin_activity_logs(actor_id,action)
 values(p_actor,'Delete all marketplace data');
end $$;

-- Keep older deployed clients compatible while the current application calls v2.
create or replace function public.service_reset_marketplace(p_actor uuid,p_confirmation text) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform public.service_reset_marketplace_v2(p_actor,p_confirmation);
end $$;

create or replace function public.service_reset_progress_v2(p_actor uuid,p_note text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.role()<>'service_role' or not exists(
  select 1 from public.users u where u.id=p_actor and u.is_active
 ) then
  raise exception 'Server administrator authorization required.' using errcode='42501';
 end if;
 insert into public.admin_activity_logs(actor_id,action,target_id)
 values(p_actor,'Account cleanup',left(coalesce(p_note,''),2000));
end $$;

revoke execute on function public.service_reset_marketplace_v2(uuid,text),public.service_reset_progress_v2(uuid,text) from public,anon,authenticated;
grant execute on function public.service_reset_marketplace_v2(uuid,text),public.service_reset_progress_v2(uuid,text) to service_role;
revoke execute on function public.service_reset_marketplace(uuid,text) from public,anon,authenticated;
grant execute on function public.service_reset_marketplace(uuid,text) to service_role;
notify pgrst,'reload schema';
select 'Reference 21000 reset v2 installed' as result;


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
