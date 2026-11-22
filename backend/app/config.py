import re
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class AlertPrincipal(BaseModel):
    model_config = ConfigDict(extra="forbid", hide_input_in_errors=True)
    key: SecretStr
    actor_id: str = Field(min_length=1, max_length=100)
    role: Literal["integration", "operator", "approver"]

    @model_validator(mode="after")
    def validate_key(self):
        if not 32 <= len(self.key.get_secret_value()) <= 256:
            raise ValueError("Operator keys must contain 32–256 characters.")
        return self


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="FLOODSAFE_",
        env_file=(
            Path(__file__).resolve().parents[1] / ".env",
            Path(__file__).resolve().parents[1] / ".env.notifications",
        ),
        extra="forbid",
        hide_input_in_errors=True,
    )
    data_mode: Literal["postgres", "fixtures"] = "postgres"
    allow_demo_data: bool = False
    db_host: str = ""
    db_port: int = 5432
    db_name: str = "postgres"
    db_user: str = ""
    db_password: SecretStr = SecretStr("")
    db_sslmode: Literal["require", "verify-full", "disable"] = "require"
    cors_origins: list[str] = ["http://127.0.0.1:8765", "http://localhost:8765"]
    alert_principals: dict[str, AlertPrincipal] = {}
    auth_url: str = ""
    auth_publishable_key: SecretStr = SecretStr("")
    sms_enabled: bool = False
    sms_account_sid: SecretStr = SecretStr("")
    sms_auth_token: SecretStr = SecretStr("")
    sms_from: SecretStr = SecretStr("")
    sms_test_recipients: dict[str, SecretStr] = {}
    notification_worker_enabled: bool = False

    @model_validator(mode="after")
    def distinct_operator_keys(self):
        keys = [principal.key.get_secret_value() for principal in self.alert_principals.values()]
        if len(set(keys)) != len(keys):
            raise ValueError("Operator credentials must be distinct.")
        if self.notification_worker_enabled and self.data_mode != "postgres":
            raise ValueError("The delivery worker requires PostgreSQL.")
        if len(self.sms_test_recipients) > 5:
            raise ValueError("The prototype supports up to five enrolled SMS testers.")
        if self.sms_enabled:
            if (
                not re.fullmatch(r"AC[a-fA-F0-9]{32}", self.sms_account_sid.get_secret_value())
                or len(self.sms_auth_token.get_secret_value()) < 16
                or not re.fullmatch(r"\+[1-9]\d{7,14}", self.sms_from.get_secret_value())
                or not self.sms_test_recipients
                or any(
                    not re.fullmatch(r"\+[1-9]\d{7,14}", value.get_secret_value())
                    for value in self.sms_test_recipients.values()
                )
            ):
                raise ValueError(
                    "Complete the live SMS configuration and enrolled test recipients before enabling SMS."
                )
        return self

    def connection_kwargs(self) -> dict:
        if not self.db_host or not self.db_user or not self.db_password.get_secret_value():
            raise ValueError("Complete the database fields in backend/.env first.")
        return dict(
            host=self.db_host,
            port=self.db_port,
            dbname=self.db_name,
            user=self.db_user,
            password=self.db_password.get_secret_value(),
            sslmode=self.db_sslmode,
            connect_timeout=5,
            application_name="floodsafe",
        )
