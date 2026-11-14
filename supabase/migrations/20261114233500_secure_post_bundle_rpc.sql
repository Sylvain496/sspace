revoke all on function public.create_post_bundle(text,text,text,text,text,text,text[],uuid[]) from public, anon;
grant execute on function public.create_post_bundle(text,text,text,text,text,text,text[],uuid[]) to authenticated;

create index if not exists post_poll_votes_option_post_idx on public.post_poll_votes(option_id,post_id);
create index if not exists post_poll_votes_user_id_idx on public.post_poll_votes(user_id);
create index if not exists post_mentions_tagged_by_idx on public.post_mentions(tagged_by);
