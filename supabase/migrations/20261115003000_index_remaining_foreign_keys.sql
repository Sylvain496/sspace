-- Cover the remaining foreign keys flagged by the Supabase performance advisor.
create index if not exists comments_user_id_idx on public.comments(user_id);
create index if not exists conversation_settings_user_id_idx on public.conversation_settings(user_id);
create index if not exists likes_user_id_idx on public.likes(user_id);
