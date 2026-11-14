alter table public.profiles add column if not exists username_confirmed boolean not null default true;
update public.profiles set username_confirmed=true where username_confirmed is null;
alter table public.profiles alter column username_confirmed set default false;
create unique index if not exists profiles_username_lower_unique on public.profiles (lower(username));
alter table public.profiles drop constraint if exists profiles_username_format_check;
alter table public.profiles add constraint profiles_username_format_check check (username ~ '^[A-Za-z0-9_]{3,20}$');

create table if not exists public.friend_requests (
 id uuid primary key default gen_random_uuid(),
 sender_id uuid not null references auth.users(id) on delete cascade,
 receiver_id uuid not null references auth.users(id) on delete cascade,
 status text not null default 'pending' check (status in ('pending','accepted','declined')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint friend_requests_not_self check (sender_id <> receiver_id),
 constraint friend_requests_sender_receiver_unique unique (sender_id,receiver_id)
);
create index if not exists friend_requests_receiver_status_idx on public.friend_requests(receiver_id,status);
create index if not exists friend_requests_sender_status_idx on public.friend_requests(sender_id,status);
alter table public.friend_requests enable row level security;
grant select,insert,update on public.friend_requests to authenticated;
drop policy if exists "Participants read friend requests" on public.friend_requests;
create policy "Participants read friend requests" on public.friend_requests for select to authenticated
using ((select auth.uid())=sender_id or (select auth.uid())=receiver_id);
drop policy if exists "Users send own friend requests" on public.friend_requests;
create policy "Users send own friend requests" on public.friend_requests for insert to authenticated
with check ((select auth.uid())=sender_id and status='pending' and sender_id<>receiver_id);
drop policy if exists "Receivers respond to friend requests" on public.friend_requests;
create policy "Receivers respond to friend requests" on public.friend_requests for update to authenticated
using ((select auth.uid())=receiver_id and status='pending')
with check ((select auth.uid())=receiver_id and status in ('accepted','declined'));

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
 insert into public.profiles (id,username,username_confirmed,display_name)
 values (new.id,'membre_' || substr(replace(new.id::text,'-',''),1,10),false,
  coalesce(nullif(new.raw_user_meta_data ->> 'display_name',''),'Nouveau membre'))
 on conflict (id) do nothing;
 return new;
end;
$function$;
