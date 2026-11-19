create or replace function private.trg_notify_social_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_target_user uuid;
  v_actor uuid;
  v_entity uuid;
  v_type text;
  v_preview text;
begin
  if tg_table_name = 'likes' then
    select p.user_id into v_target_user from public.posts p where p.id = new.post_id;
    v_actor := new.user_id;
    v_entity := new.post_id;
    v_type := 'like';
    v_preview := 'a aimé ta publication.';
  elsif tg_table_name = 'comments' then
    if new.parent_comment_id is not null then
      select c.user_id into v_target_user from public.comments c where c.id = new.parent_comment_id;
      v_type := 'comment_reply';
      v_preview := left(new.content, 80);
    else
      select p.user_id into v_target_user from public.posts p where p.id = new.post_id;
      v_type := 'comment';
      v_preview := left(new.content, 80);
    end if;
    v_actor := new.user_id;
    v_entity := new.post_id;
  elsif tg_table_name = 'comment_likes' then
    select c.user_id into v_target_user from public.comments c where c.id = new.comment_id;
    v_actor := new.user_id;
    v_entity := new.comment_id;
    v_type := 'comment_like';
    v_preview := 'a aimé ton commentaire.';
  elsif tg_table_name = 'friend_requests' then
    if tg_op = 'INSERT' and new.status = 'pending' then
      v_target_user := new.receiver_id;
      v_actor := new.sender_id;
      v_entity := new.id;
      v_type := 'friend_request';
      v_preview := 't’a envoyé une demande d’ami.';
    elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status = 'accepted' then
      v_target_user := new.sender_id;
      v_actor := new.receiver_id;
      v_entity := new.id;
      v_type := 'friend_accept';
      v_preview := 'a accepté ta demande d’ami.';
    end if;
  elsif tg_table_name = 'post_mentions' then
    v_target_user := new.mentioned_user_id;
    v_actor := new.tagged_by;
    v_entity := new.post_id;
    v_type := 'mention';
    v_preview := 't’a identifié dans une publication.';
  elsif tg_table_name = 'follows' then
    v_target_user := new.following_id;
    v_actor := new.follower_id;
    v_entity := new.follower_id;
    v_type := 'friend_activity';
    v_preview := 'a commencé à te suivre.';
  end if;

  if v_target_user is not null and v_actor is not null and v_target_user <> v_actor then
    insert into public.user_notifications(user_id, actor_id, notif_type, entity_id, preview_text)
    values (v_target_user, v_actor, v_type, v_entity, coalesce(v_preview, 'Nouvelle activité sur ton profil.'));
  end if;
  return new;
end;
$function$;

drop trigger if exists notify_on_comment_like on public.comment_likes;
create trigger notify_on_comment_like
after insert on public.comment_likes
for each row execute function private.trg_notify_social_event();
