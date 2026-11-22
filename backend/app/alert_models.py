"""Test-event and approved-publication contracts for the student prototype."""

from datetime import UTC, datetime, timedelta
from typing import Annotated, Literal
from uuid import UUID

from pydantic import AwareDatetime, Field, field_validator, model_validator

from .models import ContractModel

Severity = Literal["information", "advisory", "warning", "critical"]
EventKind = Literal["rainfall_proxy", "manual_report"]


class RuleInput(ContractModel):
    name: str = Field(min_length=1, max_length=120)
    version: int = Field(ge=1)
    event_kind: EventKind
    threshold: float = Field(ge=0)
    severity: Severity

    @field_validator("name")
    @classmethod
    def nonblank(cls, value):
        if not value.strip():
            raise ValueError("Text must not be blank.")
        return value.strip()

    @model_validator(mode="after")
    def proxy_is_information(self):
        if self.event_kind == "rainfall_proxy" and self.severity != "information":
            raise ValueError("A rainfall proxy cannot establish flood severity.")
        return self


class EventInput(ContractModel):
    source_event_id: str = Field(min_length=1, max_length=120)
    rule_id: UUID
    event_kind: EventKind
    metric: float = Field(ge=0)
    occurred_at: AwareDatetime
    valid_until: AwareDatetime
    evidence: str = Field(min_length=1, max_length=2000)
    title: str = Field(min_length=1, max_length=160)
    message: str = Field(min_length=1, max_length=1000)
    recommended_action: str = Field(min_length=1, max_length=300)
    place_ids: Annotated[list[str], Field(min_length=1, max_length=20)]
    is_demo: Literal[True] = True

    @field_validator("source_event_id", "evidence", "title", "message", "recommended_action")
    @classmethod
    def nonblank(cls, value):
        if not value.strip():
            raise ValueError("Text must not be blank.")
        return value.strip()

    @model_validator(mode="after")
    def check_event(self):
        now = datetime.now(UTC)
        if not self.occurred_at <= now < self.valid_until <= self.occurred_at + timedelta(days=1):
            raise ValueError("A test event must be current and valid for at most one day.")
        if len(set(self.place_ids)) != len(self.place_ids) or any(
            not 1 <= len(p) <= 64
            or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789-" for c in p)
            for p in self.place_ids
        ):
            raise ValueError("Use distinct catalogue locations.")
        return self


class ActionInput(ContractModel):
    expected_revision: int = Field(ge=1)
    reason: str = Field(min_length=1, max_length=500)

    @field_validator("reason")
    @classmethod
    def nonblank(cls, value):
        if not value.strip():
            raise ValueError("An audit reason is required.")
        return value.strip()


class AlertLocation(ContractModel):
    id: str
    name: str


class PublishedAlert(ContractModel):
    id: UUID
    title: str
    message: str
    recommended_action: str
    severity: Severity
    revision: int
    issued_at: AwareDatetime
    valid_until: AwareDatetime
    is_demo: Literal[True]
    locations: list[AlertLocation]
