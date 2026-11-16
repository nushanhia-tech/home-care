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
