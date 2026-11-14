alter table public.profiles
  add column if not exists profile_theme text not null default 'theme-aurora';

alter table public.profiles
  drop constraint if exists profiles_profile_theme_check;

alter table public.profiles
  add constraint profiles_profile_theme_check
  check (profile_theme in (
    'theme-aurora', 'theme-ocean', 'theme-violet', 'theme-forest',
    'theme-sunset', 'theme-ice', 'theme-rose', 'theme-neon',
    'theme-midnight', 'theme-gold'
  ));
