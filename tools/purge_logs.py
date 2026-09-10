#!/usr/bin/env python3
"""Prune expired runtime diagnostics; default is a dry run, --apply deletes files."""
from __future__ import annotations

import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import stat
import time

ROOT = Path(__file__).resolve().parents[1]
LOG_NAME = re.compile(r"(?:.+\.log(?:\.\d+)?|ai-[12]\.json(?:l(?:\.\d+)?)?|.+\.replay\.jsonl)(?:\.tmp)?$")
SKIP_DIRS = {".git", ".godot", "__pycache__", "client", "server", "tools", "tests", "fixtures", "deps"}


def active_paths(root: Path) -> set[Path]:
    """Protect whole dev/verification runs referenced by live processes on Linux."""
    protected: set[Path] = set()
    live_pids: set[str] = set()
    prefix = str(root) + "/"
    for process in Path("/proc").iterdir():
        if not process.name.isdigit():
            continue
        try:
            if process.stat().st_uid != os.getuid():
                continue
            live_pids.add(process.name)
            for raw in (process / "cmdline").read_bytes().split(b"\0"):
                value = raw.decode(errors="replace").split("=", 1)[-1]
                if not value.startswith(prefix):
                    continue
                relative = Path(value).relative_to(root)
                if len(relative.parts) >= 3 and relative.parts[:2] in [("build", "dev"), ("build", "verification")]:
                    protected.add(root.joinpath(*relative.parts[:3]))
                elif relative.parts and relative.parts[0] in {"logs", "replays"}:
                    protected.add(root / relative.parts[0])
        except (OSError, ValueError):
            continue
    # Launchers and checks encode their PID in the run name, including the
    # staging interval before session.json or a host process exists.
    for base in (root / "build/dev", root / "build/verification"):
        if base.is_dir() and not base.is_symlink():
            protected.update(p for p in base.iterdir() if p.is_dir() and p.name.rsplit("-", 1)[-1] in live_pids)
    return protected


def expired_logs(root: Path, cutoff: float, protected: set[Path]) -> list[tuple[Path, os.stat_result]]:
    candidates: list[tuple[Path, os.stat_result]] = []
    for base in (root / "build", root / "logs", root / "replays"):
        if base.is_symlink() or not base.is_dir():
            continue
        for current, directories, files in os.walk(base, followlinks=False):
            directory = Path(current)
            if any(p == directory or p in directory.parents for p in protected) or (directory / ".keep-logs").exists():
                directories[:] = []
                continue
            directories[:] = [name for name in directories if name not in SKIP_DIRS and not (directory / name).is_symlink()]
            for name in files:
                if not LOG_NAME.fullmatch(name):
                    continue
                path = directory / name
                try:
                    info = path.lstat()
                    if stat.S_ISREG(info.st_mode) and info.st_mtime < cutoff:
                        candidates.append((path, info))
                except FileNotFoundError:
                    continue
    return candidates


def purge(root: Path, hours: float, apply: bool, protected: set[Path] | None = None) -> dict:
    if hours <= 0:
        raise ValueError("Retention must be greater than zero hours")
    protected = active_paths(root) if protected is None else protected
    cutoff = time.time() - hours * 3600
    candidates = expired_logs(root, cutoff, protected)
    removed, removed_bytes = 0, 0
    errors: list[str] = []
    if apply:
        # Refresh activity immediately before mutation: a run may have started
        # during enumeration. Recheck identity/mtime and reject new symlinks.
        protected |= active_paths(root)
        for path, before in candidates:
            try:
                if any(p == path.parent or p in path.parents for p in protected):
                    continue
                if any(parent.is_symlink() or (parent / ".keep-logs").exists() for parent in path.parents if parent != root and root in parent.parents):
                    continue
                current = path.lstat()
                if not stat.S_ISREG(current.st_mode) or current.st_ino != before.st_ino or current.st_mtime != before.st_mtime or current.st_mtime >= cutoff:
                    continue
                path.unlink()
                removed += 1
                removed_bytes += current.st_size
            except FileNotFoundError:
                continue
            except OSError as error:
                errors.append(f"{path.relative_to(root)}: {error}")
    return {"mode": "apply" if apply else "dry-run", "retention_hours": hours, "eligible_files": len(candidates),
            "eligible_bytes": sum(info.st_size for _, info in candidates), "removed_files": removed,
            "removed_bytes": removed_bytes, "protected_runs": len(protected), "errors": errors,
            "examples": [str(path.relative_to(root)) for path, _ in candidates[:10]]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--older-than-hours", type=float, default=24)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if not 0 < args.older_than_hours < 876000:
        parser.error("--older-than-hours must be finite and between 0 and 876000")
    (ROOT / "build").mkdir(exist_ok=True)
    with (ROOT / "build/log-cleanup.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("Another log cleanup is already running.")
            return 0
        result = purge(ROOT, args.older_than_hours, args.apply)
        print(json.dumps(result, indent=2))
        return int(bool(result["errors"]))


if __name__ == "__main__":
    raise SystemExit(main())
