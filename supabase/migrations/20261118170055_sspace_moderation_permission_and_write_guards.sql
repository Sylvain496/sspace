
create or replace function private.modo_set_moderator(p_user_id uuid,p_active boolean,p_permissions jsonb default null)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
 v_actor uuid:=auth.uid();v_target_role text;v_permissions jsonb;
 v_allowed text[]:=array['warnings','bans','announcements','reports','audit_view','settings_manage'];v_key text;
begin
 if v_actor is null or coalesce(auth.jwt()->'app_metadata'->>'role','')<>'admin' then raise exception 'Seul l’administrateur principal peut gérer l’équipe.' using errcode='42501'; end if;
 if p_user_id is null then raise exception 'Membre requis.'; end if;
 select coalesce(raw_app_meta_data->>'role','') into v_target_role from auth.users where id=p_user_id;
 if not found then raise exception 'Membre introuvable.'; end if;
 if v_target_role='admin' then raise exception 'Impossible de modifier un administrateur principal.' using errcode='42501'; end if;
 if p_active then
  v_permissions:=coalesce(p_permissions,'{}'::jsonb);
  if jsonb_typeof(v_permissions)<>'object' then raise exception 'Permissions invalides.'; end if;
  for v_key in select jsonb_object_keys(v_permissions) loop
   if not(v_key=any(v_allowed)) or jsonb_typeof(v_permissions->v_key)<>'boolean' then raise exception 'Permission invalide : %',v_key; end if;
  end loop;
  v_permissions:=jsonb_build_object(
   'warnings',coalesce((v_permissions->>'warnings')::boolean,false),'bans',coalesce((v_permissions->>'bans')::boolean,false),
   'announcements',coalesce((v_permissions->>'announcements')::boolean,false),'reports',coalesce((v_permissions->>'reports')::boolean,false),
   'audit_view',coalesce((v_permissions->>'audit_view')::boolean,false),'settings_manage',coalesce((v_permissions->>'settings_manage')::boolean,false));
  if not((v_permissions->>'warnings')::boolean or (v_permissions->>'bans')::boolean or (v_permissions->>'announcements')::boolean or
   (v_permissions->>'reports')::boolean or (v_permissions->>'audit_view')::boolean or (v_permissions->>'settings_manage')::boolean) then raise exception 'Attribue au moins une permission.'; end if;
  insert into public.sspace_moderator_team(user_id,role,active,permissions,added_by,updated_at)
  values(p_user_id,'moderator',true,v_permissions,v_actor,clock_timestamp())
  on conflict(user_id) do update set role='moderator',active=true,permissions=excluded.permissions,added_by=v_actor,updated_at=clock_timestamp();
  update auth.users set raw_app_meta_data=coalesce(raw_app_meta_data,'{}'::jsonb)||jsonb_build_object('role','moderator','moderation_access',true),updated_at=clock_timestamp() where id=p_user_id;
  perform private.sspace_write_audit(v_actor,'moderator_activated',p_user_id::text,jsonb_build_object('permissions',v_permissions));
  return jsonb_build_object('user_id',p_user_id,'active',true,'permissions',v_permissions,'requires_relogin',true);
 else
  update public.sspace_moderator_team set active=false,updated_at=clock_timestamp() where user_id=p_user_id and role='moderator';
  update auth.users set raw_app_meta_data=case when raw_app_meta_data->>'role'='moderator' then raw_app_meta_data-'role'-'moderation_access' else raw_app_meta_data end,updated_at=clock_timestamp() where id=p_user_id;
  perform private.sspace_write_audit(v_actor,'moderator_deactivated',p_user_id::text,'{}'::jsonb);
  return jsonb_build_object('user_id',p_user_id,'active',false,'requires_relogin',true);
 end if;
end; $$;

drop policy if exists "Members and permitted staff read moderation actions" on public.moderation_actions;
create policy "Members and permitted staff read moderation actions" on public.moderation_actions
for select to authenticated using (
 target_user_id=(select auth.uid())
 or (action_type='warning' and private.sspace_has_permission('warnings'))
 or (action_type in ('ban','unban') and private.sspace_has_permission('bans'))
);

create or replace function private.sspace_guard_suspension_aux()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid();v_owner uuid;v_maintenance boolean:=false;v_message text;
begin
 if v_actor is null then raise exception 'Connexion requise.' using errcode='28000'; end if;
 if tg_table_name='follows' then v_owner:=new.follower_id;
 elsif tg_table_name='friend_requests' then
  if tg_op='INSERT' then v_owner:=new.sender_id;elsif v_actor=new.receiver_id then v_owner:=new.receiver_id;else v_owner:=new.sender_id;end if;
 elsif tg_table_name in ('likes','post_poll_votes','hidden_posts','profile_album_photos') then v_owner:=new.user_id;
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

drop trigger if exists sspace_guard_likes on public.likes;
create trigger sspace_guard_likes before insert or update on public.likes for each row execute function private.sspace_guard_suspension_aux();
drop trigger if exists sspace_guard_follows on public.follows;
create trigger sspace_guard_follows before insert or update on public.follows for each row execute function private.sspace_guard_suspension_aux();
drop trigger if exists sspace_guard_friend_requests on public.friend_requests;
create trigger sspace_guard_friend_requests before insert or update on public.friend_requests for each row execute function private.sspace_guard_suspension_aux();
drop trigger if exists sspace_guard_poll_votes on public.post_poll_votes;
create trigger sspace_guard_poll_votes before insert or update on public.post_poll_votes for each row execute function private.sspace_guard_suspension_aux();
drop trigger if exists sspace_guard_post_mentions on public.post_mentions;
create trigger sspace_guard_post_mentions before insert or update on public.post_mentions for each row execute function private.sspace_guard_suspension_aux();
drop trigger if exists sspace_guard_hidden_posts on public.hidden_posts;
create trigger sspace_guard_hidden_posts before insert or update on public.hidden_posts for each row execute function private.sspace_guard_suspension_aux();
drop trigger if exists sspace_guard_profile_album on public.profile_album_photos;
create trigger sspace_guard_profile_album before insert or update on public.profile_album_photos for each row execute function private.sspace_guard_suspension_aux();
drop trigger if exists sspace_guard_groups on public.groups;
create trigger sspace_guard_groups before insert or update on public.groups for each row execute function private.sspace_guard_suspension_aux();
revoke all on function private.sspace_guard_suspension_aux() from public,anon,authenticated;
