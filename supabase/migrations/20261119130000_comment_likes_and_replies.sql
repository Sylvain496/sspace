alter table public.comments
  add column if not exists parent_comment_id uuid;

create unique index if not exists comments_id_post_id_uidx
  on public.comments(id, post_id);

alter table public.comments
  drop constraint if exists comments_parent_same_post_fk;
alter table public.comments
  add constraint comments_parent_same_post_fk
  foreign key (parent_comment_id, post_id)
  references public.comments(id, post_id)
  on delete cascade;

create index if not exists comments_parent_comment_idx
  on public.comments(parent_comment_id, created_at);

create table if not exists public.comment_likes (
  id uuid primary key default gen_random_uuid(),
  comment_id uuid not null references public.comments(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint comment_likes_one_per_user unique(comment_id, user_id)
);

create index if not exists comment_likes_comment_idx
  on public.comment_likes(comment_id);

alter table public.comment_likes enable row level security;
grant select, insert, delete on public.comment_likes to authenticated;

drop policy if exists "Comment likes are visible" on public.comment_likes;
create policy "Comment likes are visible" on public.comment_likes
  for select to authenticated using (true);

drop policy if exists "Members like comments as themselves" on public.comment_likes;
create policy "Members like comments as themselves" on public.comment_likes
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Members remove their comment likes" on public.comment_likes;
create policy "Members remove their comment likes" on public.comment_likes
  for delete to authenticated
  using (user_id = (select auth.uid()));

create or replace function private.enforce_comment_reply()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.parent_comment_id is not null then
    if not exists (
      select 1 from public.comments parent
      where parent.id = new.parent_comment_id
        and parent.post_id = new.post_id
        and parent.parent_comment_id is null
    ) then
      raise exception 'Une réponse doit viser un commentaire principal de la même publication.'
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.enforce_comment_reply() from public, anon, authenticated;
drop trigger if exists enforce_comment_reply_before_insert on public.comments;
create trigger enforce_comment_reply_before_insert
before insert on public.comments
for each row execute function private.enforce_comment_reply();
