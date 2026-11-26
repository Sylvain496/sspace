-- SSPACE no longer offers a light/dark application theme selector.
-- Remove the obsolete per-profile application theme preference.
alter table public.profiles drop column if exists app_theme;
