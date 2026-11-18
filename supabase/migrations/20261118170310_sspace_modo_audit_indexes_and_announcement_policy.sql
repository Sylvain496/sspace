
alter table private.sspace_write_events
  add column if not exists id bigint generated always as identity;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='private.sspace_write_events'::regclass and contype='p'
  ) then
    alter table private.sspace_write_events add constraint sspace_write_events_pkey primary key(id);
  end if;
end $$;

create index if not exists moderation_actions_actor_id_idx on public.moderation_actions(actor_id);
create index if not exists sspace_admin_audit_actor_id_idx on public.sspace_admin_audit(actor_id);
create index if not exists sspace_announcements_created_by_idx on public.sspace_announcements(created_by);
create index if not exists sspace_control_settings_updated_by_idx on public.sspace_control_settings(updated_by);
create index if not exists sspace_moderator_team_added_by_idx on public.sspace_moderator_team(added_by);
create index if not exists user_suspensions_revoked_by_idx on public.user_suspensions(revoked_by);

drop policy if exists "Published announcements are readable" on public.sspace_announcements;
drop policy if exists "Announcement staff read all" on public.sspace_announcements;
create policy "Published announcements are readable by anon" on public.sspace_announcements
for select to anon using (is_published=true and starts_at<=now() and (ends_at is null or ends_at>now()));
create policy "Authenticated announcement readers" on public.sspace_announcements
for select to authenticated using (
  (is_published=true and starts_at<=now() and (ends_at is null or ends_at>now()))
  or private.sspace_has_permission('announcements')
);
