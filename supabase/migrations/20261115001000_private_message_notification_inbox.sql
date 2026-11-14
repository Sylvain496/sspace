create table if not exists public.private_message_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  message_id uuid not null unique references public.messages(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists private_message_notifications_user_created_idx
  on public.private_message_notifications(user_id,created_at desc);
alter table public.private_message_notifications enable row level security;
revoke all on public.private_message_notifications from anon, public;
grant select on public.private_message_notifications to authenticated;
drop policy if exists "Users read their own private message notifications" on public.private_message_notifications;
create policy "Users read their own private message notifications"
on public.private_message_notifications
for select to authenticated using ((select auth.uid())=user_id);

do $publication$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='private_message_notifications'
  ) then
    alter publication supabase_realtime add table public.private_message_notifications;
  end if;
end
$publication$;

create or replace function private.notify_private_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_recipient uuid;
begin
  select case when c.user_one = new.sender_id then c.user_two else c.user_one end
    into v_recipient
  from public.conversations c
  where c.id = new.conversation_id
    and (c.user_one = new.sender_id or c.user_two = new.sender_id);

  if v_recipient is null then
    return new;
  end if;

  insert into public.private_message_notifications(user_id,message_id,conversation_id,sender_id)
  values(v_recipient,new.id,new.conversation_id,new.sender_id)
  on conflict (message_id) do nothing;

  return new;
end;
$function$;

drop policy if exists "Users receive their own private message notifications" on realtime.messages;
