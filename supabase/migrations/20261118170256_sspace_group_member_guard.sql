
create or replace function private.sspace_guard_suspension_aux()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid();v_owner uuid;v_maintenance boolean:=false;v_message text;
begin
 if v_actor is null then raise exception 'Connexion requise.' using errcode='28000';end if;
 if tg_table_name='follows' then v_owner:=new.follower_id;
 elsif tg_table_name='friend_requests' then
  if tg_op='INSERT' then v_owner:=new.sender_id;elsif v_actor=new.receiver_id then v_owner:=new.receiver_id;else v_owner:=new.sender_id;end if;
 elsif tg_table_name in ('likes','post_poll_votes','hidden_posts','profile_album_photos','group_members') then v_owner:=new.user_id;
 elsif tg_table_name='post_mentions' then v_owner:=new.tagged_by;
 elsif tg_table_name='groups' then v_owner:=new.created_by;
 else raise exception 'Table non prise en charge.' using errcode='42501';end if;
 if v_owner is distinct from v_actor then raise exception 'Action non autorisée.' using errcode='42501';end if;
 if exists(select 1 from public.user_suspensions s where s.user_id=v_actor and s.revoked_at is null and s.starts_at<=clock_timestamp() and s.expires_at>clock_timestamp()) then
  raise exception 'SSPACE_BANNED: ton compte est temporairement suspendu.' using errcode='42501';end if;
 select maintenance_enabled,maintenance_message into v_maintenance,v_message from public.sspace_control_settings where id=true;
 if coalesce(v_maintenance,false) and coalesce(auth.jwt()->'app_metadata'->>'role','')<>'admin' then
  raise exception 'SSPACE_MAINTENANCE: %',coalesce(v_message,'SSPACE est en maintenance.') using errcode='55000';end if;
 return new;
end; $$;
drop trigger if exists sspace_guard_group_members on public.group_members;
create trigger sspace_guard_group_members before insert on public.group_members
for each row execute function private.sspace_guard_suspension_aux();
revoke all on function private.sspace_guard_suspension_aux() from public,anon,authenticated;
