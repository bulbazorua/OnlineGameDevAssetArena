#!/usr/bin/env python3
"""Real search, public alerts, saved debug preferences, six windows and restart."""
from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

from ai_debugger_check import read, wait, checked
from senses_windows_check import native_windows

ROOT = Path(__file__).resolve().parents[1]


def prepare(args, sandbox: Path) -> list[str]:
    for name in ("client", "server", "tools", "tests"):
        shutil.copytree(ROOT / name, sandbox / name, ignore=shutil.ignore_patterns(".godot", "__pycache__"))
    (sandbox / "build/deps").mkdir(parents=True)
    shutil.copy2(ROOT / "build/deps/libenet.a", sandbox / "build/deps/libenet.a")
    wrapper = sandbox / "godot-driver"
    wrapper.write_text("#!/usr/bin/env python3\nimport os, sys\nargs = sys.argv[1:]\n"
        "if '--dev' in args:\n    args += [" + repr("--dev-preferences-dir=" + str(sandbox / "preferences")) + "]\n"
        "if any(a.startswith('--dev-slot=p') for a in args):\n"
        "    args = ['--script', " + repr(str(sandbox / "tests/search_client_driver.gd")) + "] + args\n"
        "elif '--ai-debug' in args:\n"
        "    args = ['--script', " + repr(str(sandbox / "tests/search_ai_driver.gd")) + "] + [a for a in args if a != 'res://dev/ai/ai_debug_window.tscn']\n"
        "elif '--senses-debug' in args:\n"
        "    args = ['--script', " + repr(str(sandbox / "tests/senses_window_driver.gd")) + "] + [a for a in args if a != 'res://dev/senses/senses_window.tscn']\n"
        "os.execvp(" + repr(args.godot) + ", [" + repr(args.godot) + "] + args)\n")
    wrapper.chmod(0o755)
    command = [sys.executable, str(sandbox / "tools/dev_session.py"), "--godot", str(wrapper), "--odin", args.odin,
        "--p1", "archer", "--p2", "archer", "--seed", "42", "--watch", "0", "--arena", "vision_range",
        "--qa-arena", "client/dev/fixtures/content/vision_range.arenas.json"]
    if not args.graphical: command.append("--headless")
    return command


def stop(process) -> None:
    if process.poll() is not None: return
    process.send_signal(signal.SIGTERM)
    try:
        process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()


def check_exploration_memory(directory: Path, traces: Path) -> None:
    for owner in (1, 2):
        view = read(directory / f"senses{owner}.json")["exploration_memory"]["memory"]
        assert view["owner_id"] == owner and 0 < len(view["visits"]) <= view["capacity"] <= 16, view
        records = []
        for path in traces.glob(f"ai-{owner}.jsonl*"):
            records.extend(json.loads(line) for line in path.read_text().splitlines() if line.endswith("}"))
        source = next(r for r in records if r["input"]["tick"] == view["tick"] and r["input"]["round_id"] == view["round_id"])
        search = source["after"]["search"]
        assert view["entity_id"] == source["input"]["entity_id"] and view["position"] == search["position"]
        for shown in view["visits"]:
            visit = search["visits"][shown["number"] - 1]
            age = (view["tick"] - visit["visited_tick"]) % (2**32)
            assert shown["position"] == visit["position"] and shown["opponent_seen"] == visit["opponent_seen"]
            assert shown["age_ticks"] == age and abs(shown["strength"] - (1 - age / view["retention_ticks"])) < 0.00001


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--odin", default="odin")
    parser.add_argument("--graphical", action="store_true")
    args = parser.parse_args()
    sandbox = ROOT / "build/verification" / f"search-{time.strftime('%Y%m%d-%H%M%S')}-{os.getpid()}"
    sandbox.mkdir(parents=True)
    print(f"Search verification: {sandbox}", flush=True)
    command = prepare(args, sandbox)
    prior = set()
    first_recording = None
    for attempt, expected in enumerate(((False, False), (True, True), (False, True)), 1):
        process = None
        try:
            with (sandbox / f"runner-{attempt}.log").open("w") as log:
                process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            paths = lambda: set((sandbox / "build/dev").glob("*/session.json")) - prior
            wait(lambda: paths(), "fresh search session")
            session_path = next(iter(paths()))
            prior.add(session_path)
            session = read(session_path)
            directory = session_path.parent
            status = lambda owner: read(directory / f"search-p{owner}.json")
            wait(lambda: all(status(i).get("preference_path") for i in (1, 2)), "saved preference binding")
            for i in (1, 2):
                assert status(i)["enabled"] == expected[i - 1] and not status(i)["preference_error"], status(i)
            assert session["ai_slots"] == ["ai1", "ai2"] and session["senses_slots"] == ["senses1", "senses2"]
            if args.graphical and attempt == 1: native_windows(sandbox, session)
            wait(lambda: all(len(status(i).get("acquisitions", {})) == 2 for i in (1, 2)), "both public target markers", 20)
            wait(lambda: all(len(status(i).get("body_hops", {})) == 2 and len(status(i).get("body_landings", {})) == 2 for i in (1, 2)), "both creature bodies jump and land in both clients", 20)
            traces = Path(session["ai_trace_dir"])
            if attempt == 1:
                first_recording = traces / "match.replay.jsonl"
                memory = lambda owner: read(directory / f"senses{owner}.json").get("exploration_memory", {})
                wait(lambda: all(memory(i).get("status") == "LIVE" and memory(i).get("memory", {}).get("visits") for i in (1, 2)), "live private visits with F6 off")
                (directory / "senses-driver.json").write_text(json.dumps({"sequence": 1, "memory_only": True}))
                wait(lambda: all(read(directory / f"driver-senses{i}.json").get("passed") for i in (1, 2)), "memory tab selection and layout")
                check_exploration_memory(directory, traces)
                (sandbox / "exploration-memory.json").write_text(json.dumps({f"p{i}": memory(i) for i in (1, 2)}, indent=2))
                (directory / "search-command.json").write_text(json.dumps({"sequence": 1, "slots": ["p1", "p2"]}))
                wait(lambda: all(status(i).get("enabled") and status(i).get("readings") == 2 for i in (1, 2)), "F6 live search overlay")
                wait(lambda: "Direction scores" in status(1)["text"] and "Private visits" in status(1)["text"], "rendered search details")
                wait(lambda: all(read(directory / f"search-ai{i}.json").get("shown") for i in (1, 2)), "AI Search tabs sharing the saved setting")
                if args.graphical:
                    wait(lambda: all((directory / f"p{i}-search-debug-1.png").exists() and (directory / f"ai{i}-search.png").exists() for i in (1, 2)), "rendered search captures")
                for owner in (1, 2):
                    journal = []
                    for segment in (f"ai-{owner}.jsonl.3", f"ai-{owner}.jsonl.2", f"ai-{owner}.jsonl.1", f"ai-{owner}.jsonl"):
                        path = traces / segment
                        if path.exists(): journal.extend(json.loads(line) for line in path.read_text().splitlines() if line.endswith("}"))
                    acquired = next(r for r in journal if r["after"]["search"]["acquisition_count"] > r["before"]["search"]["acquisition_count"])
                    target = acquired["after"]["search"]
                    sample = acquired["input"]["senses"]["vision"]
                    assert any(s["subject"] == target["target"] and s["position"] == target["target_position"] for s in sample["focused"][:int(sample["focused_count"])]), acquired
                    assert target["acquired_tick"] == status(owner)["acquisitions"][str(owner)]
                (sandbox / "acquisitions.json").write_text(json.dumps({"p1": status(1), "p2": status(2)}, indent=2))
                previous_round = status(1)["round"]
                reset_requested_tick = max(status(i)["tick"] for i in (1, 2))
                (directory / "search-command.json").write_text(json.dumps({"sequence": 2, "slots": ["p1"], "action": "reset"}))
                wait(lambda: all(status(i).get("round", 0) == previous_round + 1 for i in (1, 2)), "real reset-button click and synchronized new round")
                for owner in (1, 2):
                    fresh = status(owner)["rounds"][str(previous_round + 1)]
                    assert fresh["summon"] < 90 and not any(c["alert"] for c in fresh["characters"]), fresh
                    assert math.dist(*(c["position"] for c in fresh["characters"])) >= 408, fresh
                    assert not {c["id"] for c in fresh["characters"]} & {c["id"] for c in status(owner)["rounds"][str(previous_round)]["characters"]}
                wait(lambda: all(status(i).get("brain_rounds") == [previous_round + 1] * 2 for i in (1, 2)), "fresh search diagnostics after reset")
                wait(lambda: all(memory(i).get("memory", {}).get("round_id") == previous_round + 1 for i in (1, 2)), "memory windows rebound after reset")
                for owner in (1, 2):
                    fresh_memory = memory(owner)["memory"]
                    assert fresh_memory["entity_id"] == status(owner)["rounds"][str(previous_round + 1)]["characters"][owner - 1]["id"]
                    assert all((visit["visited_tick"] - reset_requested_tick) % (2**32) < 2**31 for visit in fresh_memory["visits"]), "Old exploration entries survived reset"
                initial = status(1)["rounds"][str(previous_round + 1)]["characters"]
                def explored():
                    positions = status(1).get("positions", [])
                    return len(positions) == 2 and all(math.dist(start["position"], current) > 12 for start, current in zip(initial, positions))
                wait(explored, "both creatures explore after reset")
                assert all(status(i)["enabled"] for i in (1, 2)), "Reset changed saved debug toggles"
                assert "Search reset" in status(1)["reset_status"], status(1)
                (sandbox / "search-reset.json").write_text(json.dumps({"p1": status(1), "p2": status(2)}, indent=2))
                if args.graphical:
                    wait(lambda: all((directory / f"p{i}-search-reset.png").exists() for i in (1, 2)), "reset-button render captures")
                    native_windows(sandbox, session)
            elif attempt == 2:
                wait(lambda: all(status(i).get("readings") == 2 for i in (1, 2)), "restored live search display")
                (directory / "search-command.json").write_text(json.dumps({"sequence": 1, "slots": ["p1"]}))
                wait(lambda: status(1).get("sequence") == 1 and not status(1).get("enabled"), "saved off toggle")
                assert status(2)["enabled"], "P1 toggle changed P2 preference"
            for log in (directory / "generation-1").glob("*.log"):
                text = log.read_text()
                assert "SCRIPT ERROR:" not in text and "ERROR:" not in text, (log, text[-2000:])
        finally:
            if process is not None: stop(process)
    checked([args.godot, "--headless", "--path", str(first_recording.parent.parent / "client"),
        "--script", str(ROOT / "tests/search_replay_check.gd"), "--", "--expect-reset", "--fixture=" + str(first_recording)], sandbox / "replay-check.log")
    print("PASS: private search acquisition, creature body hops and landings, senses-window exploration memory, pixel markers, default-off F6, independent saved toggles across three launches, host reset button, six roles and recorded reset/alert replay.", flush=True)


if __name__ == "__main__":
    main()
