-- Development only. Run explicitly; never loaded on API startup.
-- Re-running this file does not renew expired scenario dates.
INSERT INTO public.places(id,name,is_demo,is_published) VALUES
  ('kibera','Kibera',true,true), ('westlands','Westlands',true,true),
  ('embakasi','Embakasi',true,true), ('kasarani','Kasarani',true,true)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.risk_assessments
  (id,place_id,level,source,issued_at,valid_until,is_demo,is_published) VALUES
  ('00000000-0000-4000-8000-000000000001','kibera','high','FloodSafe development seed; not current conditions',now()-interval '1 hour',now()+interval '1 hour',true,true),
  ('00000000-0000-4000-8000-000000000002','kasarani','low','FloodSafe development seed; not current conditions',now()-interval '1 hour',now()+interval '1 hour',true,true),
  ('00000000-0000-4000-8000-000000000003','embakasi','high','FloodSafe development seed; not current conditions',now()-interval '4 hours',now()-interval '2 hours',true,true)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.advisories
  (id,language,title,body,source,source_url,published_at,valid_until,is_demo,is_published) VALUES
  ('00000000-0000-4000-8000-000000000010','en','Preparedness practice',
   'Practise finding your household preparedness plan and checking official local updates. This is a test advisory, not an evacuation instruction.',
   'FloodSafe development example; general preparedness adapted from CDC',
   'https://www.cdc.gov/floods/safety/',now()-interval '1 hour',now()+interval '7 days',true,true)
ON CONFLICT (id) DO NOTHING;
