-- Destructive: removes only this increment's application tables and their data.
-- Does not delete auth.users, PostGIS, the reader role, or unrelated tables.
DROP TABLE public.advisories, public.rainfall_telemetry, public.risk_assessments,
  public.susceptibility_grid, public.devices, public.user_location_telemetry,
  public.saved_places, public.profiles, public.places;
