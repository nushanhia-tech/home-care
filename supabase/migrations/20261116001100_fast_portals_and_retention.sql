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
