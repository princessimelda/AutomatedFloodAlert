-- Public information and owner-private records. No SMS or model inference runs.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA extensions;
DO $$ BEGIN
  IF (SELECT extnamespace::regnamespace::text FROM pg_extension WHERE extname = 'postgis') <> 'extensions' THEN
    RAISE EXCEPTION 'PostGIS must be installed in extensions; review existing extension before migrating';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'floodsafe_reader') THEN
    CREATE ROLE floodsafe_reader NOLOGIN NOSUPERUSER NOBYPASSRLS;
  END IF;
  EXECUTE format('GRANT floodsafe_reader TO %I', current_user);
END $$;

CREATE TABLE public.places (
  id text PRIMARY KEY CHECK (id ~ '^[a-z0-9][a-z0-9-]{0,63}$'),
  name text NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 120),
  is_demo boolean NOT NULL DEFAULT false,
  is_published boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  language text NOT NULL DEFAULT 'en' CHECK (language IN ('en', 'sw')),
  push_enabled boolean NOT NULL DEFAULT false,
  sms_enabled boolean NOT NULL DEFAULT false,
  location_consent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.saved_places (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  label text NOT NULL CHECK (length(trim(label)) BETWEEN 1 AND 120),
  position extensions.geography(Point,4326) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.user_location_telemetry (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  position extensions.geography(Point,4326) NOT NULL,
  accuracy_m double precision NOT NULL CHECK (accuracy_m >= 0 AND accuracy_m < 'Infinity'::float8),
  recorded_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  push_token text NOT NULL UNIQUE CHECK (length(push_token) BETWEEN 1 AND 4096),
  platform text NOT NULL CHECK (platform IN ('android','web','ios')),
  enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.susceptibility_grid (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  boundary extensions.geometry(MultiPolygon,4326) NOT NULL,
  source text NOT NULL CHECK (length(trim(source)) > 0),
  is_demo boolean NOT NULL DEFAULT false,
  is_published boolean NOT NULL DEFAULT false,
  CHECK (extensions.ST_IsValid(boundary) AND NOT extensions.ST_IsEmpty(boundary))
);
CREATE TABLE public.risk_assessments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  place_id text REFERENCES public.places(id),
  zone_id uuid REFERENCES public.susceptibility_grid(id),
  level text NOT NULL CHECK (level IN ('low','moderate','high')),
  source text NOT NULL CHECK (length(trim(source)) > 0),
  model_version text,
  issued_at timestamptz NOT NULL,
  valid_until timestamptz NOT NULL,
  is_demo boolean NOT NULL DEFAULT false,
  is_published boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (place_id IS NOT NULL OR zone_id IS NOT NULL),
  CHECK (valid_until > issued_at)
);
CREATE TABLE public.rainfall_telemetry (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  position extensions.geography(Point,4326) NOT NULL,
  precipitation_mm double precision NOT NULL CHECK (precipitation_mm >= 0 AND precipitation_mm < 'Infinity'::float8),
  valid_at timestamptz NOT NULL,
  retrieved_at timestamptz NOT NULL DEFAULT now(),
  kind text NOT NULL CHECK (kind IN ('forecast','observation','reanalysis')),
  source text NOT NULL,
  source_record_id text NOT NULL,
  UNIQUE (source, source_record_id)
);
CREATE TABLE public.advisories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  place_id text REFERENCES public.places(id),
  language text NOT NULL CHECK (language IN ('en','sw')),
  title text NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 200),
  body text NOT NULL CHECK (length(trim(body)) BETWEEN 1 AND 10000),
  source text NOT NULL,
  source_url text NOT NULL CHECK (source_url LIKE 'https://%'),
  published_at timestamptz NOT NULL,
  valid_until timestamptz NOT NULL CHECK (valid_until > published_at),
  is_demo boolean NOT NULL DEFAULT false,
  is_published boolean NOT NULL DEFAULT false
);

CREATE INDEX saved_places_user_idx ON public.saved_places(user_id);
CREATE INDEX location_user_time_idx ON public.user_location_telemetry(user_id, recorded_at DESC);
CREATE INDEX location_position_idx ON public.user_location_telemetry USING gist(position);
CREATE INDEX devices_user_idx ON public.devices(user_id);
CREATE INDEX grid_boundary_idx ON public.susceptibility_grid USING gist(boundary);
CREATE INDEX risk_place_time_idx ON public.risk_assessments(place_id, issued_at DESC) WHERE is_published;
CREATE INDEX risk_zone_time_idx ON public.risk_assessments(zone_id, issued_at DESC) WHERE is_published;
CREATE INDEX rainfall_position_idx ON public.rainfall_telemetry USING gist(position);
CREATE INDEX rainfall_time_idx ON public.rainfall_telemetry(valid_at DESC);
CREATE INDEX advisory_place_language_time_idx ON public.advisories(place_id, language, published_at DESC) WHERE is_published;

ALTER TABLE public.places ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saved_places ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_location_telemetry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.susceptibility_grid ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.risk_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rainfall_telemetry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.advisories ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.places, public.profiles, public.saved_places,
  public.user_location_telemetry, public.devices, public.susceptibility_grid,
  public.risk_assessments, public.rainfall_telemetry, public.advisories
  FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA public, extensions TO floodsafe_reader;
GRANT SELECT ON public.places, public.susceptibility_grid,
  public.risk_assessments, public.advisories TO floodsafe_reader;
CREATE POLICY published_places ON public.places FOR SELECT TO floodsafe_reader USING (is_published);
CREATE POLICY published_grid ON public.susceptibility_grid FOR SELECT TO floodsafe_reader USING (is_published);
CREATE POLICY published_risk ON public.risk_assessments FOR SELECT TO floodsafe_reader USING (is_published);
CREATE POLICY published_advisories ON public.advisories FOR SELECT TO floodsafe_reader USING (is_published);

-- Authenticated clients can manage their own profile/saved places, never
-- telemetry, risk, publication or provider-delivery records.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles, public.saved_places TO authenticated;
CREATE POLICY own_profile ON public.profiles TO authenticated
  USING ((SELECT auth.uid()) = user_id) WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY own_saved_places ON public.saved_places TO authenticated
  USING ((SELECT auth.uid()) = user_id) WITH CHECK ((SELECT auth.uid()) = user_id);
-- Device and telemetry ingestion will be authenticated server workflows in a
-- later migration. No direct client permissions are granted to those tables.
