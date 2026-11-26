-- Remove redundant indexes while preserving the constraint-backed and canonical indexes.
drop index if exists public.memory_suggestions_one_per_week;
drop index if exists public.sspace_profile_one_pending_verification;
