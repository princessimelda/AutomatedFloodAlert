-- Student prototype: test alerts only; no operational thresholds or public emergency claims.
DO $$ BEGIN
 IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='floodsafe_alert_service') THEN
  CREATE ROLE floodsafe_alert_service NOLOGIN NOBYPASSRLS;
 END IF;
END $$;
GRANT floodsafe_alert_service TO postgres;
CREATE SCHEMA floodsafe_alerting;
REVOKE ALL ON SCHEMA floodsafe_alerting FROM PUBLIC,anon,authenticated;
GRANT USAGE ON SCHEMA floodsafe_alerting TO floodsafe_alert_service,floodsafe_reader;
GRANT USAGE ON SCHEMA public TO floodsafe_alert_service;
GRANT SELECT ON public.places TO floodsafe_alert_service;
CREATE POLICY alert_service_places ON public.places FOR SELECT TO floodsafe_alert_service USING(is_published);

CREATE TABLE floodsafe_alerting.alert_rules (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 name text NOT NULL CHECK(length(name) BETWEEN 1 AND 120),
 version integer NOT NULL CHECK(version>0),
 event_kind text NOT NULL CHECK(event_kind IN ('rainfall_proxy','manual_report')),
 threshold double precision NOT NULL CHECK(threshold>=0 AND threshold<'Infinity'::float8),
 severity text NOT NULL CHECK(severity IN ('information','advisory','warning','critical')),
 approved_by text NOT NULL,
 approved_at timestamptz NOT NULL DEFAULT now(),
 is_demo boolean NOT NULL DEFAULT true CHECK(is_demo),
 UNIQUE(name,version),
 CHECK(event_kind<>'rainfall_proxy' OR severity='information')
);
CREATE TABLE floodsafe_alerting.alert_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 source text NOT NULL,
 source_event_id text NOT NULL,
 payload_sha256 text NOT NULL CHECK(payload_sha256~'^[a-f0-9]{64}$'),
 event_kind text NOT NULL CHECK(event_kind IN ('rainfall_proxy','manual_report')),
 metric double precision NOT NULL CHECK(metric>=0 AND metric<'Infinity'::float8),
 occurred_at timestamptz NOT NULL,
 valid_until timestamptz NOT NULL CHECK(valid_until>occurred_at),
 evidence text NOT NULL,
 received_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(source,source_event_id)
);
CREATE TABLE floodsafe_alerting.alerts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 event_id uuid NOT NULL UNIQUE REFERENCES floodsafe_alerting.alert_events(id),
 rule_id uuid NOT NULL REFERENCES floodsafe_alerting.alert_rules(id),
 title text NOT NULL CHECK(length(title) BETWEEN 1 AND 160),
 message text NOT NULL CHECK(length(message) BETWEEN 1 AND 1000),
 recommended_action text NOT NULL CHECK(length(recommended_action) BETWEEN 1 AND 300),
 severity text NOT NULL CHECK(severity IN ('information','advisory','warning','critical')),
 status text NOT NULL CHECK(status IN ('pending_approval','approved','published','resolved','cancelled')),
 revision integer NOT NULL DEFAULT 1 CHECK(revision>0),
 created_by text NOT NULL,
 approved_by text,
 approved_at timestamptz,
 issued_at timestamptz,
 valid_until timestamptz NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 is_demo boolean NOT NULL DEFAULT true CHECK(is_demo),
 CHECK(approved_by IS NULL OR approved_by<>created_by)
);
CREATE TABLE floodsafe_alerting.alert_locations (
 alert_id uuid NOT NULL REFERENCES floodsafe_alerting.alerts(id) ON DELETE CASCADE,
 place_id text NOT NULL REFERENCES public.places(id),
 PRIMARY KEY(alert_id,place_id)
);
CREATE TABLE floodsafe_alerting.alert_audit_logs (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 alert_id uuid NOT NULL REFERENCES floodsafe_alerting.alerts(id),
 actor_id text NOT NULL,
 action text NOT NULL,
 revision integer NOT NULL,
 reason text NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE floodsafe_alerting.notification_jobs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 alert_id uuid NOT NULL REFERENCES floodsafe_alerting.alerts(id),
 revision integer NOT NULL,
 channel text NOT NULL CHECK(channel IN ('in_app','sms')),
 recipient_key text NOT NULL,
 destination text,
 status text NOT NULL CHECK(status IN ('available','queued','processing','retry','accepted','delivered','failed','unknown','cancelled')),
 attempt_count integer NOT NULL DEFAULT 0 CHECK(attempt_count BETWEEN 0 AND 3),
 next_attempt_at timestamptz NOT NULL DEFAULT now(),
 provider_id text UNIQUE,
 error_code text,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(alert_id,revision,channel,recipient_key)
);
CREATE TABLE floodsafe_alerting.notification_attempts (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 job_id uuid NOT NULL REFERENCES floodsafe_alerting.notification_jobs(id),
 attempt integer NOT NULL,
 outcome text NOT NULL,
 provider_id text,
 error_code text,
 started_at timestamptz NOT NULL DEFAULT now(),
 finished_at timestamptz,
 UNIQUE(job_id,attempt)
);
CREATE TABLE floodsafe_alerting.alert_acknowledgements (
 alert_id uuid NOT NULL REFERENCES floodsafe_alerting.alerts(id),
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 acknowledged_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(alert_id,user_id)
);
CREATE INDEX alert_status_time ON floodsafe_alerting.alerts(status,valid_until);
CREATE INDEX alert_place_lookup ON floodsafe_alerting.alert_locations(place_id,alert_id);
CREATE INDEX notification_queue ON floodsafe_alerting.notification_jobs(next_attempt_at) WHERE status IN ('queued','retry');
CREATE INDEX notification_alert ON floodsafe_alerting.notification_jobs(alert_id);
CREATE INDEX audit_alert ON floodsafe_alerting.alert_audit_logs(alert_id,recorded_at);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['alert_rules','alert_events','alerts','alert_locations','alert_audit_logs','notification_jobs','notification_attempts','alert_acknowledgements'] LOOP
  EXECUTE format('ALTER TABLE floodsafe_alerting.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON floodsafe_alerting.%I FROM PUBLIC,anon,authenticated',t);
  EXECUTE format('CREATE POLICY service_access ON floodsafe_alerting.%I TO floodsafe_alert_service USING(true) WITH CHECK(true)',t);
 END LOOP;
END $$;
GRANT SELECT,INSERT ON ALL TABLES IN SCHEMA floodsafe_alerting TO floodsafe_alert_service;
GRANT UPDATE ON floodsafe_alerting.alerts,floodsafe_alerting.notification_jobs,floodsafe_alerting.notification_attempts TO floodsafe_alert_service;
GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA floodsafe_alerting TO floodsafe_alert_service;
CREATE VIEW floodsafe_alerting.published_alerts WITH (security_barrier=true) AS
 SELECT a.id,a.title,a.message,a.recommended_action,a.severity,a.revision,a.issued_at,a.valid_until,a.is_demo,
 coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.id,'name',p.name) ORDER BY p.name)
 FROM floodsafe_alerting.alert_locations l JOIN public.places p ON p.id=l.place_id
 WHERE l.alert_id=a.id AND p.is_published),'[]'::jsonb) AS locations
 FROM floodsafe_alerting.alerts a
 WHERE a.status='published' AND a.issued_at<=now() AND a.valid_until>now()
 AND EXISTS(SELECT FROM floodsafe_alerting.alert_locations l JOIN public.places p ON p.id=l.place_id WHERE l.alert_id=a.id AND p.is_published)
 AND EXISTS(SELECT FROM floodsafe_alerting.notification_jobs j WHERE j.alert_id=a.id AND j.channel='in_app' AND j.status='available');
REVOKE ALL ON floodsafe_alerting.published_alerts FROM PUBLIC,anon,authenticated;
GRANT SELECT ON floodsafe_alerting.published_alerts TO floodsafe_reader;
