-- SSPACE statistics, private music library and server-validated rewards
create table if not exists public.sspace_reward_ledger (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 points integer not null check (points > 0 and points <= 1000),
 reason text not null, source_key text not null, created_at timestamptz not null default now(),
 constraint sspace_reward_ledger_user_source_unique unique(user_id,source_key)
);
create index if not exists sspace_reward_ledger_user_created_idx on public.sspace_reward_ledger(user_id,created_at desc);
create table if not exists public.sspace_badge_catalog (
 code text primary key, title text not null, description text not null,
 icon text not null default '🏅', points_threshold integer not null check(points_threshold>=0),
 active boolean not null default true
);
create table if not exists public.sspace_user_badges (
 user_id uuid not null references auth.users(id) on delete cascade,
 badge_code text not null references public.sspace_badge_catalog(code) on delete cascade,
 awarded_at timestamptz not null default now(), primary key(user_id,badge_code)
);
create table if not exists public.sspace_music_plays (
 user_id uuid not null references auth.users(id) on delete cascade,
 track_id uuid not null references public.sspace_music_tracks(id) on delete cascade,
 play_date date not null default ((now() at time zone 'America/Toronto')::date),
 played_at timestamptz not null default now(), primary key(user_id,track_id,play_date)
);
create index if not exists sspace_music_plays_user_date_idx on public.sspace_music_plays(user_id,play_date desc);
alter table public.sspace_reward_ledger enable row level security;
alter table public.sspace_badge_catalog enable row level security;
alter table public.sspace_user_badges enable row level security;
alter table public.sspace_music_plays enable row level security;
drop policy if exists sspace_reward_ledger_read_own on public.sspace_reward_ledger;
create policy sspace_reward_ledger_read_own on public.sspace_reward_ledger for select to authenticated using(user_id=(select auth.uid()));
drop policy if exists sspace_badge_catalog_read_active on public.sspace_badge_catalog;
create policy sspace_badge_catalog_read_active on public.sspace_badge_catalog for select to authenticated using(active=true);
drop policy if exists sspace_user_badges_read_own on public.sspace_user_badges;
create policy sspace_user_badges_read_own on public.sspace_user_badges for select to authenticated using(user_id=(select auth.uid()));
drop policy if exists sspace_music_plays_read_own on public.sspace_music_plays;
create policy sspace_music_plays_read_own on public.sspace_music_plays for select to authenticated using(user_id=(select auth.uid()));
grant select on public.sspace_music_plays to authenticated;
drop policy if exists community_music_insert on public.sspace_music_tracks;
create policy community_music_insert on public.sspace_music_tracks for insert to authenticated with check(user_id=(select auth.uid()));
drop policy if exists community_music_delete on public.sspace_music_tracks;
create policy community_music_delete on public.sspace_music_tracks for delete to authenticated using(user_id=(select auth.uid()));
insert into public.sspace_badge_catalog(code,title,description,icon,points_threshold) values
('first-steps','Premiers pas','Tu as gagné tes premiers points SSPACE.','🌱',5),
('regular','Membre actif','Tu as accumulé 25 points communautaires.','⭐',25),
('veteran','Membre fidèle','Tu as accumulé 100 points communautaires.','🏆',100),
('legend','Légende SSPACE','Tu as accumulé 250 points communautaires.','👑',250)
on conflict(code) do update set title=excluded.title,description=excluded.description,icon=excluded.icon,points_threshold=excluded.points_threshold;

create or replace function public.sspace_my_dashboard_stats()
returns jsonb language plpgsql stable security definer set search_path=''
as $function$
declare me uuid := (select auth.uid());
begin
 if me is null then raise exception 'Connexion requise'; end if;
 return jsonb_build_object(
 'posts',(select count(*)::int from public.posts p where p.user_id=me),
 'followers',(select count(*)::int from public.follows f where f.following_id=me),
 'following',(select count(*)::int from public.follows f where f.follower_id=me),
 'likes_received',(select count(*)::int from public.likes l join public.posts p on p.id=l.post_id where p.user_id=me and l.user_id<>me),
 'comments_received',(select count(*)::int from public.comments c join public.posts p on p.id=c.post_id where p.user_id=me and c.user_id<>me),
 'profile_visits',(select coalesce(sum(v.visit_count),0)::int from public.profile_visits v where v.profile_id=me),
 'measured_at',now());
end;$function$;

create or replace function public.sspace_record_music_play(p_track_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare me uuid := (select auth.uid()); inserted_count integer;
begin
 if me is null then raise exception 'Connexion requise'; end if;
 if not exists(select 1 from public.sspace_music_tracks t where t.id=p_track_id) then raise exception 'Morceau introuvable'; end if;
 insert into public.sspace_music_plays(user_id,track_id,play_date)
 values(me,p_track_id,(now() at time zone 'America/Toronto')::date) on conflict do nothing;
 get diagnostics inserted_count=row_count;
 return jsonb_build_object('recorded',inserted_count=1);
end;$function$;

create or replace function public.sspace_refresh_my_challenges()
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare me uuid := (select auth.uid()); wk date := date_trunc('week',now() at time zone 'America/Toronto')::date;
 ch record; n integer; payload jsonb;
begin
 if me is null then raise exception 'Connexion requise'; end if;
 for ch in select c.* from public.sspace_challenges c where c.active=true loop
  n:=case ch.code
   when 'comment_week' then (select count(*)::int from public.comments c where c.user_id=me and c.created_at >= (wk::timestamp at time zone 'America/Toronto') and c.created_at < ((wk+7)::timestamp at time zone 'America/Toronto'))
   when 'listen_music_week' then (select count(distinct p.track_id)::int from public.sspace_music_plays p where p.user_id=me and p.play_date>=wk and p.play_date<wk+7)
   when 'publish_blog_week' then (select count(*)::int from public.posts p where p.user_id=me and p.created_at >= (wk::timestamp at time zone 'America/Toronto') and p.created_at < ((wk+7)::timestamp at time zone 'America/Toronto'))
   else 0 end;
  insert into public.sspace_challenge_progress(challenge_id,user_id,period_start,progress_count,completed_at,updated_at)
  values(ch.id,me,wk,least(n,100000),case when n>=ch.target_count then now() else null end,now())
  on conflict(challenge_id,user_id,period_start) do update set progress_count=excluded.progress_count,
  completed_at=case when excluded.completed_at is not null then coalesce(public.sspace_challenge_progress.completed_at,excluded.completed_at) else null end,updated_at=now();
 end loop;
 select coalesce(jsonb_agg(jsonb_build_object('code',c.code,'title',c.title,'description',c.description,'target_count',c.target_count,
 'progress_count',p.progress_count,'completed',coalesce(p.progress_count,0)>=c.target_count,
 'claimed',exists(select 1 from public.sspace_reward_ledger l where l.user_id=me and l.source_key='challenge:'||c.code||':'||wk::text)
 ) order by c.title),'[]'::jsonb) into payload
 from public.sspace_challenges c left join public.sspace_challenge_progress p on p.challenge_id=c.id and p.user_id=me and p.period_start=wk where c.active=true;
 return jsonb_build_object('week_start',wk,'challenges',payload);
end;$function$;

create or replace function public.sspace_my_rewards()
returns jsonb language plpgsql stable security definer set search_path=''
as $function$
declare me uuid := (select auth.uid()); pts integer; badge_data jsonb; ledger_data jsonb;
begin
 if me is null then raise exception 'Connexion requise'; end if;
 select coalesce(sum(points),0)::int into pts from public.sspace_reward_ledger where user_id=me;
 select coalesce(jsonb_agg(jsonb_build_object('code',b.code,'title',b.title,'description',b.description,'icon',b.icon,'awarded_at',ub.awarded_at) order by ub.awarded_at desc),'[]'::jsonb)
 into badge_data from public.sspace_user_badges ub join public.sspace_badge_catalog b on b.code=ub.badge_code where ub.user_id=me;
 select coalesce(jsonb_agg(jsonb_build_object('points',l.points,'reason',l.reason,'created_at',l.created_at) order by l.created_at desc),'[]'::jsonb)
 into ledger_data from (select * from public.sspace_reward_ledger where user_id=me order by created_at desc limit 12) l;
 return jsonb_build_object('points',pts,'badges',badge_data,'recent',ledger_data);
end;$function$;

create or replace function public.sspace_claim_daily_points()
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare me uuid := (select auth.uid()); day_key text := (now() at time zone 'America/Toronto')::date::text; new_id uuid; total integer;
begin
 if me is null then raise exception 'Connexion requise'; end if;
 insert into public.sspace_reward_ledger(user_id,points,reason,source_key)
 values(me,5,'Bonus de connexion quotidien','daily:'||day_key)
 on conflict(user_id,source_key) do nothing returning id into new_id;
 if new_id is null then return jsonb_build_object('claimed',false,'message','Bonus déjà récupéré aujourd’hui.'); end if;
 select coalesce(sum(points),0)::int into total from public.sspace_reward_ledger where user_id=me;
 insert into public.sspace_user_badges(user_id,badge_code) select me,b.code from public.sspace_badge_catalog b where b.active and total>=b.points_threshold on conflict do nothing;
 return jsonb_build_object('claimed',true,'points_added',5,'total_points',total);
end;$function$;

create or replace function public.sspace_claim_challenge_reward(p_code text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare me uuid := (select auth.uid()); wk date := date_trunc('week',now() at time zone 'America/Toronto')::date;
 ch public.sspace_challenges%rowtype; prog integer; new_id uuid; total integer; source text;
begin
 if me is null then raise exception 'Connexion requise'; end if;
 select * into ch from public.sspace_challenges where code=p_code and active=true;
 if ch.id is null then raise exception 'Défi introuvable'; end if;
 perform public.sspace_refresh_my_challenges();
 select progress_count into prog from public.sspace_challenge_progress where challenge_id=ch.id and user_id=me and period_start=wk;
 if coalesce(prog,0)<ch.target_count then raise exception 'Défi pas encore terminé.'; end if;
 source:='challenge:'||ch.code||':'||wk::text;
 insert into public.sspace_reward_ledger(user_id,points,reason,source_key) values(me,20,'Défi terminé : '||ch.title,source)
 on conflict(user_id,source_key) do nothing returning id into new_id;
 if new_id is null then return jsonb_build_object('claimed',false,'message','Récompense déjà récupérée.'); end if;
 select coalesce(sum(points),0)::int into total from public.sspace_reward_ledger where user_id=me;
 insert into public.sspace_user_badges(user_id,badge_code) select me,b.code from public.sspace_badge_catalog b where b.active and total>=b.points_threshold on conflict do nothing;
 return jsonb_build_object('claimed',true,'points_added',20,'total_points',total);
end;$function$;

revoke all on function public.sspace_my_dashboard_stats() from public,anon;
revoke all on function public.sspace_record_music_play(uuid) from public,anon;
revoke all on function public.sspace_refresh_my_challenges() from public,anon;
revoke all on function public.sspace_my_rewards() from public,anon;
revoke all on function public.sspace_claim_daily_points() from public,anon;
revoke all on function public.sspace_claim_challenge_reward(text) from public,anon;
grant execute on function public.sspace_my_dashboard_stats() to authenticated;
grant execute on function public.sspace_record_music_play(uuid) to authenticated;
grant execute on function public.sspace_refresh_my_challenges() to authenticated;
grant execute on function public.sspace_my_rewards() to authenticated;
grant execute on function public.sspace_claim_daily_points() to authenticated;
grant execute on function public.sspace_claim_challenge_reward(text) to authenticated;
