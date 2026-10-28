from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from threading import Lock
from typing import Protocol

from psycopg import Error
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool, PoolTimeout

from .config import Settings
from .models import (
    Advisory,
    Assessment,
    AssistantAnswer,
    AssistantQuestion,
    Dashboard,
    DashboardRequest,
    Place,
)


class NotFound(Exception):
    pass


class DatabaseUnavailable(Exception):
    pass


class AnswerUnavailable(Exception):
    pass


class Repository(Protocol):
    def assistant_questions(self, language: str) -> list[AssistantQuestion]: ...
    def assistant_answer(self, question_id: str, language: str) -> AssistantAnswer: ...
    def places(self) -> list[Place]: ...
    def dashboard(self, request: DashboardRequest) -> Dashboard: ...
    def advisories(self, place_id: str | None, language: str, limit: int) -> list[Advisory]: ...
    def ping(self) -> None: ...
    def close(self) -> None: ...


class FixtureRepository:
    """Explicit local mode only. Never an automatic database-outage fallback."""

    def __init__(self):
        now = datetime.now(timezone.utc)
        self._places = [
            Place(id=id, name=name, is_demo=True)
            for id, name in [
                ("kibera", "Kibera"),
                ("westlands", "Westlands"),
                ("embakasi", "Embakasi"),
                ("kasarani", "Kasarani"),
            ]
        ]
        self._assessments = {
            "kibera": Assessment(
                level="high",
                issued_at=now - timedelta(hours=1),
                valid_until=now + timedelta(hours=1),
            ),
            "kasarani": Assessment(
                level="low",
                issued_at=now - timedelta(hours=1),
                valid_until=now + timedelta(hours=1),
            ),
            "embakasi": Assessment(
                level="high",
                issued_at=now - timedelta(hours=4),
                valid_until=now - timedelta(hours=2),
            ),
        }
        self._advisory = Advisory(
            id="fixture-preparedness",
            language="en",
            title="Preparedness practice",
            body="Practise finding your household preparedness plan and checking official local updates. This is a test advisory, not an evacuation instruction.",
            source="FloodSafe development example; general preparedness adapted from CDC",
            source_url="https://www.cdc.gov/floods/safety/",
            published_at=now - timedelta(hours=1),
            valid_until=now + timedelta(days=7),
            is_demo=True,
        )

    def assistant_questions(self, language):
        return []

    def assistant_answer(self, question_id, language):
        raise AnswerUnavailable()

    def places(self):
        return self._places

    def dashboard(self, request):
        if not request.place_id.startswith("gps:") and request.place_id not in {
            p.id for p in self._places
        }:
            raise NotFound()
        return Dashboard(
            place_id=request.place_id,
            source="FloodSafe API fixtures; not current conditions",
            is_demo=True,
            assessment=self._assessments.get(request.place_id),
        )

    def advisories(self, place_id, language, limit):
        if (
            place_id
            and not place_id.startswith("gps:")
            and place_id not in {p.id for p in self._places}
        ):
            raise NotFound()
        now = datetime.now(timezone.utc)
        return (
            [self._advisory][:limit]
            if language == "en" and self._advisory.published_at <= now < self._advisory.valid_until
            else []
        )

    def ping(self):
        pass

    def close(self):
        pass


class PostgresRepository:
    def assistant_questions(self, language):
        with self._connection() as connection:
            rows = connection.execute(
                "SELECT id,language,category,question FROM public.assistant_answers WHERE language=%s ORDER BY sort_order,id LIMIT 100",
                (language,),
            ).fetchall()
        return [AssistantQuestion(**row) for row in rows]

    def assistant_answer(self, question_id, language):
        with self._connection() as connection:
            row = connection.execute(
                "SELECT id,language,category,question,answer,source,source_url,reviewed_at,valid_until FROM public.assistant_answers WHERE id=%s AND language=%s",
                (question_id, language),
            ).fetchone()
        if row is None:
            raise AnswerUnavailable()
        return AssistantAnswer(**row)

    def __init__(self, settings: Settings):
        self.settings = settings
        self._pool = None
        self._lock = Lock()

    def _get_pool(self):
        with self._lock:
            if self._pool is None:
                try:
                    kwargs = self.settings.connection_kwargs()
                except ValueError as error:
                    raise DatabaseUnavailable() from error
                self._pool = ConnectionPool(
                    kwargs={**kwargs, "row_factory": dict_row},
                    min_size=0,
                    max_size=3,
                    timeout=6,
                    open=True,
                )
        return self._pool

    @contextmanager
    def _connection(self):
        try:
            with self._get_pool().connection() as connection:
                with connection.transaction():
                    # Even an administrative connection uses a read-only,
                    # non-BYPASSRLS role for every application query.
                    connection.execute("SET LOCAL ROLE floodsafe_reader")
                    connection.execute("SET LOCAL statement_timeout = '3s'")
                    connection.execute("SET TRANSACTION READ ONLY")
                    yield connection
        except (Error, PoolTimeout) as error:
            raise DatabaseUnavailable() from error

    def ping(self):
        with self._connection() as connection:
            connection.execute("SELECT id FROM public.places LIMIT 1").fetchall()

    def places(self):
        with self._connection() as connection:
            rows = connection.execute(
                "SELECT id,name,is_demo FROM public.places WHERE (%s OR NOT is_demo) ORDER BY name",
                (self.settings.allow_demo_data,),
            ).fetchall()
        return [Place(**row) for row in rows]

    def dashboard(self, request):
        demo = self.settings.allow_demo_data
        with self._connection() as connection:
            place = None
            if request.place_id.startswith("gps:"):
                # Demo geometry must NEVER match real GPS coordinates.
                row = connection.execute(
                    """
                    SELECT r.level,r.source,r.issued_at,r.valid_until,r.is_demo
                    FROM public.risk_assessments r
                    JOIN public.susceptibility_grid g ON g.id=r.zone_id
                    WHERE NOT r.is_demo AND NOT g.is_demo AND r.issued_at <= now()
                    AND extensions.ST_Covers(g.boundary, extensions.ST_SetSRID(extensions.ST_MakePoint(%s,%s),4326))
                    ORDER BY (r.valid_until > now()) DESC,
                      CASE r.level WHEN 'high' THEN 3 WHEN 'moderate' THEN 2 ELSE 1 END DESC,
                      r.issued_at DESC, r.id LIMIT 1
                    """,
                    (request.longitude, request.latitude),
                ).fetchone()
            else:
                place = connection.execute(
                    "SELECT id,is_demo FROM public.places WHERE id=%s AND (%s OR NOT is_demo)",
                    (request.place_id, demo),
                ).fetchone()
                if place is None:
                    raise NotFound()
                row = connection.execute(
                    """
                    SELECT level,source,issued_at,valid_until,is_demo
                    FROM public.risk_assessments
                    WHERE place_id=%s AND (%s OR NOT is_demo) AND issued_at <= now()
                    ORDER BY (valid_until > now()) DESC, issued_at DESC, id LIMIT 1
                    """,
                    (request.place_id, demo),
                ).fetchone()
        if row is None:
            return Dashboard(
                place_id=request.place_id,
                source="FloodSafe database; no published assessment available",
                is_demo=bool(place and place["is_demo"]),
            )
        return Dashboard(
            place_id=request.place_id,
            source=row["source"],
            is_demo=row["is_demo"] or bool(place and place["is_demo"]),
            assessment=Assessment(
                level=row["level"],
                issued_at=row["issued_at"],
                valid_until=row["valid_until"],
            ),
        )

    def advisories(self, place_id, language, limit):
        with self._connection() as connection:
            if place_id and not place_id.startswith("gps:"):
                place = connection.execute(
                    "SELECT id FROM public.places WHERE id=%s AND (%s OR NOT is_demo)",
                    (place_id, self.settings.allow_demo_data),
                ).fetchone()
                if place is None:
                    raise NotFound()
            rows = connection.execute(
                """
                SELECT id::text,place_id,language,title,body,source,source_url,published_at,valid_until,is_demo
                FROM public.advisories WHERE language=%s AND (%s OR NOT is_demo)
                  AND (place_id IS NULL OR place_id=%s)
                  AND published_at <= now() AND valid_until > now()
                ORDER BY published_at DESC,id LIMIT %s
                """,
                (language, self.settings.allow_demo_data, place_id, limit),
            ).fetchall()
        return [Advisory(**row) for row in rows]

    def close(self):
        with self._lock:
            if self._pool is not None:
                self._pool.close()
                self._pool = None
