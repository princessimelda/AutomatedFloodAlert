"""Optional, pinned OpenMP runtime for Intel Macs without a working libomp install."""

import ctypes
import hashlib
import io
import json
import platform
import subprocess
import tarfile
from pathlib import Path

URL = "https://conda.anaconda.org/conda-forge/osx-64/llvm-openmp-15.0.5-h61d9ccf_0.tar.bz2"
SHA256 = "63550d85200d78c1db5ab44f32ff5ead273e373b9634a3d9fe82085d03ace3e5"
CACHE = Path(__file__).resolve().parents[2] / ".cache" / "nairobi-openmp"


def prepare_macos_runtime(download=False):
    if platform.system() != "Darwin" or platform.machine() != "x86_64":
        return None
    library = CACHE / "libomp.dylib"
    receipt = CACHE / "provenance.json"
    if not library.exists():
        if not download:
            return None
        result = subprocess.run(
            [
                "curl",
                "--fail",
                "--location",
                "--silent",
                "--show-error",
                "--max-time",
                "60",
                URL,
            ],
            check=True,
            capture_output=True,
        )
        if hashlib.sha256(result.stdout).hexdigest() != SHA256:
            raise ValueError("OpenMP package checksum mismatch.")
        CACHE.mkdir(parents=True, exist_ok=True)
        with tarfile.open(fileobj=io.BytesIO(result.stdout), mode="r:bz2") as archive:
            # Read only the exact library, not arbitrary archive paths.
            content = archive.extractfile("lib/libomp.dylib").read()
            library.write_bytes(content)
            for member in archive.getmembers():
                if member.isfile() and member.name.startswith("info/licenses/"):
                    (CACHE / Path(member.name).name).write_bytes(
                        archive.extractfile(member).read()
                    )
        receipt.write_text(
            json.dumps(
                {
                    "source_url": URL,
                    "package_sha256": SHA256,
                    "library_sha256": hashlib.sha256(content).hexdigest(),
                },
                indent=2,
            )
        )
    if (
        not receipt.exists()
        or hashlib.sha256(library.read_bytes()).hexdigest()
        != json.loads(receipt.read_text())["library_sha256"]
    ):
        raise ValueError("Cached OpenMP library failed integrity verification.")
    ctypes.CDLL(str(library), mode=ctypes.RTLD_GLOBAL)
    return library
