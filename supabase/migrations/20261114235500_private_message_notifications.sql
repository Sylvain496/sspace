create index if not exists messages_sender_id_idx on public.messages(sender_id);

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

  begin
    perform realtime.send(
      jsonb_build_object(
        'conversation_id', new.conversation_id,
        'message_id', new.id,
        'sender_id', new.sender_id
      ),
      'new_private_message',
      'user:' || v_recipient::text || ':notifications',
      true
    );
  exception when others then
    raise warning 'SSPACE private message notification was not delivered: %', sqlerrm;
  end;

  return new;
end;
$function$;

revoke all on function private.notify_private_message() from public, anon, authenticated;

drop trigger if exists notify_private_message_after_insert on public.messages;
create trigger notify_private_message_after_insert
after insert on public.messages
for each row execute function private.notify_private_message();

drop policy if exists "Users receive their own private message notifications" on realtime.messages;
create policy "Users receive their own private message notifications"
on realtime.messages
for select to authenticated
using (
  extension = 'broadcast'
  and (select realtime.topic()) = 'user:' || (select auth.uid())::text || ':notifications'
);
