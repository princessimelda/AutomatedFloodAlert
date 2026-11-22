"""Create local demo credentials once, with no overwrite or secret output."""

import json
import os
import secrets
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def provision(path, public_config=None):
    public = public_config or {}
    principals = {
        role: {"key": secrets.token_urlsafe(32), "actor_id": "student-" + role, "role": role}
        for role in ("integration", "operator", "approver")
    }
    values = {
        "ALERT_PRINCIPALS": json.dumps(principals),
        "AUTH_URL": public.get("FLOODSAFE_SUPABASE_URL", ""),
        "AUTH_PUBLISHABLE_KEY": public.get("FLOODSAFE_SUPABASE_PUBLISHABLE_KEY", ""),
        "SMS_ENABLED": "false",
        "NOTIFICATION_WORKER_ENABLED": "false",
        "SMS_ACCOUNT_SID": "",
        "SMS_AUTH_TOKEN": "",
        "SMS_FROM": "",
        "SMS_TEST_RECIPIENTS": "{}",
    }
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w") as output:
        output.write("# Private prototype configuration; never commit or paste into chat.\n")
        output.writelines(f"FLOODSAFE_{key}={value}\n" for key, value in values.items())


def main():
    path = ROOT / "backend/.env.notifications"
    config = ROOT / "floodsafe/config.local.json"
    public = json.loads(config.read_text()) if config.exists() else {}
    try:
        provision(path, public)
        print("Created private backend/.env.notifications. SMS remains disabled.")
    except FileExistsError:
        print("Private notification configuration already exists; no changes made.")


if __name__ == "__main__":
    main()
