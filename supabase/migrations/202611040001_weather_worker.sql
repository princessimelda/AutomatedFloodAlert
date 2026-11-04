-- Private experimental worker records; never replace public risk_assessments.
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='floodsafe_worker') THEN
    CREATE ROLE floodsafe_worker NOLOGIN NOBYPASSRLS;
  END IF;
END $$;
GRANT floodsafe_worker TO postgres;
CREATE SCHEMA floodsafe_pipeline;
REVOKE ALL ON SCHEMA floodsafe_pipeline FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA floodsafe_pipeline TO floodsafe_worker, floodsafe_reader;

CREATE TABLE floodsafe_pipeline.model_versions (
  version text PRIMARY KEY,
  bundle_sha256 text NOT NULL CHECK (bundle_sha256 ~ '^[a-f0-9]{64}$'),
  metadata jsonb NOT NULL CHECK (metadata->>'target_kind' = 'high_rainfall_proxy'),
  registered_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE floodsafe_pipeline.worker_runs (
  id uuid PRIMARY KEY,
  model_version text NOT NULL REFERENCES floodsafe_pipeline.model_versions(version),
  scheduled_hour timestamptz NOT NULL,
  target_date date NOT NULL,
  status text NOT NULL CHECK (status IN ('running','ready','incomplete','failed','expired')),
  started_at timestamptz NOT NULL,
  finished_at timestamptz,
  valid_until timestamptz NOT NULL CHECK (valid_until > started_at),
  error_code text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (model_version, scheduled_hour)
);
CREATE INDEX worker_run_latest ON floodsafe_pipeline.worker_runs(model_version,started_at DESC,id DESC);
CREATE TABLE floodsafe_pipeline.weather_inputs (
  run_id uuid NOT NULL REFERENCES floodsafe_pipeline.worker_runs(id) ON DELETE CASCADE,
  grid_id text NOT NULL,
  day date NOT NULL,
  tavg double precision CHECK (tavg BETWEEN -90 AND 60),
  tmin double precision CHECK (tmin BETWEEN -90 AND 60),
  tmax double precision CHECK (tmax BETWEEN -90 AND 60),
  prcp double precision CHECK (prcp BETWEEN 0 AND 2000),
  wspd double precision CHECK (wspd BETWEEN 0 AND 500),
  pres double precision CHECK (pres BETWEEN 800 AND 1100),
  PRIMARY KEY(run_id,grid_id,day)
);
CREATE TABLE floodsafe_pipeline.source_responses (
  run_id uuid NOT NULL REFERENCES floodsafe_pipeline.worker_runs(id) ON DELETE CASCADE,
  request_index integer NOT NULL CHECK (request_index >= 0),
  receipt jsonb NOT NULL,
  body_sha256 text NOT NULL CHECK (body_sha256 ~ '^[a-f0-9]{64}$'),
  body bytea NOT NULL,
  PRIMARY KEY(run_id,request_index)
);
CREATE TABLE floodsafe_pipeline.rainfall_predictions (
  run_id uuid NOT NULL REFERENCES floodsafe_pipeline.worker_runs(id) ON DELETE CASCADE,
  grid_id text NOT NULL,
  target_date date NOT NULL,
  score double precision NOT NULL CHECK (score >= 0 AND score <= 1),
  predicted_high_rainfall boolean NOT NULL,
  rain_threshold_mm double precision NOT NULL CHECK (rain_threshold_mm > 0 AND rain_threshold_mm < 'Infinity'::float8),
  features jsonb NOT NULL CHECK (jsonb_typeof(features)='object'),
  feature_sha256 text NOT NULL CHECK (feature_sha256 ~ '^[a-f0-9]{64}$'),
  generated_at timestamptz NOT NULL,
  valid_until timestamptz NOT NULL CHECK (valid_until > generated_at),
  experimental boolean NOT NULL DEFAULT true CHECK (experimental),
  PRIMARY KEY(run_id,grid_id)
);

ALTER TABLE floodsafe_pipeline.model_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE floodsafe_pipeline.worker_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE floodsafe_pipeline.weather_inputs ENABLE ROW LEVEL SECURITY;
ALTER TABLE floodsafe_pipeline.source_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE floodsafe_pipeline.rainfall_predictions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA floodsafe_pipeline FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT ON floodsafe_pipeline.model_versions TO floodsafe_worker;
GRANT SELECT,INSERT,UPDATE ON floodsafe_pipeline.worker_runs,
  floodsafe_pipeline.weather_inputs,floodsafe_pipeline.source_responses,
  floodsafe_pipeline.rainfall_predictions TO floodsafe_worker;
CREATE POLICY worker_models ON floodsafe_pipeline.model_versions TO floodsafe_worker USING(true) WITH CHECK(true);
CREATE POLICY worker_runs ON floodsafe_pipeline.worker_runs TO floodsafe_worker USING(true) WITH CHECK(true);
CREATE POLICY worker_weather ON floodsafe_pipeline.weather_inputs TO floodsafe_worker USING(true) WITH CHECK(true);
CREATE POLICY worker_sources ON floodsafe_pipeline.source_responses TO floodsafe_worker USING(true) WITH CHECK(true);
CREATE POLICY worker_predictions ON floodsafe_pipeline.rainfall_predictions TO floodsafe_worker USING(true) WITH CHECK(true);

-- Owner-backed, bounded views deliberately expose only operational status and
-- still-valid experimental scores to the backend reader, never raw source data.
CREATE VIEW floodsafe_pipeline.latest_status WITH (security_barrier=true) AS
SELECT DISTINCT ON(model_version) id AS run_id,model_version,target_date,started_at,finished_at,valid_until,
 CASE
   WHEN now() >= valid_until THEN 'stale'
   WHEN status='running' AND now()-started_at > interval '15 minutes' THEN 'failed'
   ELSE status
 END AS status,
 error_code
FROM floodsafe_pipeline.worker_runs
ORDER BY model_version,started_at DESC,id DESC;
CREATE VIEW floodsafe_pipeline.current_predictions WITH (security_barrier=true) AS
SELECT p.*,s.model_version FROM floodsafe_pipeline.rainfall_predictions p
JOIN floodsafe_pipeline.latest_status s ON s.run_id=p.run_id
WHERE s.status='ready' AND p.valid_until>now()
 AND p.target_date=(now() AT TIME ZONE 'UTC')::date;
REVOKE ALL ON floodsafe_pipeline.latest_status,floodsafe_pipeline.current_predictions FROM PUBLIC,anon,authenticated;
GRANT SELECT ON floodsafe_pipeline.latest_status,floodsafe_pipeline.current_predictions TO floodsafe_reader;
