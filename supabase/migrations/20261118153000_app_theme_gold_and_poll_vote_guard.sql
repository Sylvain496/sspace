-- Allow the optional Gold application appearance without changing the default theme.
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_app_theme_check;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_app_theme_check
  CHECK (app_theme = ANY (ARRAY['dark'::text, 'light'::text, 'gold'::text]));

-- A poll vote must select an option belonging to the same poll.
DROP POLICY IF EXISTS "Members vote once on visible polls" ON public.post_poll_votes;

CREATE POLICY "Members vote once on visible polls"
ON public.post_poll_votes
FOR INSERT
TO authenticated
WITH CHECK (
  user_id = (SELECT auth.uid())
  AND EXISTS (
    SELECT 1
    FROM public.posts p
    WHERE p.id = post_poll_votes.post_id
      AND p.poll_question IS NOT NULL
  )
  AND EXISTS (
    SELECT 1
    FROM public.post_poll_options o
    WHERE o.id = post_poll_votes.option_id
      AND o.post_id = post_poll_votes.post_id
  )
);
