"""Never targets Supabase: fixed loopback port, database and test marker."""

import os
from datetime import datetime, timezone
from pathlib import Path

import psycopg
import pytest
from psycopg.rows import dict_row

from app.config import Settings
from app.manage import migrate, seed
from app.models import DashboardRequest
from app.repositories import PostgresRepository

pytestmark = pytest.mark.database
ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture(scope="module")
def database_settings():
    if os.getenv("FLOODSAFE_RUN_DB_TESTS") != "1":
        pytest.skip("Start the isolated PostGIS container and set FLOODSAFE_RUN_DB_TESTS=1.")
    settings = Settings(
        _env_file=None,
        db_host="127.0.0.1",
        db_port=55432,
        db_name="floodsafe_test",
        db_user="postgres",
        db_password="floodsafe-test-only",
        db_sslmode="disable",
        allow_demo_data=True,
    )
    with psycopg.connect(**settings.connection_kwargs(), row_factory=dict_row) as connection:
        assert (
            connection.execute("SELECT marker FROM floodsafe_test_marker.identity").fetchone()[
                "marker"
            ]
            == "isolated-floodsafe-tests"
        )
        migrate(connection)
        seed(connection)
    return settings


@pytest.fixture
def db(database_settings):
    connection = psycopg.connect(**database_settings.connection_kwargs(), row_factory=dict_row)
    try:
        yield connection
    finally:
        connection.rollback()
        connection.close()


def test_rls_and_grants_cover_every_application_table(db):
    tables = db.execute("""SELECT c.relname,c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='public' AND c.relkind='r' AND c.relname IN
        ('places','profiles','saved_places','user_location_telemetry','devices','susceptibility_grid','risk_assessments','rainfall_telemetry','advisories')""").fetchall()
    assert len(tables) == 9
    assert all(table["relrowsecurity"] for table in tables)
    assert not db.execute(
        "SELECT rolbypassrls FROM pg_roles WHERE rolname='floodsafe_reader'"
    ).fetchone()["rolbypassrls"]
    assert not db.execute(
        "SELECT has_table_privilege('anon','public.profiles','SELECT') AS allowed"
    ).fetchone()["allowed"]
    assert not db.execute(
        "SELECT has_table_privilege('floodsafe_reader','public.user_location_telemetry','SELECT') AS allowed"
    ).fetchone()["allowed"]


def test_users_cannot_read_or_create_another_users_profile(db):
    a = "10000000-0000-4000-8000-000000000001"
    b = "10000000-0000-4000-8000-000000000002"
    db.execute("INSERT INTO auth.users(id) VALUES (%s),(%s)", (a, b))
    db.execute("INSERT INTO public.profiles(user_id) VALUES (%s),(%s)", (a, b))
    db.execute("SET LOCAL ROLE authenticated")
    db.execute("SELECT set_config('request.jwt.claim.sub',%s,true)", (a,))
    assert [str(row["user_id"]) for row in db.execute("SELECT user_id FROM public.profiles")] == [a]
    assert (
        db.execute("UPDATE public.profiles SET sms_enabled=true WHERE user_id=%s", (b,)).rowcount
        == 0
    )
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        with db.transaction():
            db.execute("UPDATE public.profiles SET user_id=%s WHERE user_id=%s", (b, a))


def test_constraints_reject_invalid_validity(db):
    with pytest.raises(psycopg.errors.CheckViolation):
        with db.transaction():
            db.execute("""INSERT INTO public.risk_assessments(place_id,level,source,issued_at,valid_until)
                VALUES ('kibera','high','Test',now(),now()-interval '1 hour')""")


def test_reader_sees_only_published_rows_and_cannot_write(db):
    db.execute("INSERT INTO public.places(id,name) VALUES ('draft-place','Not published')")
    db.execute("SET LOCAL ROLE floodsafe_reader")
    assert db.execute("SELECT id FROM public.places WHERE id='draft-place'").fetchone() is None
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        with db.transaction():
            db.execute("INSERT INTO public.places(id,name) VALUES ('blocked','No')")


def test_migration_and_seed_are_repeatable_without_renewing_dates(db):
    before = db.execute("SELECT id,valid_until FROM public.risk_assessments ORDER BY id").fetchall()
    assert migrate(db) == []
    seed(db)
    assert (
        db.execute("SELECT id,valid_until FROM public.risk_assessments ORDER BY id").fetchall()
        == before
    )


def test_real_repository_connects_with_reader_role(database_settings):
    repository = PostgresRepository(database_settings)
    try:
        repository.ping()
        assert len(repository.places()) == 4
        assert repository.dashboard(DashboardRequest(place_id="westlands")).assessment is None
        assert (
            repository.dashboard(DashboardRequest(place_id="embakasi")).assessment.current(
                datetime.now(timezone.utc)
            )
            is False
        )
        assert repository.advisories("kibera", "en", 20)[0].is_demo
    finally:
        repository.close()


def test_boundary_matching_and_demo_polygon_exclusion(database_settings):
    # Invented test geometry, never real flood evidence. Inserted only in the
    # marker-protected local test database; removed in finally.
    ids = [
        "20000000-0000-4000-8000-000000000001",
        "20000000-0000-4000-8000-000000000002",
    ]
    kwargs = database_settings.connection_kwargs()
    repository = PostgresRepository(database_settings)
    try:
        with psycopg.connect(**kwargs) as connection:
            for id, demo in zip(ids, [False, True]):
                connection.execute(
                    """INSERT INTO public.susceptibility_grid(id,name,boundary,source,is_demo,is_published)
                    VALUES (%s,'Test polygon',extensions.ST_Multi(extensions.ST_GeomFromText('POLYGON((36 -2,37 -2,37 -1,36 -1,36 -2))',4326)),'Synthetic test',%s,true)""",
                    (id, demo),
                )
                connection.execute(
                    """INSERT INTO public.risk_assessments(id,zone_id,level,source,issued_at,valid_until,is_demo,is_published)
                    VALUES (%s,%s,%s,'Synthetic test',now()-interval '1 hour',now()+interval '1 hour',%s,true)""",
                    (id, id, "high" if demo else "moderate", demo),
                )
        boundary = repository.dashboard(
            DashboardRequest(place_id="gps:test", latitude=-1, longitude=36)
        )
        assert (
            boundary.assessment.level == "moderate"
        )  # ST_Covers includes boundary; demo high excluded
        outside = repository.dashboard(
            DashboardRequest(place_id="gps:test", latitude=0, longitude=0)
        )
        assert outside.assessment is None
        with psycopg.connect(**kwargs) as connection:
            connection.execute(
                "UPDATE public.risk_assessments SET issued_at=now()-interval '4 hours',valid_until=now()-interval '1 hour' WHERE id=%s",
                (ids[0],),
            )
        expired = repository.dashboard(
            DashboardRequest(place_id="gps:test", latitude=-1.5, longitude=36.5)
        )
        assert expired.assessment is not None
        assert not expired.assessment.current(datetime.now(timezone.utc))
    finally:
        repository.close()
        with psycopg.connect(**kwargs) as connection:
            connection.execute(
                "DELETE FROM public.risk_assessments WHERE id=ANY(%s::uuid[])", (ids,)
            )
            connection.execute(
                "DELETE FROM public.susceptibility_grid WHERE id=ANY(%s::uuid[])",
                (ids,),
            )


def test_rollback_and_reapply_in_isolated_database(database_settings):
    # Run last; this container contains only disposable application data.
    with psycopg.connect(
        **database_settings.connection_kwargs(), row_factory=dict_row
    ) as connection:
        connection.execute(
            (ROOT / "supabase/rollbacks/202610280003_saved_place_defaults.sql").read_text(),
            prepare=False,
        )
        connection.execute(
            (ROOT / "supabase/rollbacks/202610280001_core.sql").read_text(),
            prepare=False,
        )
        connection.execute(
            "DELETE FROM floodsafe_internal.schema_migrations WHERE version IN ('202610280001_core','202610280003_saved_place_defaults')"
        )
        assert migrate(connection) == ["202610280001_core", "202610280003_saved_place_defaults"]
        seed(connection)


def test_guided_assistant_only_reads_current_published_answers(database_settings, db):
    from app.repositories import AnswerUnavailable

    repository = PostgresRepository(database_settings)
    try:
        questions = repository.assistant_questions("en")
        assert len(questions) == 5
        assert repository.assistant_answer("live-data", "en").answer
        assert repository.assistant_questions("sw") == []
        with pytest.raises(AnswerUnavailable):
            repository.assistant_answer("not-approved", "en")
        db.execute("""INSERT INTO public.assistant_answers
            (id,language,category,question,answer,source,source_url,reviewed_at,valid_until,is_published)
            VALUES ('draft-test','en','Test','Hidden?','Must not show','Test','https://example.com',now(),now()+interval '1 day',false),
            ('expired-test','en','Test','Expired?','Must not show','Test','https://example.com',now()-interval '2 days',now()-interval '1 day',true),
            ('future-test','en','Test','Future?','Must not show','Test','https://example.com',now()+interval '1 day',now()+interval '2 days',true)""")
        db.execute("SET LOCAL ROLE floodsafe_reader")
        assert (
            db.execute(
                "SELECT id FROM public.assistant_answers WHERE id IN ('draft-test','expired-test','future-test')"
            ).fetchall()
            == []
        )
        with pytest.raises(psycopg.errors.InsufficientPrivilege), db.transaction():
            db.execute("UPDATE public.assistant_answers SET answer='Changed' WHERE id='live-data'")
    finally:
        repository.close()


def test_saved_places_are_owner_private_and_defaults_atomic(db):
    a = "20000000-0000-4000-8000-000000000001"
    b = "20000000-0000-4000-8000-000000000002"
    db.execute("INSERT INTO auth.users(id) VALUES (%s),(%s)", (a, b))
    db.execute(
        "INSERT INTO public.saved_places(user_id,place_id,label) VALUES (%s,'kibera','Home'),(%s,'westlands','Work'),(%s,'kibera','Private')",
        (a, a, b),
    )
    db.execute("SET LOCAL ROLE authenticated")
    db.execute("SELECT set_config('request.jwt.claim.sub',%s,true)", (a,))
    rows = db.execute("SELECT id,user_id FROM public.saved_places").fetchall()
    assert len(rows) == 2
    assert all(str(row["user_id"]) == a for row in rows)
    for row in rows:
        db.execute("SELECT public.set_default_place(%s)", (row["id"],))
        defaults = db.execute("SELECT id FROM public.saved_places WHERE is_default").fetchall()
        assert [r["id"] for r in defaults] == [row["id"]]
    with pytest.raises(psycopg.errors.InsufficientPrivilege), db.transaction():
        db.execute(
            "INSERT INTO public.saved_places(user_id,place_id,label) VALUES (%s,'embakasi','Forbidden')",
            (b,),
        )
    assert db.execute("DELETE FROM public.saved_places WHERE user_id=%s", (b,)).rowcount == 0
    with pytest.raises(psycopg.errors.RaiseException), db.transaction():
        db.execute("SELECT public.set_default_place('ffffffff-ffff-4fff-8fff-ffffffffffff')")
    assert len(db.execute("SELECT id FROM public.saved_places WHERE is_default").fetchall()) == 1
