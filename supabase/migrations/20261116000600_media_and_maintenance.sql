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
