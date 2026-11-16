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
