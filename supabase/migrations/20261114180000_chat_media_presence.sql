alter table public.profiles add column if not exists last_seen_at timestamptz;
alter table public.messages add column if not exists message_type text not null default 'text';
alter table public.messages add column if not exists media_path text;
alter table public.messages add column if not exists link_url text;
do $$
begin
 if not exists (select 1 from pg_constraint where conname='messages_message_type_check' and conrelid='public.messages'::regclass) then
  alter table public.messages add constraint messages_message_type_check check (message_type in ('text','image','audio','link'));
 end if;
 if not exists (select 1 from pg_constraint where conname='messages_media_path_length_check' and conrelid='public.messages'::regclass) then
  alter table public.messages add constraint messages_media_path_length_check check (media_path is null or length(media_path) <= 500);
 end if;
 if not exists (select 1 from pg_constraint where conname='messages_link_url_check' and conrelid='public.messages'::regclass) then
  alter table public.messages add constraint messages_link_url_check check (link_url is null or (length(link_url) <= 2048 and link_url ~ '^https?://'));
 end if;
end $$;
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('chat-attachments','chat-attachments',false,12582912,array['image/jpeg','image/png','image/webp','image/gif','audio/webm','audio/ogg','audio/mp4','audio/mpeg','audio/wav'])
on conflict (id) do update set public=false,file_size_limit=12582912,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists "Chat participants can read attachments" on storage.objects;
create policy "Chat participants can read attachments" on storage.objects for select to authenticated
using (bucket_id='chat-attachments' and exists (
 select 1 from public.conversations c where c.id::text=(storage.foldername(name))[1]
 and (c.user_one=(select auth.uid()) or c.user_two=(select auth.uid()))
));
drop policy if exists "Chat participants can upload own attachments" on storage.objects;
create policy "Chat participants can upload own attachments" on storage.objects for insert to authenticated
with check (bucket_id='chat-attachments' and (storage.foldername(name))[2]=(select auth.uid())::text and exists (
 select 1 from public.conversations c where c.id::text=(storage.foldername(name))[1]
 and (c.user_one=(select auth.uid()) or c.user_two=(select auth.uid()))
));
