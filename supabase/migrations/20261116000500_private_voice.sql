-- Audio is end-to-end WebRTC media, never uploaded to PostgreSQL or recorded here.
create table if not exists public.voice_calls(id uuid primary key default gen_random_uuid(),booking_id uuid not null references public.bookings(id) on delete cascade,caller_id uuid not null references public.users(id),callee_id uuid not null references public.users(id),status text not null default 'ringing' check(status in ('ringing','accepted','active','ended','rejected','missed','failed')),created_at timestamptz not null default now(),accepted_at timestamptz,connected_at timestamptz,ended_at timestamptz,ended_reason text not null default '',caller_seen_at timestamptz not null default now(),callee_seen_at timestamptz,check(caller_id<>callee_id));
create index if not exists voice_calls_participants on public.voice_calls(caller_id,callee_id,created_at desc);
create index if not exists voice_calls_callee_active on public.voice_calls(callee_id,status);
create table if not exists public.voice_signals(id bigint generated always as identity primary key,call_id uuid not null references public.voice_calls(id) on delete cascade,sender_id uuid not null references public.users(id),recipient_id uuid not null references public.users(id),kind text not null check(kind in ('offer','answer','candidate')),payload jsonb not null,created_at timestamptz not null default now());
create index if not exists voice_signals_delivery on public.voice_signals(call_id,recipient_id,id);
create table if not exists private.voice_user_slots(user_id uuid primary key references public.users(id) on delete cascade,call_id uuid not null references public.voice_calls(id) on delete cascade);
create table if not exists private.voice_rate_windows(user_id uuid,minute bigint,hits int not null,primary key(user_id,minute));
alter table public.voice_calls enable row level security;alter table public.voice_signals enable row level security;
revoke all on public.voice_calls,public.voice_signals from anon,authenticated;
revoke all on private.voice_user_slots,private.voice_rate_windows from public,anon,authenticated;
create or replace function private.call_allowed(p_call uuid,p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.voice_calls c join public.bookings b on b.id=c.booking_id join public.users u on u.id=p_user cross join public.website_configuration w
 where c.id=p_call and u.is_active and not w.maintenance_mode and w.provider_portal_enabled and w.customer_portal_enabled and(private.ops()->>'calling_enabled')::boolean and p_user in (c.caller_id,c.callee_id)
 and b.accepted_at is not null and b.status in(select jsonb_array_elements_text(private.ops()->'call_statuses')) and((c.caller_id=b.customer_id and c.callee_id=b.provider_id) or(c.callee_id=b.customer_id and c.caller_id=b.provider_id)))
$$;
create or replace function private.finish_call(p_call uuid,p_status text,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare c public.voice_calls;
begin
 update public.voice_calls set status=p_status,ended_at=now(),ended_reason=left(p_reason,100) where id=p_call and status in ('ringing','accepted','active') returning * into c;
 if c.id is not null then
  delete from private.voice_user_slots where call_id=c.id;delete from public.voice_signals where call_id=c.id;
  if p_status='missed' then perform private.notify(c.callee_id,'Missed Local Mate booking call',c.booking_id);end if;
 end if;
end $$;
create or replace function private.expire_calls(p_user uuid default null) returns void language plpgsql security definer set search_path='' as $$
declare c public.voice_calls;
begin
 for c in select * from public.voice_calls where status in ('ringing','accepted','active') and(p_user is null or p_user in(caller_id,callee_id)) for update skip locked loop
  if not private.call_allowed(c.id,c.caller_id) or not private.call_allowed(c.id,c.callee_id) then perform private.finish_call(c.id,'ended','booking_or_account_permission_changed');
  elsif c.status='ringing' and c.created_at<now()-make_interval(secs=>(private.ops()->>'ring_seconds')::int) then perform private.finish_call(c.id,'missed','unanswered');
  elsif c.caller_seen_at<now()-make_interval(secs=>(private.ops()->>'call_heartbeat_seconds')::int) or(c.status<>'ringing' and coalesce(c.callee_seen_at,c.accepted_at)<now()-make_interval(secs=>(private.ops()->>'call_heartbeat_seconds')::int)) then perform private.finish_call(c.id,'ended','session_disconnected');
  elsif c.created_at<now()-make_interval(secs=>(private.ops()->>'call_max_seconds')::int) then perform private.finish_call(c.id,'ended','duration_limit');end if;
 end loop;
 delete from public.voice_signals where created_at<now()-interval '10 minutes';
end $$;
create or replace function private.voice_dto(p_call uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',c.id,'booking_id',c.booking_id,'booking_reference',upper(left(c.booking_id::text,8)),'caller_id',c.caller_id,'callee_id',c.callee_id,
 'caller_name',case when c.caller_id=b.customer_id then 'Customer · '||upper(left(b.id::text,8)) else private.safe_text(coalesce(nullif(p.business_name,''),'Service provider')) end,
 'callee_name',case when c.callee_id=b.customer_id then 'Customer · '||upper(left(b.id::text,8)) else private.safe_text(coalesce(nullif(p.business_name,''),'Service provider')) end,
 'status',c.status,'created_at',c.created_at,'accepted_at',c.accepted_at,'connected_at',c.connected_at,'ended_at',c.ended_at,'ended_reason',c.ended_reason,
 'duration_seconds',case when c.connected_at is not null then greatest(0,floor(extract(epoch from(coalesce(c.ended_at,now())-c.connected_at)))) else 0 end)
 from public.voice_calls c join public.bookings b on b.id=c.booking_id left join public.provider_profiles p on p.user_id=b.provider_id where c.id=p_call
$$;
create or replace function public.start_voice_call(p_booking uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.bookings;other uuid;call_id uuid;
begin
 perform private.take_rate_limit();perform private.expire_calls(auth.uid());
 select * into b from public.bookings where id=p_booking for share;
 if auth.uid() not in(b.customer_id,b.provider_id) or b.provider_id is null or b.accepted_at is null then raise exception 'Calls are private to the customer and accepting provider.' using errcode='42501';end if;
 if not(private.ops()->>'calling_enabled')::boolean or not(b.status in(select jsonb_array_elements_text(private.ops()->'call_statuses'))) or exists(select 1 from public.website_configuration where id and(maintenance_mode or not customer_portal_enabled or not provider_portal_enabled)) then raise exception 'Calling is unavailable for this booking. Use in-app chat.';end if;
 other:=case when auth.uid()=b.customer_id then b.provider_id else b.customer_id end;
 if not exists(select 1 from public.users where id=other and is_active) then raise exception 'This participant is unavailable.';end if;
 -- Lock participants in a fixed order to prevent double ringing and crossed calls.
 perform pg_advisory_xact_lock(hashtextextended('voice-user:'||least(auth.uid(),other)::text,0));
 perform pg_advisory_xact_lock(hashtextextended('voice-user:'||greatest(auth.uid(),other)::text,0));
 if exists(select 1 from private.voice_user_slots where user_id in(auth.uid(),other)) then raise exception 'One participant is already in a Local Mate call. Try chat or call again later.';end if;
 insert into public.voice_calls(booking_id,caller_id,callee_id) values(b.id,auth.uid(),other) returning id into call_id;
 insert into private.voice_user_slots(user_id,call_id) values(auth.uid(),call_id),(other,call_id);
 perform private.notify(other,'Incoming Local Mate booking call',b.id);return private.voice_dto(call_id);
end $$;
create or replace function public.voice_call_action(p_call uuid,p_action text,p_reason text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.voice_calls;
begin
 if not public.account_active() then raise exception 'Sign in.' using errcode='42501';end if;
 perform private.expire_calls(auth.uid());select * into c from public.voice_calls where id=p_call for update;
 if c.id is null or auth.uid() not in(c.caller_id,c.callee_id) then raise exception 'This call is private.' using errcode='42501';end if;
 if p_action='end' then perform private.finish_call(c.id,'ended',case when p_reason='session_ended' then 'session_ended' else 'participant_ended' end);
 elsif p_action='reject' then
  if c.callee_id<>auth.uid() or c.status<>'ringing' then raise exception 'This call is no longer ringing.';end if;perform private.finish_call(c.id,'rejected','callee_rejected');
 elsif p_action='accept' then
  if c.callee_id<>auth.uid() or c.status<>'ringing' or not private.call_allowed(c.id,auth.uid()) then raise exception 'This call cannot be accepted.';end if;
  update public.voice_calls set status='accepted',accepted_at=now(),callee_seen_at=now() where id=c.id;
 elsif p_action='connected' then
  if c.status not in ('accepted','active') or not private.call_allowed(c.id,auth.uid()) then raise exception 'This call is unavailable.';end if;
  update public.voice_calls set status='active',connected_at=coalesce(connected_at,now()) where id=c.id;
 elsif p_action='failed' then perform private.finish_call(c.id,'failed','connection_failed');
 elsif p_action<>'heartbeat' then raise exception 'Unknown call action.';
 end if;
 if p_action in ('heartbeat','connected','accept') and c.status in ('ringing','accepted','active') then
  if not private.call_allowed(c.id,auth.uid()) then perform private.finish_call(c.id,'ended','permission_changed');
  else update public.voice_calls set caller_seen_at=case when caller_id=auth.uid() then now() else caller_seen_at end,callee_seen_at=case when callee_id=auth.uid() then now() else callee_seen_at end where id=c.id;end if;
 end if;
 return private.voice_dto(c.id);
end $$;
create or replace function public.voice_call_state(p_call uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not public.account_active() or not exists(select 1 from public.voice_calls where id=p_call and auth.uid() in(caller_id,callee_id)) then raise exception 'This call is private.' using errcode='42501';end if;
 perform private.expire_calls(auth.uid());return private.voice_dto(p_call);
end $$;
create or replace function public.voice_call_history(p_booking uuid default null) returns setof jsonb language plpgsql security definer set search_path='' as $$
begin
 if not public.account_active() then raise exception 'Sign in.' using errcode='42501';end if;
 perform private.expire_calls(auth.uid());
 return query select private.voice_dto(c.id) from public.voice_calls c where(p_booking is null or c.booking_id=p_booking) and(auth.uid() in(c.caller_id,c.callee_id) or public.is_admin()) order by c.created_at desc limit 100;
end $$;
create or replace function public.voice_incoming() returns setof jsonb language plpgsql security definer set search_path='' as $$
begin
 if not public.account_active() then raise exception 'Sign in.' using errcode='42501';end if;
 perform private.expire_calls(auth.uid());return query select private.voice_dto(c.id) from public.voice_calls c where c.callee_id=auth.uid() and c.status='ringing' and private.call_allowed(c.id,auth.uid());
end $$;
create or replace function public.send_voice_signal(p_call uuid,p_kind text,p_payload jsonb) returns bigint language plpgsql security definer set search_path='' as $$
declare c public.voice_calls;signal_id bigint;hits int;minute_now bigint:=floor(extract(epoch from now())/60);clean jsonb;
begin
 if not public.account_active() or not private.call_allowed(p_call,auth.uid()) then raise exception 'This call is private.' using errcode='42501';end if;
 select * into c from public.voice_calls where id=p_call for share;
 if c.status not in ('ringing','accepted','active') then raise exception 'This call has ended.';end if;
 if pg_column_size(p_payload)>20000 then raise exception 'Signalling payload is too large.';end if;
 insert into private.voice_rate_windows(user_id,minute,hits) values(auth.uid(),minute_now,1) on conflict(user_id,minute) do update set hits=private.voice_rate_windows.hits+1 where private.voice_rate_windows.hits<180 returning private.voice_rate_windows.hits into hits;
 if hits is null then raise exception 'Too many signalling messages.';end if;
 if p_kind in ('offer','answer') then
  if(p_kind='offer' and(c.caller_id<>auth.uid() or c.status not in ('ringing','accepted'))) or(p_kind='answer' and(c.callee_id<>auth.uid() or c.status<>'accepted')) then raise exception 'Signalling role mismatch.' using errcode='42501';end if;
  if jsonb_typeof(p_payload->'sdp')<>'string' or p_payload->>'type'<>p_kind or(p_payload->>'sdp')!~ E'^v=0[\\r\\n]' or(p_payload->>'sdp')~E'(^|[\\r\\n])m=(video|application)' then raise exception 'An audio-only SDP message is required.';end if;
  clean:=jsonb_build_object('type',p_kind,'sdp',p_payload->>'sdp');
 elsif p_kind='candidate' then
  if jsonb_typeof(p_payload->'candidate')<>'string' or length(p_payload->>'candidate')>4000 then raise exception 'Invalid ICE candidate.';end if;
  clean:=jsonb_build_object('candidate',p_payload->>'candidate','sdpMid',p_payload->'sdpMid','sdpMLineIndex',p_payload->'sdpMLineIndex','usernameFragment',p_payload->'usernameFragment');
 else raise exception 'Unknown signal type.';end if;
 insert into public.voice_signals(call_id,sender_id,recipient_id,kind,payload) values(c.id,auth.uid(),case when c.caller_id=auth.uid() then c.callee_id else c.caller_id end,p_kind,clean) returning id into signal_id;return signal_id;
end $$;
create or replace function public.receive_voice_signals(p_call uuid,p_after bigint default 0) returns setof jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.account_active() or not private.call_allowed(p_call,auth.uid()) then raise exception 'This call is private.' using errcode='42501';end if;
 if not exists(select 1 from public.voice_calls where id=p_call and(status in ('accepted','active') or caller_id=auth.uid())) then return;end if;
 return query select jsonb_build_object('id',s.id,'kind',s.kind,'payload',s.payload) from public.voice_signals s where s.call_id=p_call and s.recipient_id=auth.uid() and s.id>p_after order by s.id limit 100;
end $$;
create or replace function private.stop_unauthorized_calls() returns trigger language plpgsql security definer set search_path='' as $$
declare c public.voice_calls;scope_user uuid;scope_booking uuid;
begin
 if tg_table_name='users' then scope_user:=new.id;elsif tg_table_name='bookings' then scope_booking:=new.id;end if;
 for c in select * from public.voice_calls where(scope_user is null or scope_user in(caller_id,callee_id)) and(scope_booking is null or booking_id=scope_booking) and status in ('ringing','accepted','active') loop
  if not private.call_allowed(c.id,c.caller_id) or not private.call_allowed(c.id,c.callee_id) then perform private.finish_call(c.id,'ended','booking_or_account_permission_changed');end if;
 end loop;return new;
end $$;
do $$ declare t text;begin
 foreach t in array array['users','bookings','website_configuration','operations_configuration'] loop
  execute format('drop trigger if exists stop_unauthorized_calls on public.%I',t);
  execute format('create trigger stop_unauthorized_calls after update on public.%I for each row execute function private.stop_unauthorized_calls()',t);
 end loop;
end $$;
drop policy if exists voice_metadata_read on public.voice_calls;
create policy voice_metadata_read on public.voice_calls for select to authenticated using(public.account_active() and auth.uid() in(caller_id,callee_id));
grant select(id,booking_id,caller_id,callee_id,status,created_at,accepted_at,connected_at,ended_at,ended_reason) on public.voice_calls to authenticated;
-- Signals are exposed only through participant-checked RPCs. Administrators see metadata, never SDP/audio.
revoke execute on function public.start_voice_call(uuid),public.voice_call_action(uuid,text,text),public.voice_call_state(uuid),public.voice_call_history(uuid),public.voice_incoming(),public.send_voice_signal(uuid,text,jsonb),public.receive_voice_signals(uuid,bigint) from public,anon;
grant execute on function public.start_voice_call(uuid),public.voice_call_action(uuid,text,text),public.voice_call_state(uuid),public.voice_call_history(uuid),public.voice_incoming(),public.send_voice_signal(uuid,text,jsonb),public.receive_voice_signals(uuid,bigint) to authenticated;
revoke execute on all functions in schema private from public,anon,authenticated;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='voice_calls') then alter publication supabase_realtime add table public.voice_calls;end if;
end $$;
notify pgrst, 'reload schema';
