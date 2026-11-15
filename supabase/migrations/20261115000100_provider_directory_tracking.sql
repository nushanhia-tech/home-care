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
create policy offerings_owner on public.provider_offerings for select to authenticated using(public.account_active() and(provider_id=auth.uid() or public.is_admin()));
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
