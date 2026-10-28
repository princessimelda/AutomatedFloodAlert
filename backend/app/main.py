from contextlib import asynccontextmanager
from typing import Annotated, Literal

from fastapi import FastAPI, Path, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException

from .config import Settings
from .models import (
    Advisory,
    ApiError,
    AssistantAnswer,
    AssistantQuestion,
    Dashboard,
    DashboardRequest,
    Place,
)
from .repositories import (
    AnswerUnavailable,
    DatabaseUnavailable,
    FixtureRepository,
    NotFound,
    PostgresRepository,
    Repository,
)


def create_app(settings: Settings | None = None, repository: Repository | None = None):
    settings = settings or Settings()
    if settings.data_mode == "fixtures" and not settings.allow_demo_data:
        raise ValueError("Fixture mode requires explicit FLOODSAFE_ALLOW_DEMO_DATA=true.")
    store = repository or (
        FixtureRepository() if settings.data_mode == "fixtures" else PostgresRepository(settings)
    )

    @asynccontextmanager
    async def lifespan(app):
        yield
        store.close()

    app = FastAPI(title="FloodSafe public information API", version="0.1.0", lifespan=lifespan)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_methods=["GET", "POST"],
        allow_headers=["Content-Type"],
        allow_credentials=False,
    )

    def error(status, code, message):
        return JSONResponse(
            status_code=status,
            content=ApiError(code=code, message=message).model_dump(),
        )

    @app.exception_handler(RequestValidationError)
    async def invalid_request(request, exception):
        # Do not echo coordinates, request bodies, or validation input values.
        return error(422, "invalid_request", "Check the request fields and coordinate ranges.")

    @app.exception_handler(NotFound)
    async def not_found(request, exception):
        return error(404, "place_not_found", "This place is not available.")

    @app.exception_handler(AnswerUnavailable)
    async def answer_unavailable(request, exception):
        return error(
            404,
            "answer_unavailable",
            "This answer is no longer available. Refresh the question list.",
        )

    @app.exception_handler(DatabaseUnavailable)
    async def database_error(request, exception):
        return error(
            503,
            "data_unavailable",
            "Information is temporarily unavailable. Try again later.",
        )

    @app.exception_handler(HTTPException)
    async def http_error(request, exception):
        return error(
            exception.status_code,
            "http_error",
            "The requested operation is not available.",
        )

    @app.exception_handler(Exception)
    async def unexpected_error(request, exception):
        return error(500, "internal_error", "Could not complete the request.")

    @app.middleware("http")
    async def no_private_caching(request: Request, call_next):
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        return response

    @app.get("/healthz")
    def health():
        return {"status": "ok", "data_mode": settings.data_mode}

    @app.get("/readyz")
    def ready():
        store.ping()
        return {"status": "ready", "data_mode": settings.data_mode}

    @app.get("/v1/places", response_model=list[Place])
    def places():
        return store.places()

    @app.post("/v1/dashboard", response_model=Dashboard)
    def dashboard(request: DashboardRequest):
        # Coordinates are a POST body, never persisted or logged by the app.
        return store.dashboard(request)

    @app.get("/v1/advisories", response_model=list[Advisory])
    def advisories(
        place_id: Annotated[str | None, Query(max_length=128)] = None,
        language: Literal["en", "sw"] = "en",
        limit: Annotated[int, Query(ge=1, le=100)] = 20,
    ):
        return store.advisories(place_id, language, limit)

    @app.get("/v1/assistant/questions", response_model=list[AssistantQuestion])
    def assistant_questions(language: Literal["en", "sw"] = "en"):
        return store.assistant_questions(language)

    @app.get("/v1/assistant/questions/{question_id}", response_model=AssistantAnswer)
    def assistant_answer(
        question_id: Annotated[str, Path(pattern="^[a-z0-9][a-z0-9-]{0,63}$")],
        language: Literal["en", "sw"] = "en",
    ):
        return store.assistant_answer(question_id, language)

    return app


app = create_app()
