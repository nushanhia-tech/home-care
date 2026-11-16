-- Keep server account operations available if an interrupted bootstrap left more than one candidate.
create or replace function public.service_bootstrap_state() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  is_completed boolean;
  candidate uuid;
begin
  if auth.role()<>'service_role' then
    raise exception 'Server authorization required.' using errcode='42501';
  end if;

  select completed into is_completed
  from private.initial_admin_bootstrap
  where singleton;

  if not coalesce(is_completed,false) then
    select id into candidate
    from auth.users
    where email='admin@localmate.invalid'
      and raw_app_meta_data->>'local_mate_bootstrap'='true'
    order by id
    limit 1;
  end if;

  return jsonb_build_object(
    'completed',coalesce(is_completed,false),
    'candidate_id',candidate
  );
end $$;

revoke execute on function public.service_bootstrap_state() from public,anon,authenticated;
grant execute on function public.service_bootstrap_state() to service_role;
notify pgrst,'reload schema';
