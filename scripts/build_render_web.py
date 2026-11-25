"""Build Flutter for Render using only explicitly allowed public configuration."""

import json
import os
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import urlsplit

FLUTTER_VERSION = "3.47.5"  # Match .github/workflows/checks.yml.
PUBLIC_KEYS = (
    "FLOODSAFE_API_URL",
    "FLOODSAFE_SUPABASE_URL",
    "FLOODSAFE_SUPABASE_PUBLISHABLE_KEY",
)


def public_configuration(environment):
    """Fail before download/build if hosted settings are missing or unsafe."""
    config = {key: environment.get(key, "").strip() for key in PUBLIC_KEYS}
    for key in PUBLIC_KEYS[:2]:
        try:
            url = urlsplit(config[key])
            valid = (
                url.scheme == "https"
                and bool(url.hostname)
                and url.hostname not in ("localhost", "127.0.0.1", "::1")
                and url.username is None
                and url.password is None
                and not url.query
                and not url.fragment
                and url.port in (None, 443)
                and url.path in ("", "/")
            )
        except ValueError:
            valid = False
        if not valid:
            raise ValueError(f"Set {key} to a public HTTPS origin.")
        config[key] = config[key].rstrip("/")
    if not config[PUBLIC_KEYS[2]].startswith("sb_publishable_"):
        raise ValueError("Set the Supabase publishable key, never a service-role key.")
    return config


def main():
    config = public_configuration(os.environ)
    project = Path(__file__).resolve().parents[1] / "floodsafe"
    with tempfile.TemporaryDirectory(prefix="floodsafe-render-") as work:
        work = Path(work)
        sdk = work / "flutter"
        subprocess.run(
            [
                "git",
                "clone",
                "--depth",
                "1",
                "--branch",
                FLUTTER_VERSION,
                "https://github.com/flutter/flutter.git",
                str(sdk),
            ],
            check=True,
        )
        flutter = str(sdk / "bin" / "flutter")
        defines = work / "public-config.json"
        defines.write_text(json.dumps(config))
        defines.chmod(0o600)
        subprocess.run([flutter, "config", "--no-analytics"], check=True)
        subprocess.run([flutter, "pub", "get"], cwd=project, check=True)
        subprocess.run(
            [
                flutter,
                "build",
                "web",
                "--release",
                "--no-web-resources-cdn",
                f"--dart-define-from-file={defines}",
            ],
            cwd=project,
            check=True,
        )


if __name__ == "__main__":
    main()
