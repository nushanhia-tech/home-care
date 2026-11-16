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
