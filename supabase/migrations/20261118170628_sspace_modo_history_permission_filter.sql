
create or replace function private.modo_user_history(p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_actions jsonb;v_suspensions jsonb;v_can_warnings boolean:=private.sspace_has_permission('warnings');v_can_bans boolean:=private.sspace_has_permission('bans');
begin
 if not(v_can_warnings or v_can_bans) then raise exception 'Permission de consultation refusée.' using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',a.id,'action_type',a.action_type,'reason',a.reason,'duration_hours',a.duration_hours,
  'expires_at',a.expires_at,'created_at',a.created_at,'actor_id',a.actor_id
 ) order by a.created_at desc),'[]'::jsonb)
 into v_actions
 from (
  select * from public.moderation_actions
  where target_user_id=p_user_id
    and ((action_type='warning' and v_can_warnings) or (action_type in ('ban','unban') and v_can_bans))
  order by created_at desc limit 30
 ) a;
 if v_can_bans then
  select coalesce(jsonb_agg(jsonb_build_object(
   'id',s.id,'starts_at',s.starts_at,'expires_at',s.expires_at,'revoked_at',s.revoked_at,
   'active',(s.revoked_at is null and s.expires_at>clock_timestamp())
  ) order by s.created_at desc),'[]'::jsonb)
  into v_suspensions from public.user_suspensions s where s.user_id=p_user_id;
 else
  v_suspensions:='[]'::jsonb;
 end if;
 return jsonb_build_object('actions',v_actions,'suspensions',v_suspensions);
end; $$;
