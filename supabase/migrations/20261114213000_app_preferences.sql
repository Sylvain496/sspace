alter table public.profiles
  add column if not exists app_theme text not null default 'dark',
  add column if not exists app_language text not null default 'fr';

alter table public.profiles
  drop constraint if exists profiles_app_theme_check;
alter table public.profiles
  add constraint profiles_app_theme_check
  check (app_theme in ('dark', 'light'));

alter table public.profiles
  drop constraint if exists profiles_app_language_check;
alter table public.profiles
  add constraint profiles_app_language_check
  check (app_language in ('fr', 'en'));

grant select, update on public.profiles to authenticated;
