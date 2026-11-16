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
