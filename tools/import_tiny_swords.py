#!/usr/bin/env python3
"""Install the reviewed Tiny Swords subset locally, preserving original PNGs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "client/assets/tiny_swords"
DEFAULT_SOURCE = Path.home() / "CONTENT_CREATION/BulbaZorua/GameAssets/Tiny Swords (Free Pack)/Tiny Swords (Free Pack)"


def validated_files(source: Path) -> list[tuple[Path, bytes]]:
    manifest = json.loads((DESTINATION / "manifest.json").read_text())
    if manifest.get("schema_version") != 1:
        raise ValueError("Unsupported Tiny Swords manifest version")
    prepared = []
    source = source.expanduser().resolve()
    for entry in manifest["files"]:
        relative = Path(entry["path"])
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"Invalid manifest path: {relative}")
        path = (source / relative).resolve()
        if not path.is_relative_to(source):
            raise ValueError(f"Source path leaves the pack: {relative}")
        data = path.read_bytes()
        if not data.startswith(b"\x89PNG\r\n\x1a\n") or len(data) < 24:
            raise ValueError(f"Not a PNG: {relative}")
        if struct.unpack(">II", data[16:24]) != (entry["width"], entry["height"]):
            raise ValueError(f"Unexpected dimensions: {relative}")
        if hashlib.sha256(data).hexdigest() != entry["sha256"]:
            raise ValueError(f"Different pack bytes: {relative}; review the manifest before replacing this version")
        prepared.append((relative, data))
    return prepared


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--verify", action="store_true", help="Check local copies without importing")
    args = parser.parse_args()
    try:
        # Preflight every file before modifying the installed subset.
        files = validated_files(DESTINATION if args.verify else args.source)
        if not args.verify:
            for relative, data in files:
                target = DESTINATION / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                if target.exists() and target.read_bytes() == data:
                    continue
                with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as temporary:
                    temporary.write(data)
                    temporary_path = Path(temporary.name)
                try:
                    os.replace(temporary_path, target)
                finally:
                    temporary_path.unlink(missing_ok=True)
        print(f"{'Verified' if args.verify else 'Installed'} {len(files)} original Tiny Swords PNGs (local, ignored by Git).")
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"Tiny Swords import failed: {error}\nUse --source with the supplied Free Pack directory.\n")


if __name__ == "__main__":
    raise SystemExit(main())
