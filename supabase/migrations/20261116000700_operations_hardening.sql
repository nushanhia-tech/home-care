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
