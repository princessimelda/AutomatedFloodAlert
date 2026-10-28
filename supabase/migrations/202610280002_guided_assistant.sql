-- A finite, database-backed question catalogue. No arbitrary text or AI calls.
CREATE TABLE public.assistant_answers (
  id text NOT NULL CHECK (id ~ '^[a-z0-9][a-z0-9-]{0,63}$'),
  language text NOT NULL CHECK (language IN ('en','sw')),
  category text NOT NULL CHECK (length(trim(category)) BETWEEN 1 AND 80),
  question text NOT NULL CHECK (length(trim(question)) BETWEEN 1 AND 240),
  answer text NOT NULL CHECK (length(trim(answer)) BETWEEN 1 AND 6000),
  source text NOT NULL,
  source_url text NOT NULL CHECK (source_url LIKE 'https://%'),
  reviewed_at timestamptz NOT NULL,
  valid_until timestamptz NOT NULL CHECK (valid_until > reviewed_at),
  is_published boolean NOT NULL DEFAULT false,
  sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  PRIMARY KEY (id,language)
);
ALTER TABLE public.assistant_answers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.assistant_answers FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.assistant_answers TO floodsafe_reader;
CREATE POLICY current_published_answers ON public.assistant_answers
  FOR SELECT TO floodsafe_reader
  USING (is_published AND reviewed_at <= now() AND valid_until > now());
CREATE INDEX assistant_catalogue_idx ON public.assistant_answers(language,sort_order,id) WHERE is_published;

-- Implementation-checked app help only. Medical/emergency guidance and
-- Kiswahili content require their own source/local review before publication.
INSERT INTO public.assistant_answers
(id,language,category,question,answer,source,source_url,reviewed_at,valid_until,is_published,sort_order)
VALUES
('live-data','en','Understanding FloodSafe','Is the flood information live?',
 'The database connection is real, but the current seeded risk scenarios are test data, not current flood predictions. Check the source, test-data label, issue time and expiry on Home. Missing or expired information does not mean that an area is at low risk.',
 'FloodSafe implementation notes','https://github.com/princessimelda/AutomatedFloodAlert/blob/main/README.md',now(),now()+interval '90 days',true,1),
('choose-place','en','Using the app','How do I choose my location?',
 'On Home, select Choose a place or Change place, then select an available neighbourhood. You can also choose Use my location for a one-time foreground check. If location permission is denied, manual selection and general preparedness guidance remain available.',
 'FloodSafe core-flow implementation','https://github.com/princessimelda/AutomatedFloodAlert/tree/main/floodsafe',now(),now()+interval '90 days',true,2),
('missing-risk','en','Understanding FloodSafe','Why is risk information unavailable?',
 'There may be no published assessment for that place, the information may have expired, or the service may be unavailable. Check the message on Home and try refreshing. Do not interpret unavailable information as low risk. This assistant cannot confirm current local flood conditions.',
 'FloodSafe assessment validity rules','https://github.com/princessimelda/AutomatedFloodAlert/tree/main/backend',now(),now()+interval '90 days',true,3),
('preparedness','en','Using the app','Where can I find preparedness steps?',
 'On Home, select Read preparedness steps. General educational guidance is available without signing in or enabling GPS. Published advisories, when available, show their source and validity. General guidance is not a location-specific evacuation instruction.',
 'FloodSafe preparedness screen','https://github.com/princessimelda/AutomatedFloodAlert/tree/main/floodsafe',now(),now()+interval '90 days',true,4),
('routes','en','App limitations','Can FloodSafe show me a safe evacuation route?',
 'Not yet. The map is an illustration and does not provide verified routes or evacuation destinations. Do not use it for navigation. This guided assistant does not calculate routes or generate evacuation instructions.',
 'FloodSafe routing implementation status','https://github.com/princessimelda/AutomatedFloodAlert/tree/main/floodsafe',now(),now()+interval '90 days',true,5);
