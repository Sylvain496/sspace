
alter table public.sspace_control_settings
  add column if not exists comment_cooldown_seconds integer not null default 5
  check (comment_cooldown_seconds between 2 and 300);

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create table if not exists private.sspace_write_events (
  user_id uuid not null, action text not null, created_at timestamptz not null default clock_timestamp()
);
create index if not exists sspace_write_events_lookup_idx on private.sspace_write_events(user_id,action,created_at desc);
revoke all on private.sspace_write_events from public,anon,authenticated;

create or replace function private.sspace_has_permission(p_permission text)
returns boolean language plpgsql stable security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_role text:=coalesce(auth.jwt()->'app_metadata'->>'role',''); v_allowed boolean:=false;
begin
 if v_user is null then return false; end if;
 if v_role='admin' then return true; end if;
 if p_permission not in ('warnings','bans','announcements','reports','audit_view','settings_manage','team_manage') then return false; end if;
 select coalesce((m.permissions->>p_permission)::boolean,false) into v_allowed
 from public.sspace_moderator_team m where m.user_id=v_user and m.active=true and m.role='moderator';
 return coalesce(v_allowed,false);
end; $$;

create or replace function private.sspace_write_audit(p_actor uuid,p_action text,p_target text,p_details jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=''
as $$
begin
 if p_actor is not null then
  insert into public.sspace_admin_audit(actor_id,action,target,details)
  values(p_actor,left(p_action,100),p_target,coalesce(p_details,'{}'::jsonb));
 end if;
end; $$;

create or replace function private.sspace_guard_member_content()
returns trigger language plpgsql security definer set search_path=''
as $$
declare
 v_actor uuid:=auth.uid(); v_owner uuid; v_kind text; v_maintenance boolean:=false;
 v_message text; v_antispam boolean:=true; v_cooldown integer:=0; v_last timestamptz;
 v_admin boolean:=coalesce(auth.jwt()->'app_metadata'->>'role','')='admin';
begin
 if v_actor is null then raise exception 'Connexion requise.' using errcode='28000'; end if;
 if tg_table_name='posts' then v_owner:=new.user_id;v_kind:='post';
 elsif tg_table_name='comments' then v_owner:=new.user_id;v_kind:='comment';
 elsif tg_table_name='messages' then v_owner:=new.sender_id;v_kind:='message';
 else raise exception 'Action non prise en charge.' using errcode='42501'; end if;
 if v_owner is distinct from v_actor then raise exception 'Tu ne peux publier qu’en ton propre nom.' using errcode='42501'; end if;
 if exists(select 1 from public.user_suspensions s where s.user_id=v_actor and s.revoked_at is null and s.starts_at<=clock_timestamp() and s.expires_at>clock_timestamp()) then
  raise exception 'SSPACE_BANNED: ton compte est temporairement suspendu.' using errcode='42501';
 end if;
 select c.maintenance_enabled,c.maintenance_message,c.antispam_enabled,
  case when v_kind='post' then c.post_cooldown_seconds when v_kind='comment' then c.comment_cooldown_seconds else c.message_cooldown_seconds end
 into v_maintenance,v_message,v_antispam,v_cooldown from public.sspace_control_settings c where c.id=true;
 if coalesce(v_maintenance,false) and not v_admin then
  raise exception 'SSPACE_MAINTENANCE: %',coalesce(v_message,'SSPACE est en maintenance.') using errcode='55000';
 end if;
 if tg_op='INSERT' and coalesce(v_antispam,true) and not v_admin then
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor::text||':'||v_kind,0));
  select max(e.created_at) into v_last from private.sspace_write_events e where e.user_id=v_actor and e.action=v_kind;
  if v_last is not null and v_last>clock_timestamp()-pg_catalog.make_interval(secs=>greatest(v_cooldown,1)) then
   raise exception 'SSPACE_ANTISPAM: attends quelques secondes avant de recommencer.' using errcode='55P03';
  end if;
  insert into private.sspace_write_events(user_id,action) values(v_actor,v_kind);
 end if;
 return new;
end; $$;

drop trigger if exists sspace_guard_posts on public.posts;
create trigger sspace_guard_posts before insert or update on public.posts for each row execute function private.sspace_guard_member_content();
drop trigger if exists sspace_guard_comments on public.comments;
create trigger sspace_guard_comments before insert on public.comments for each row execute function private.sspace_guard_member_content();
drop trigger if exists sspace_guard_messages on public.messages;
create trigger sspace_guard_messages before insert on public.messages for each row execute function private.sspace_guard_member_content();

create or replace function private.modo_apply_action(p_target_user_id uuid,p_action_type text,p_reason text,p_duration_hours integer default null)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid();v_id uuid;v_role text;v_target_moderator boolean:=false;v_expires timestamptz;
begin
 if v_actor is null then raise exception 'Connexion requise.' using errcode='28000'; end if;
 if p_target_user_id is null or p_target_user_id=v_actor then raise exception 'Choisis un autre membre.'; end if;
 if p_action_type not in ('warning','ban') then raise exception 'Type de sanction invalide.'; end if;
 if length(btrim(coalesce(p_reason,''))) not between 3 and 1000 then raise exception 'Le motif doit contenir de 3 à 1000 caractères.'; end if;
 if p_action_type='warning' then
  if not private.sspace_has_permission('warnings') then raise exception 'Permission avertissements refusée.' using errcode='42501'; end if;
  if p_duration_hours is not null then raise exception 'Un avertissement ne possède pas de durée.'; end if;
 else
  if not private.sspace_has_permission('bans') then raise exception 'Permission bannissements refusée.' using errcode='42501'; end if;
  if p_duration_hours is null or p_duration_hours not between 1 and 8760 then raise exception 'La durée doit être comprise entre 1 et 8760 heures.'; end if;
 end if;
 select coalesce(u.raw_app_meta_data->>'role','') into v_role from auth.users u where u.id=p_target_user_id;
 if not found then raise exception 'Membre introuvable.'; end if;
 if v_role='admin' then raise exception 'Un compte administrateur principal ne peut pas être sanctionné ici.' using errcode='42501'; end if;
 select exists(select 1 from public.sspace_moderator_team m where m.user_id=p_target_user_id and m.active=true) into v_target_moderator;
 if v_target_moderator and coalesce(auth.jwt()->'app_metadata'->>'role','')<>'admin' then
  raise exception 'Un modérateur ne peut pas sanctionner un autre modérateur.' using errcode='42501';
 end if;
 if p_action_type='ban' then
  if exists(select 1 from public.user_suspensions s where s.user_id=p_target_user_id and s.revoked_at is null and s.expires_at>clock_timestamp()) then raise exception 'Ce membre possède déjà une suspension active.'; end if;
  v_expires:=clock_timestamp()+pg_catalog.make_interval(hours=>p_duration_hours);
 end if;
 insert into public.moderation_actions(target_user_id,actor_id,action_type,reason,duration_hours,expires_at)
 values(p_target_user_id,v_actor,p_action_type,btrim(p_reason),p_duration_hours,v_expires) returning id into v_id;
 if p_action_type='ban' then
  insert into public.user_suspensions(user_id,moderation_action_id,starts_at,expires_at) values(p_target_user_id,v_id,clock_timestamp(),v_expires);
 end if;
 perform private.sspace_write_audit(v_actor,'moderation_'||p_action_type,p_target_user_id::text,
  jsonb_build_object('action_id',v_id,'reason',btrim(p_reason),'duration_hours',p_duration_hours,'expires_at',v_expires));
 return v_id;
end; $$;

create or replace function private.modo_revoke_suspension(p_suspension_id uuid,p_reason text default 'Suspension levée par la modération')
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid();v_s public.user_suspensions%rowtype;v_action uuid;v_reason text:=left(btrim(coalesce(p_reason,'Suspension levée par la modération')),1000);
begin
 if v_actor is null then raise exception 'Connexion requise.' using errcode='28000'; end if;
 if not private.sspace_has_permission('bans') then raise exception 'Permission bannissements refusée.' using errcode='42501'; end if;
 select * into v_s from public.user_suspensions where id=p_suspension_id for update;
 if not found then raise exception 'Suspension introuvable.'; end if;
 if v_s.revoked_at is not null or v_s.expires_at<=clock_timestamp() then raise exception 'Cette suspension est déjà terminée.'; end if;
 update public.user_suspensions set revoked_at=clock_timestamp(),revoked_by=v_actor where id=p_suspension_id;
 insert into public.moderation_actions(target_user_id,actor_id,action_type,reason) values(v_s.user_id,v_actor,'unban',v_reason) returning id into v_action;
 perform private.sspace_write_audit(v_actor,'moderation_unban',v_s.user_id::text,jsonb_build_object('suspension_id',p_suspension_id,'action_id',v_action,'reason',v_reason));
 return v_action;
end; $$;

create or replace function private.modo_set_moderator(p_user_id uuid,p_active boolean,p_permissions jsonb default null)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=auth.uid();v_target_role text;v_permissions jsonb;v_allowed text[]:=array['warnings','bans','announcements','reports','audit_view','settings_manage'];v_key text;
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
  v_permissions:=jsonb_build_object('warnings',coalesce((v_permissions->>'warnings')::boolean,false),'bans',coalesce((v_permissions->>'bans')::boolean,false),
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

create or replace function private.modo_access_snapshot()
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_user uuid:=auth.uid();v_row public.sspace_moderator_team%rowtype;
begin
 if v_user is null then return '{"role":"member","permissions":{}}'::jsonb; end if;
 if coalesce(auth.jwt()->'app_metadata'->>'role','')='admin' then
  return jsonb_build_object('role','admin','permissions','{"warnings":true,"bans":true,"announcements":true,"reports":true,"audit_view":true,"settings_manage":true,"team_manage":true}'::jsonb);
 end if;
 select * into v_row from public.sspace_moderator_team where user_id=v_user and active=true and role='moderator';
 if not found then return '{"role":"member","permissions":{}}'::jsonb; end if;
 return jsonb_build_object('role','moderator','permissions',v_row.permissions);
end; $$;

create or replace function private.modo_search_members(p_query text)
returns table(user_id uuid,username text,display_name text) language plpgsql stable security definer set search_path=''
as $$
declare v_query text:=lower(btrim(coalesce(p_query,'')));
begin
 if not(private.sspace_has_permission('warnings') or private.sspace_has_permission('bans') or private.sspace_has_permission('team_manage')) then raise exception 'Permission de recherche refusée.' using errcode='42501'; end if;
 if length(v_query)<2 or length(v_query)>40 then raise exception 'Entre au moins 2 caractères.'; end if;
 return query select p.id,p.username,p.display_name from public.profiles p
 where lower(p.username) like '%'||v_query||'%' or lower(p.display_name) like '%'||v_query||'%' order by p.username limit 20;
end; $$;

create or replace function private.modo_user_history(p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_actions jsonb;v_suspensions jsonb;
begin
 if not(private.sspace_has_permission('warnings') or private.sspace_has_permission('bans')) then raise exception 'Permission de consultation refusée.' using errcode='42501'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'action_type',a.action_type,'reason',a.reason,'duration_hours',a.duration_hours,'expires_at',a.expires_at,'created_at',a.created_at,'actor_id',a.actor_id) order by a.created_at desc),'[]'::jsonb)
 into v_actions from (select * from public.moderation_actions where target_user_id=p_user_id order by created_at desc limit 30) a;
 select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'starts_at',s.starts_at,'expires_at',s.expires_at,'revoked_at',s.revoked_at,'active',(s.revoked_at is null and s.expires_at>clock_timestamp())) order by s.created_at desc),'[]'::jsonb)
 into v_suspensions from public.user_suspensions s where s.user_id=p_user_id;
 return jsonb_build_object('actions',v_actions,'suspensions',v_suspensions);
end; $$;

create or replace function private.modo_list_moderators()
returns table(user_id uuid,username text,display_name text,role text,active boolean,permissions jsonb,created_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$
begin
 if not private.sspace_has_permission('team_manage') then raise exception 'Accès administrateur requis.' using errcode='42501'; end if;
 return query select m.user_id,p.username,p.display_name,m.role,m.active,m.permissions,m.created_at
 from public.sspace_moderator_team m left join public.profiles p on p.id=m.user_id order by m.active desc,coalesce(p.username,'') asc;
end; $$;

create or replace function private.modo_list_audit(p_limit integer default 30)
returns table(id bigint,actor_id uuid,action text,target text,details jsonb,created_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$
begin
 if not private.sspace_has_permission('audit_view') then raise exception 'Accès au journal refusé.' using errcode='42501'; end if;
 return query select a.id,a.actor_id,a.action,a.target,a.details,a.created_at from public.sspace_admin_audit a order by a.created_at desc limit greatest(1,least(coalesce(p_limit,30),100));
end; $$;

create or replace function private.modo_my_status()
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_user uuid:=auth.uid();v_suspension jsonb;v_warnings jsonb;
begin
 if v_user is null then return '{}'::jsonb; end if;
 select jsonb_build_object('id',s.id,'expires_at',s.expires_at,'reason',a.reason) into v_suspension
 from public.user_suspensions s join public.moderation_actions a on a.id=s.moderation_action_id
 where s.user_id=v_user and s.revoked_at is null and s.starts_at<=clock_timestamp() and s.expires_at>clock_timestamp()
 order by s.created_at desc limit 1;
 select coalesce(jsonb_agg(jsonb_build_object('reason',x.reason,'created_at',x.created_at) order by x.created_at desc),'[]'::jsonb) into v_warnings
 from (select reason,created_at from public.moderation_actions where target_user_id=v_user and action_type='warning' order by created_at desc limit 3) x;
 return jsonb_build_object('active_suspension',v_suspension,'recent_warnings',v_warnings);
end; $$;

create or replace function private.audit_announcement_change()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_actor uuid:=coalesce(auth.uid(),case when tg_op='DELETE' then old.created_by else new.created_by end);
declare v_id uuid:=case when tg_op='DELETE' then old.id else new.id end;
begin
 perform private.sspace_write_audit(v_actor,case when tg_op='INSERT' then 'announcement_created' when tg_op='UPDATE' then 'announcement_updated' else 'announcement_deleted' end,v_id::text,
 jsonb_build_object('title',case when tg_op='DELETE' then old.title else new.title end,'published',case when tg_op='DELETE' then old.is_published else new.is_published end));
 if tg_op='DELETE' then return old; else return new; end if;
end; $$;
drop trigger if exists sspace_audit_announcements on public.sspace_announcements;
create trigger sspace_audit_announcements after insert or update or delete on public.sspace_announcements for each row execute function private.audit_announcement_change();

create or replace function private.audit_control_settings_change()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 perform private.sspace_write_audit(coalesce(auth.uid(),new.updated_by),'control_settings_updated','platform',
 jsonb_build_object('maintenance_enabled',new.maintenance_enabled,'antispam_enabled',new.antispam_enabled,'post_cooldown_seconds',new.post_cooldown_seconds,
 'comment_cooldown_seconds',new.comment_cooldown_seconds,'message_cooldown_seconds',new.message_cooldown_seconds));
 return new;
end; $$;
drop trigger if exists sspace_audit_control_settings on public.sspace_control_settings;
create trigger sspace_audit_control_settings after update on public.sspace_control_settings for each row execute function private.audit_control_settings_change();

drop policy if exists "Moderators can manage moderation actions" on public.moderation_actions;
drop policy if exists "Members can read their own moderation notices" on public.moderation_actions;
create policy "Members and permitted staff read moderation actions" on public.moderation_actions for select to authenticated
using(target_user_id=(select auth.uid()) or (action_type in ('warning','unban') and private.sspace_has_permission('warnings')) or (action_type='ban' and private.sspace_has_permission('bans')));
revoke insert,update,delete on public.moderation_actions from anon,authenticated;
grant select on public.moderation_actions to authenticated;

drop policy if exists "Moderators can manage suspensions" on public.user_suspensions;
drop policy if exists "Members can read own suspension status" on public.user_suspensions;
create policy "Members and permitted staff read suspensions" on public.user_suspensions for select to authenticated
using(user_id=(select auth.uid()) or private.sspace_has_permission('bans'));
revoke insert,update,delete on public.user_suspensions from anon,authenticated;
grant select on public.user_suspensions to authenticated;

drop policy if exists "Staff manage announcements" on public.sspace_announcements;
drop policy if exists "Published announcements are readable" on public.sspace_announcements;
create policy "Published announcements are readable" on public.sspace_announcements for select to anon,authenticated
using(is_published=true and starts_at<=now() and (ends_at is null or ends_at>now()));
create policy "Announcement staff read all" on public.sspace_announcements for select to authenticated using(private.sspace_has_permission('announcements'));
create policy "Announcement staff create" on public.sspace_announcements for insert to authenticated with check(private.sspace_has_permission('announcements') and created_by=(select auth.uid()));
create policy "Announcement staff update" on public.sspace_announcements for update to authenticated using(private.sspace_has_permission('announcements')) with check(private.sspace_has_permission('announcements'));
create policy "Announcement staff delete" on public.sspace_announcements for delete to authenticated using(private.sspace_has_permission('announcements'));

drop policy if exists "Staff read control settings" on public.sspace_control_settings;
drop policy if exists "Admins update control settings" on public.sspace_control_settings;
create policy "Admins read control settings" on public.sspace_control_settings for select to authenticated using(private.sspace_has_permission('settings_manage'));
create policy "Admins update control settings" on public.sspace_control_settings for update to authenticated
using(private.sspace_has_permission('settings_manage')) with check(private.sspace_has_permission('settings_manage') and updated_by=(select auth.uid()));

drop policy if exists "Admins read audit journal" on public.sspace_admin_audit;
drop policy if exists "Staff append audit journal" on public.sspace_admin_audit;
create policy "Permitted staff read audit journal" on public.sspace_admin_audit for select to authenticated using(private.sspace_has_permission('audit_view'));
revoke insert,update,delete on public.sspace_admin_audit from anon,authenticated;
grant select on public.sspace_admin_audit to authenticated;

drop policy if exists "Admins manage moderator team" on public.sspace_moderator_team;
create policy "Admins read moderator team" on public.sspace_moderator_team for select to authenticated using(private.sspace_has_permission('team_manage'));
revoke insert,update,delete on public.sspace_moderator_team from anon,authenticated;
grant select on public.sspace_moderator_team to authenticated;

revoke all on function private.sspace_has_permission(text) from public,anon;
revoke all on function private.sspace_write_audit(uuid,text,text,jsonb) from public,anon,authenticated;
revoke all on function private.sspace_guard_member_content() from public,anon,authenticated;
revoke all on function private.modo_apply_action(uuid,text,text,integer) from public,anon;
revoke all on function private.modo_revoke_suspension(uuid,text) from public,anon;
revoke all on function private.modo_set_moderator(uuid,boolean,jsonb) from public,anon;
revoke all on function private.modo_access_snapshot() from public,anon;
revoke all on function private.modo_search_members(text) from public,anon;
revoke all on function private.modo_user_history(uuid) from public,anon;
revoke all on function private.modo_list_moderators() from public,anon;
revoke all on function private.modo_list_audit(integer) from public,anon;
revoke all on function private.modo_my_status() from public,anon;
grant execute on function private.sspace_has_permission(text) to authenticated;
grant execute on function private.modo_apply_action(uuid,text,text,integer) to authenticated;
grant execute on function private.modo_revoke_suspension(uuid,text) to authenticated;
grant execute on function private.modo_set_moderator(uuid,boolean,jsonb) to authenticated;
grant execute on function private.modo_access_snapshot() to authenticated;
grant execute on function private.modo_search_members(text) to authenticated;
grant execute on function private.modo_user_history(uuid) to authenticated;
grant execute on function private.modo_list_moderators() to authenticated;
grant execute on function private.modo_list_audit(integer) to authenticated;
grant execute on function private.modo_my_status() to authenticated;

create or replace function public.modo_get_my_access() returns jsonb language sql stable security invoker set search_path='' as $$ select private.modo_access_snapshot(); $$;
create or replace function public.modo_search_members(p_query text) returns table(user_id uuid,username text,display_name text) language sql stable security invoker set search_path='' as $$ select * from private.modo_search_members(p_query); $$;
create or replace function public.modo_user_history(p_user_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$ select private.modo_user_history(p_user_id); $$;
create or replace function public.modo_list_moderators() returns table(user_id uuid,username text,display_name text,role text,active boolean,permissions jsonb,created_at timestamptz) language sql stable security invoker set search_path='' as $$ select * from private.modo_list_moderators(); $$;
create or replace function public.modo_list_audit(p_limit integer default 30) returns table(id bigint,actor_id uuid,action text,target text,details jsonb,created_at timestamptz) language sql stable security invoker set search_path='' as $$ select * from private.modo_list_audit(p_limit); $$;
create or replace function public.modo_my_status() returns jsonb language sql stable security invoker set search_path='' as $$ select private.modo_my_status(); $$;
create or replace function public.modo_issue_action(p_target_user_id uuid,p_action_type text,p_reason text,p_duration_hours integer default null) returns uuid language sql security invoker set search_path='' as $$ select private.modo_apply_action(p_target_user_id,p_action_type,p_reason,p_duration_hours); $$;
create or replace function public.modo_revoke_ban(p_suspension_id uuid,p_reason text default 'Suspension levée par la modération') returns uuid language sql security invoker set search_path='' as $$ select private.modo_revoke_suspension(p_suspension_id,p_reason); $$;
create or replace function public.modo_set_moderator(p_user_id uuid,p_active boolean,p_permissions jsonb default null) returns jsonb language sql security invoker set search_path='' as $$ select private.modo_set_moderator(p_user_id,p_active,p_permissions); $$;

revoke all on function public.modo_get_my_access() from public,anon;
revoke all on function public.modo_search_members(text) from public,anon;
revoke all on function public.modo_user_history(uuid) from public,anon;
revoke all on function public.modo_list_moderators() from public,anon;
revoke all on function public.modo_list_audit(integer) from public,anon;
revoke all on function public.modo_my_status() from public,anon;
revoke all on function public.modo_issue_action(uuid,text,text,integer) from public,anon;
revoke all on function public.modo_revoke_ban(uuid,text) from public,anon;
revoke all on function public.modo_set_moderator(uuid,boolean,jsonb) from public,anon;
grant execute on function public.modo_get_my_access() to authenticated;
grant execute on function public.modo_search_members(text) to authenticated;
grant execute on function public.modo_user_history(uuid) to authenticated;
grant execute on function public.modo_list_moderators() to authenticated;
grant execute on function public.modo_list_audit(integer) to authenticated;
grant execute on function public.modo_my_status() to authenticated;
grant execute on function public.modo_issue_action(uuid,text,text,integer) to authenticated;
grant execute on function public.modo_revoke_ban(uuid,text) to authenticated;
grant execute on function public.modo_set_moderator(uuid,boolean,jsonb) to authenticated;
