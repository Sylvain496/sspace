alter table public.posts
  add column if not exists media_url text,
  add column if not exists media_type text,
  add column if not exists poll_question text;

alter table public.posts drop constraint if exists posts_media_type_check;
alter table public.posts add constraint posts_media_type_check
  check (media_type is null or media_type in ('audio','video'));
alter table public.posts drop constraint if exists posts_media_url_check;
alter table public.posts add constraint posts_media_url_check
  check (media_url is null or (length(media_url) <= 2048 and media_url ~ '^https?://'));
alter table public.posts drop constraint if exists posts_poll_question_check;
alter table public.posts add constraint posts_poll_question_check
  check (poll_question is null or length(poll_question) between 1 and 180);

create table if not exists public.post_poll_options (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  option_text text not null check (length(option_text) between 1 and 100),
  created_at timestamptz not null default now(),
  constraint post_poll_options_id_post_unique unique (id,post_id)
);
create index if not exists post_poll_options_post_idx on public.post_poll_options(post_id);

create table if not exists public.post_poll_votes (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  option_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint post_poll_votes_one_per_user unique(post_id,user_id),
  constraint post_poll_votes_option_post_fk foreign key(option_id,post_id)
    references public.post_poll_options(id,post_id) on delete cascade
);
create index if not exists post_poll_votes_option_idx on public.post_poll_votes(option_id);

create table if not exists public.post_mentions (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  mentioned_user_id uuid not null references public.profiles(id) on delete cascade,
  tagged_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint post_mentions_once unique(post_id,mentioned_user_id),
  constraint post_mentions_no_self check (tagged_by <> mentioned_user_id)
);
create index if not exists post_mentions_post_idx on public.post_mentions(post_id);
create index if not exists post_mentions_user_idx on public.post_mentions(mentioned_user_id);

alter table public.post_poll_options enable row level security;
alter table public.post_poll_votes enable row level security;
alter table public.post_mentions enable row level security;
grant select on public.post_poll_options,public.post_poll_votes,public.post_mentions to authenticated;
grant insert on public.post_poll_votes to authenticated;

drop policy if exists "Poll options visible with their post" on public.post_poll_options;
create policy "Poll options visible with their post" on public.post_poll_options
for select to authenticated using (exists(select 1 from public.posts p where p.id=post_id));
drop policy if exists "Poll votes visible with their post" on public.post_poll_votes;
create policy "Poll votes visible with their post" on public.post_poll_votes
for select to authenticated using (exists(select 1 from public.posts p where p.id=post_id));
drop policy if exists "Members vote once on visible polls" on public.post_poll_votes;
create policy "Members vote once on visible polls" on public.post_poll_votes
for insert to authenticated with check (
  user_id=(select auth.uid())
  and exists(select 1 from public.posts p where p.id=post_id and p.poll_question is not null)
  and exists(select 1 from public.post_poll_options o where o.id=option_id and o.post_id=post_id)
);
drop policy if exists "Post mentions visible with their post" on public.post_mentions;
create policy "Post mentions visible with their post" on public.post_mentions
for select to authenticated using (exists(select 1 from public.posts p where p.id=post_id));

create or replace function public.create_post_bundle(
  p_title text,
  p_content text,
  p_image_url text,
  p_media_url text,
  p_media_type text,
  p_poll_question text,
  p_poll_options text[],
  p_mentioned_user_ids uuid[]
) returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_user uuid := auth.uid();
  v_post uuid;
  v_count integer;
begin
  if v_user is null then raise exception 'Connexion requise.'; end if;
  if coalesce(length(p_title),0)>160 then raise exception 'Titre trop long.'; end if;
  if coalesce(length(p_content),0)>20000 then raise exception 'Publication trop longue.'; end if;
  if p_media_type is not null and p_media_type not in ('audio','video') then raise exception 'Type de média invalide.'; end if;
  if p_media_url is not null and (length(p_media_url)>2048 or p_media_url !~ '^https?://') then raise exception 'Adresse média invalide.'; end if;
  if p_image_url is not null and (length(p_image_url)>2048 or p_image_url !~ '^https?://') then raise exception 'Adresse image invalide.'; end if;
  if (p_media_url is null) <> (p_media_type is null) then raise exception 'Fichier média incomplet.'; end if;

  if p_poll_question is not null then
    if length(trim(p_poll_question)) not between 1 and 180 then raise exception 'Question de sondage invalide.'; end if;
    if coalesce(cardinality(p_poll_options),0) not between 2 and 6 then raise exception 'Un sondage doit contenir de 2 à 6 choix.'; end if;
    if exists(select 1 from unnest(p_poll_options) x where length(trim(x)) not between 1 and 100) then raise exception 'Un choix de sondage est vide ou trop long.'; end if;
    if (select count(distinct lower(trim(x))) from unnest(p_poll_options) x) <> cardinality(p_poll_options) then raise exception 'Les choix du sondage doivent être différents.'; end if;
  elsif p_poll_options is not null and cardinality(p_poll_options)>0 then
    raise exception 'Une question est requise pour le sondage.';
  end if;

  if coalesce(cardinality(p_mentioned_user_ids),0)>0 then
    select count(distinct x) into v_count from unnest(p_mentioned_user_ids) x;
    if v_count <> cardinality(p_mentioned_user_ids) then raise exception 'Un ami est sélectionné plusieurs fois.'; end if;
    if exists (
      select 1 from unnest(p_mentioned_user_ids) x
      where x=v_user or not exists (
        select 1 from public.friend_requests fr
        where fr.status='accepted'
          and ((fr.sender_id=v_user and fr.receiver_id=x) or (fr.receiver_id=v_user and fr.sender_id=x))
      )
    ) then raise exception 'Tu peux identifier uniquement tes amis acceptés.'; end if;
  end if;

  insert into public.posts(user_id,title,content,image_url,media_url,media_type,poll_question)
  values(v_user,coalesce(p_title,''),coalesce(nullif(p_content,''),' '),p_image_url,p_media_url,p_media_type,nullif(trim(p_poll_question),''))
  returning id into v_post;

  if p_poll_question is not null then
    insert into public.post_poll_options(post_id,option_text)
    select v_post,trim(x) from unnest(p_poll_options) x;
  end if;

  if coalesce(cardinality(p_mentioned_user_ids),0)>0 then
    insert into public.post_mentions(post_id,mentioned_user_id,tagged_by)
    select v_post,x,v_user from unnest(p_mentioned_user_ids) x;
  end if;
  return v_post;
end;
$function$;

revoke all on function public.create_post_bundle(text,text,text,text,text,text,text[],uuid[]) from public;
grant execute on function public.create_post_bundle(text,text,text,text,text,text,text[],uuid[]) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('post-media','post-media',true,52428800,
 array['audio/mpeg','audio/mp3','audio/wav','audio/x-wav','audio/ogg','audio/webm','audio/mp4','audio/aac','video/mp4','video/webm'])
on conflict(id) do update set public=true,file_size_limit=52428800,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "Members upload own post media" on storage.objects;
create policy "Members upload own post media" on storage.objects
for insert to authenticated with check (
  bucket_id='post-media' and (storage.foldername(name))[1]=(select auth.uid())::text
);
