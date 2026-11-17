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
