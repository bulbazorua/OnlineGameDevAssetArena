#!/usr/bin/env python3
"""Open a QA recording without starting a host or joining the live game."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--replay", default="latest")
    parser.add_argument("--godot", default="godot")
    args = parser.parse_args()
    if args.replay == "latest":
        matches = list((ROOT / "build/dev").glob("*/generation-*/ai-traces-*/match.replay.jsonl"))
        if not matches:
            parser.error("No recording found. Start make dev_arena with AI_DEBUG=1 first.")
        recording = max(matches, key=lambda p: p.stat().st_mtime)
    else:
        recording = Path(args.replay).expanduser().resolve()
    if not recording.is_file(): parser.error(f"Recording does not exist: {recording}")
    # Prefer the run's retained project/resources when available. Exported files
    # use the current client and still require a matching content fingerprint.
    project = recording.parent.parent / "client"
    if not (project / "dev/ai/replay_window.tscn").is_file(): project = ROOT / "client"
    print(f"QA replay: {recording}\nPresentation project: {project}", flush=True)
    return subprocess.call([args.godot, "--path", str(project), "res://dev/ai/replay_window.tscn", "--", "--dev", f"--replay={recording}"])


if __name__ == "__main__":
    raise SystemExit(main())
