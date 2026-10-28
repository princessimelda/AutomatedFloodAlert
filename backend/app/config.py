from pathlib import Path
from typing import Literal

from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="FLOODSAFE_",
        env_file=Path(__file__).resolve().parents[1] / ".env",
        extra="forbid",
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
