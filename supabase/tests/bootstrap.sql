-- Test container only. Hosted Supabase already provides auth.users/auth.uid().
CREATE DATABASE floodsafe_test TEMPLATE template0;
\connect floodsafe_test
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;
CREATE SCHEMA auth;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
GRANT USAGE ON SCHEMA auth TO authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated;
CREATE SCHEMA floodsafe_test_marker;
CREATE TABLE floodsafe_test_marker.identity(marker text PRIMARY KEY);
INSERT INTO floodsafe_test_marker.identity VALUES ('isolated-floodsafe-tests');
