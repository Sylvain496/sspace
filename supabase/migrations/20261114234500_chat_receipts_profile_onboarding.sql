create table if not exists public.profile_private_details (
  user_id uuid primary key references auth.users(id) on delete cascade,
  first_name text,
  last_name text,
  age smallint,
  gender text,
  region text,
  zodiac_sign text,
  hobbies text not null default '',
  music_preferences text not null default '',
  updated_at timestamptz not null default now(),
  constraint profile_private_age_check check (age is null or age between 1 and 120),
  constraint profile_private_gender_check check (gender is null or gender in ('femme','homme','non_binaire','prefere_ne_pas_repondre')),
  constraint profile_private_zodiac_check check (zodiac_sign is null or zodiac_sign in ('belier','taureau','gemeaux','cancer','lion','vierge','balance','scorpion','sagittaire','capricorne','verseau','poissons','non_defini'))
);
alter table public.profile_private_details enable row level security;
revoke all on public.profile_private_details from anon, public;
grant select,insert,update on public.profile_private_details to authenticated;
drop policy if exists "Users read their private profile details" on public.profile_private_details;
create policy "Users read their private profile details" on public.profile_private_details
for select to authenticated using ((select auth.uid())=user_id);
drop policy if exists "Users create their private profile details" on public.profile_private_details;
create policy "Users create their private profile details" on public.profile_private_details
for insert to authenticated with check ((select auth.uid())=user_id);
drop policy if exists "Users update their private profile details" on public.profile_private_details;
create policy "Users update their private profile details" on public.profile_private_details
for update to authenticated using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);

grant update(read_at) on public.messages to authenticated;
drop policy if exists "Recipients mark incoming messages as read" on public.messages;
create policy "Recipients mark incoming messages as read" on public.messages
for update to authenticated
using (
  sender_id <> (select auth.uid())
  and read_at is null
  and exists(select 1 from public.conversations c where c.id=conversation_id and ((select auth.uid())=c.user_one or (select auth.uid())=c.user_two))
)
with check (
  sender_id <> (select auth.uid())
  and read_at is not null
  and exists(select 1 from public.conversations c where c.id=conversation_id and ((select auth.uid())=c.user_one or (select auth.uid())=c.user_two))
);
create index if not exists messages_unread_conversation_idx on public.messages(conversation_id,sender_id,read_at) where read_at is null;