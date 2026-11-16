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
