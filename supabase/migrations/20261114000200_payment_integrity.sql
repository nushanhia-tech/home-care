create function public.reserve_payment(p_booking uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.bookings;p public.payments;
begin
 perform private.take_rate_limit();
 select * into b from public.bookings where id=p_booking and customer_id=auth.uid() for update;
 if b.id is null or b.status<>'work_completed' or b.payment_status<>'pending' or b.estimated_price<=0 then raise exception 'This booking is not ready for online payment.';end if;
 insert into public.payments(booking_id,amount) values(b.id,b.estimated_price) on conflict(booking_id) do nothing;
 select * into p from public.payments where booking_id=b.id;
 if p.status<>'pending' then raise exception 'This payment has already been processed.';end if;
 return to_jsonb(p);
end $$;
create function public.attach_payment_order(p_payment uuid,p_order text) returns text language plpgsql security definer set search_path='' as $$
declare record public.payments;
begin
 if auth.role()<>'service_role' then raise exception 'Server payment authorization required.' using errcode='42501';end if;
 select * into record from public.payments where id=p_payment for update;
 if record.id is null or record.status<>'pending' then raise exception 'Payment is unavailable.';end if;
 if record.gateway_order_id is not null then return record.gateway_order_id;end if;
 update public.payments set gateway_order_id=p_order where id=p_payment;return p_order;
end $$;
create function public.record_payment_capture(p_order text,p_gateway_payment text,p_amount_paise bigint) returns void language plpgsql security definer set search_path='' as $$
declare record public.payments;customer uuid;
begin
 if auth.role()<>'service_role' then raise exception 'Server payment authorization required.' using errcode='42501';end if;
 select * into record from public.payments where gateway_order_id=p_order for update;
 if record.id is null or record.amount::bigint*100<>p_amount_paise then raise exception 'Payment amount does not match.';end if;
 if record.status='successful' then
  if record.gateway_payment_id<>p_gateway_payment then raise exception 'Payment identity does not match.';end if;
  return;
 end if;
 update public.payments set status='successful',gateway_payment_id=p_gateway_payment where id=record.id;
 update public.bookings set payment_status='successful',payment_method='online' where id=record.booking_id returning customer_id into customer;
 perform private.notify(customer,'Your online payment has been verified',record.booking_id);
end $$;
revoke execute on function public.reserve_payment(uuid),public.attach_payment_order(uuid,text),public.record_payment_capture(text,text,bigint) from public,anon,authenticated;
grant execute on function public.reserve_payment(uuid) to authenticated;
grant execute on function public.attach_payment_order(uuid,text),public.record_payment_capture(text,text,bigint) to service_role;
