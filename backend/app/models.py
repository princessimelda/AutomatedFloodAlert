from datetime import datetime
from typing import Annotated, Literal

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator


class ContractModel(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class Place(ContractModel):
    id: str
    name: str
    is_demo: bool


class DashboardRequest(ContractModel):
    place_id: Annotated[str, Field(min_length=1, max_length=128)]
    latitude: Annotated[float | None, Field(ge=-90, le=90)] = None
    longitude: Annotated[float | None, Field(ge=-180, le=180)] = None

    @model_validator(mode="after")
    def validate_location(self):
        gps = self.place_id.startswith("gps:")
        if gps != (self.latitude is not None and self.longitude is not None):
            raise ValueError(
                "GPS requests require both coordinates; named places use place_id only."
            )
        if not gps and (self.latitude is not None or self.longitude is not None):
            raise ValueError("Named places cannot include coordinates.")
        if not gps and (
            len(self.place_id) > 64
            or not all(c in "abcdefghijklmnopqrstuvwxyz0123456789-" for c in self.place_id)
        ):
            raise ValueError("Invalid place identifier.")
        return self


class Assessment(ContractModel):
    level: Literal["low", "moderate", "high"]
    issued_at: AwareDatetime
    valid_until: AwareDatetime

    @model_validator(mode="after")
    def validate_dates(self):
        if self.valid_until <= self.issued_at:
            raise ValueError("Validity must end after issue time.")
        return self

    def current(self, now: datetime) -> bool:
        return self.issued_at <= now < self.valid_until


class Dashboard(ContractModel):
    place_id: str
    source: str
    is_demo: bool
    assessment: Assessment | None = None


class Advisory(ContractModel):
    id: str
    place_id: str | None = None
    language: Literal["en", "sw"]
    title: str
    body: str
    source: str
    source_url: str
    published_at: AwareDatetime
    valid_until: AwareDatetime
    is_demo: bool


class ApiError(ContractModel):
    code: str
    message: str


class AssistantQuestion(ContractModel):
    id: str
    language: Literal["en", "sw"]
    category: str
    question: str


class AssistantAnswer(AssistantQuestion):
    answer: str
    source: str
    source_url: str
    reviewed_at: AwareDatetime
    valid_until: AwareDatetime
