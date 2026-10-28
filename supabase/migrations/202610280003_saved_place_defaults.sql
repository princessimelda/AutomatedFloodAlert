-- Save supported catalogue places without collecting precise GPS positions.
ALTER TABLE public.saved_places ALTER COLUMN position DROP NOT NULL;
ALTER TABLE public.saved_places ADD COLUMN place_id text REFERENCES public.places(id) ON DELETE CASCADE;
ALTER TABLE public.saved_places ADD COLUMN is_default boolean NOT NULL DEFAULT false;
ALTER TABLE public.saved_places ADD CONSTRAINT saved_place_has_location CHECK (place_id IS NOT NULL OR position IS NOT NULL);
CREATE UNIQUE INDEX saved_catalogue_place ON public.saved_places(user_id,place_id);
CREATE UNIQUE INDEX one_default_place ON public.saved_places(user_id) WHERE is_default;
GRANT SELECT ON public.places TO authenticated;
CREATE POLICY authenticated_published_places ON public.places FOR SELECT TO authenticated USING (is_published);

-- Invoker security retains owner RLS. A per-user lock serialises default changes.
CREATE FUNCTION public.set_default_place(target_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(auth.uid()::text,0));
  IF NOT EXISTS (SELECT 1 FROM public.saved_places WHERE id=target_id AND user_id=auth.uid()) THEN
    RAISE EXCEPTION 'Saved place unavailable';
  END IF;
  UPDATE public.saved_places SET is_default=false WHERE user_id=auth.uid() AND is_default;
  UPDATE public.saved_places SET is_default=true WHERE id=target_id AND user_id=auth.uid();
END;
$$;
REVOKE ALL ON FUNCTION public.set_default_place(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_default_place(uuid) TO authenticated;
