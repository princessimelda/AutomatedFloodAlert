-- Run before rolling back the core migration. Remove catalogue saves first.
DROP FUNCTION IF EXISTS public.set_default_place(uuid);
DROP POLICY IF EXISTS authenticated_published_places ON public.places;
REVOKE SELECT ON public.places FROM authenticated;
DELETE FROM public.saved_places WHERE position IS NULL;
ALTER TABLE public.saved_places DROP COLUMN place_id;
ALTER TABLE public.saved_places DROP COLUMN is_default;
ALTER TABLE public.saved_places ALTER COLUMN position SET NOT NULL;
