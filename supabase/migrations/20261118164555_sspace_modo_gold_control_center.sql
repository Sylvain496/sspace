-- SSPACE Gold MODO control center: announcements, control settings, audit journal and moderator registry.
create table if not exists public.sspace_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 3 and 120),
  message text not null check (char_length(message) between 1 and 4000),
  visual_style text not null default 'gold' check (visual_style in ('gold','urgent','classic')),
  animation text not null default 'reveal' check (animation in ('reveal','glow','ticker','spark')),
  is_published boolean not null default false,
  show_on_login boolean not null default true,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at)
);
create index if not exists sspace_announcements_live_idx on public.sspace_announcements (is_published, starts_at desc, ends_at);

create table if not exists public.sspace_control_settings (
  id boolean primary key default true check (id),
  maintenance_enabled boolean not null default false,
  maintenance_message text not null default 'SSPACE est temporairement en maintenance. Nous revenons bientôt.',
  antispam_enabled boolean not null default true,
  post_cooldown_seconds integer not null default 20 check (post_cooldown_seconds between 5 and 3600),
  message_cooldown_seconds integer not null default 2 check (message_cooldown_seconds between 1 and 120),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);
insert into public.sspace_control_settings (id) values (true) on conflict (id) do nothing;

create table if not exists public.sspace_admin_audit (
  id bigint generated always as identity primary key,
  actor_id uuid not null references auth.users(id) on delete restrict,
  action text not null check (char_length(action) between 2 and 100),
  target text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists sspace_admin_audit_created_idx on public.sspace_admin_audit (created_at desc);

create table if not exists public.sspace_moderator_team (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'moderator' check (role in ('moderator','admin')),
  active boolean not null default true,
  permissions jsonb not null default '{"warnings":true,"bans":true,"announcements":true,"reports":true}'::jsonb,
  added_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.sspace_announcements enable row level security;
alter table public.sspace_control_settings enable row level security;
alter table public.sspace_admin_audit enable row level security;
alter table public.sspace_moderator_team enable row level security;

drop policy if exists "Published announcements are readable" on public.sspace_announcements;
create policy "Published announcements are readable" on public.sspace_announcements
for select to anon, authenticated using (
  is_published = true and starts_at <= now() and (ends_at is null or ends_at > now())
);
drop policy if exists "Staff manage announcements" on public.sspace_announcements;
create policy "Staff manage announcements" on public.sspace_announcements
for all to authenticated
using ((auth.jwt()->'app_metadata'->>'role') in ('admin','moderator'))
with check ((auth.jwt()->'app_metadata'->>'role') in ('admin','moderator'));

drop policy if exists "Staff read control settings" on public.sspace_control_settings;
create policy "Staff read control settings" on public.sspace_control_settings
for select to authenticated using ((auth.jwt()->'app_metadata'->>'role') in ('admin','moderator'));
drop policy if exists "Admins update control settings" on public.sspace_control_settings;
create policy "Admins update control settings" on public.sspace_control_settings
for update to authenticated
using ((auth.jwt()->'app_metadata'->>'role') = 'admin')
with check ((auth.jwt()->'app_metadata'->>'role') = 'admin' and updated_by = auth.uid());

drop policy if exists "Admins read audit journal" on public.sspace_admin_audit;
create policy "Admins read audit journal" on public.sspace_admin_audit
for select to authenticated using ((auth.jwt()->'app_metadata'->>'role') = 'admin');
drop policy if exists "Staff append audit journal" on public.sspace_admin_audit;
create policy "Staff append audit journal" on public.sspace_admin_audit
for insert to authenticated with check (
  (auth.jwt()->'app_metadata'->>'role') in ('admin','moderator') and actor_id = auth.uid()
);

drop policy if exists "Admins manage moderator team" on public.sspace_moderator_team;
create policy "Admins manage moderator team" on public.sspace_moderator_team
for all to authenticated
using ((auth.jwt()->'app_metadata'->>'role') = 'admin')
with check ((auth.jwt()->'app_metadata'->>'role') = 'admin');

grant select on public.sspace_announcements to anon, authenticated;
grant insert, update, delete, select on public.sspace_announcements to authenticated;
grant select, update on public.sspace_control_settings to authenticated;
grant select, insert on public.sspace_admin_audit to authenticated;
grant select, insert, update, delete on public.sspace_moderator_team to authenticated;
grant usage, select on sequence public.sspace_admin_audit_id_seq to authenticated;
