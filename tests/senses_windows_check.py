#!/usr/bin/env python3
"""Six native windows, private current readings, lifecycle and display latency."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

from ai_debugger_check import checked, journal_records, read, wait

ROOT = Path(__file__).resolve().parents[1]


def prepare(args, sandbox: Path) -> list[str]:
    for name in ("client", "server", "tools", "tests"):
        shutil.copytree(ROOT / name, sandbox / name, ignore=shutil.ignore_patterns(".godot", "__pycache__"))
    (sandbox / "build/deps").mkdir(parents=True)
    shutil.copy2(ROOT / "build/deps/libenet.a", sandbox / "build/deps/libenet.a")
    wrapper = sandbox / "godot-driver"
    wrapper.write_text("#!/usr/bin/env python3\nimport os, sys\nargs = sys.argv[1:]\n"
        "if '--senses-debug' in args and '--sense-owner=2' in args and os.path.exists(" + repr(str(sandbox / "fail-senses2")) + "):\n    sys.exit(7)\n"
        "for flag, scene, driver in " + repr([
            ("--senses-debug", "res://dev/senses/senses_window.tscn", str(sandbox / "tests/senses_window_driver.gd")),
            ("--ai-debug", "res://dev/ai/ai_debug_window.tscn", str(sandbox / "tests/ai_debugger_driver.gd")),
        ]) + ":\n    if flag in args:\n        args = ['--script', driver] + [a for a in args if a != scene]\n        break\n"
        "if any(a.startswith('--dev-slot=p') for a in args):\n    args = ['--script', " + repr(str(sandbox / "tests/dev_client_driver.gd")) + "] + args\n"
        "os.execvp(" + repr(args.godot) + ", [" + repr(args.godot) + "] + args)\n")
    wrapper.chmod(0o755)
    base = [sys.executable, str(sandbox / "tools/dev_session.py"), "--godot", str(wrapper), "--odin", args.odin,
            "--p1", "archer", "--p2", "archer", "--seed", "42", "--observe-only", "--arena", "vision_range",
            "--qa-arena", "client/dev/fixtures/content/vision_range.arenas.json"]
    if not args.graphical:
        base.append("--headless")
    return base


def check_bound_readings(directory: Path, session: dict) -> None:
    for owner in (1, 2):
        state = read(directory / f"senses{owner}.json")
        record = state["record"]
        assert state["role"] == "senses" and state["owner_id"] == owner and state["run_id"] == session["ai_run"]
        assert state["status"] == "LIVE" and not state["reader_error"]
        assert record["owner_id"] == owner and record["entity_id"] == record["vision"]["observer"]
        sample = record["vision"]
        expected = sample["focused"][:int(sample["focused_count"])]
        focused = [row for row in state["readings"] if row["quality"] == "Focused"]
        assert len(focused) == len(expected) and expected
        for row, sighting in zip(focused, expected):
            for key in ("subject", "position", "appearance_id", "facing", "locomotion"):
                assert row[key] == sighting[key], (key, row, sighting)
        # Journals rotate at 8 MiB, so the matching decision may already sit in an older segment.
        records = journal_records(Path(session["ai_trace_dir"]), owner)
        matched = [r for r in records if r["input"]["tick"] == record["tick"]]
        assert matched and matched[-1]["input"]["senses"]["vision"] == sample
        first = next(r for r in records if r["input"]["senses"]["vision"]["sample_id"] == sample["sample_id"])
        assert first["input"]["senses"]["vision_is_new"] and record["delivered_us"] == first["queued_us"]
        check_bound_olfaction(state, record, records)


def check_bound_olfaction(state: dict, record: dict, records: list[dict]) -> None:
    """The Olfaction page shows exactly the delivered nose sample, with its own delivery clock."""
    nose = record["olfaction"]
    assert state["olfaction_status"] == "LIVE" and nose["status"] == "Sampled" and nose["observer"] == record["entity_id"]
    shown = state["scent_readings"]
    expected = nose["readings"][:int(nose["reading_count"])]
    assert len(shown) == len(expected)
    for row, reading in zip(shown, expected):
        for key in ("observation_id", "class", "strength", "freshness", "bearing_valid", "zones"):
            assert row[key] == reading[key], (key, row, reading)
        assert not any(key in row for key in ("position", "subject", "entity_id")), row
    matched = [r for r in records if r["input"]["tick"] == record["tick"]]
    assert matched and matched[-1]["input"]["senses"]["olfaction"] == nose
    first = next(r for r in records if r["input"]["senses"]["olfaction"]["sample_id"] == nose["sample_id"])
    assert first["input"]["senses"]["olfaction_is_new"] and record["scent_delivered_us"] == first["queued_us"]
    assert record["own_emitter"]["class"] in ("Human", "Orc")
    check_coverage(state, nose)


def check_coverage(state: dict, nose: dict) -> None:
    """Coverage is the nose's own footprint: sixteen zone words, scent only on measured ground, shown as counted."""
    coverage = nose["coverage"]
    assert len(coverage) == 16 and set(coverage) <= {"Unsampled", "Partial", "Sampled"}, coverage
    for reading in nose["readings"][:int(nose["reading_count"])]:
        for zone, band in enumerate(reading["zones"]):
            assert band == "None" or coverage[zone] != "Unsampled", (zone, band, coverage)
    shown = state["scent_coverage"]
    assert shown["recorded"] and shown["sampled"] == coverage.count("Sampled") and shown["partial"] == coverage.count("Partial") and shown["unsampled"] == coverage.count("Unsampled"), (shown, coverage)
    assert state["scent_legend_fits"], "the Olfaction legend overflows its view"


def native_windows(sandbox: Path, session: dict) -> dict[int, str]:
    windows = subprocess.check_output(["wmctrl", "-lp"], text=True)
    owned = {int(line.split()[2]): line for line in windows.splitlines() if int(line.split()[2]) in session["pids"]}
    (sandbox / "six-native-windows.txt").write_text("\n".join(owned.values()) + "\n")
    assert len(owned) == 6, owned
    for pid in session["senses_pids"].values(): assert "SENSES" in owned[pid]
    for pid in session["ai_pids"].values(): assert "AI DEBUG" in owned[pid]
    return owned


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--odin", default="odin")
    parser.add_argument("--graphical", action="store_true")
    args = parser.parse_args()
    sandbox = ROOT / "build/verification" / f"senses-windows-{time.strftime('%Y%m%d-%H%M%S')}-{os.getpid()}"
    sandbox.mkdir(parents=True)
    print(f"Senses window verification artifacts: {sandbox}", flush=True)
    base = prepare(args, sandbox)
    process = None
    owned = set()
    try:
        with (sandbox / "runner.log").open("w") as output:
            process = subprocess.Popen(base, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        wait(lambda: list((sandbox / "build/dev").glob("*/session.json")), "six-window session")
        session_path = next((sandbox / "build/dev").glob("*/session.json"))
        directory = session_path.parent

        def session():
            value = read(session_path)
            owned.update(value.get("pids", []))
            return value

        def senses():
            return [read(directory / f"senses{owner}.json") for owner in (1, 2)]

        initial = session()
        assert initial["slots"] == ["p1", "p2"] and initial["ai_slots"] == ["ai1", "ai2"]
        assert initial["senses_slots"] == ["senses1", "senses2"] and len(initial["pids"]) == 7
        wait(lambda: all(s.get("status") == "LIVE" and s.get("readings") and s.get("olfaction_status") == "LIVE" for s in senses()), "both live sighting lists and nose samples")
        check_bound_readings(directory, initial)
        assert read(directory / "ai2.json")["paused"], "Decision window should start paused in this driver"
        if args.graphical: native_windows(sandbox, initial)
        (directory / "senses-driver.json").write_text(json.dumps({"sequence": 1}))
        wait(lambda: all(read(directory / f"driver-senses{i}.json").get("passed") for i in (1, 2)), "live UI, precision, lost readings, unavailable senses and stale recovery")
        if args.graphical:
            wait(lambda: all(s.get("metrics", {}).get("displays", 0) >= 80 for s in senses()), "steady display measurements", 30)
        else:
            samples = [s["record"]["vision"]["sample_id"] for s in senses()]
            wait(lambda: all(s["record"]["vision"]["sample_id"] >= samples[i] + 80 for i, s in enumerate(senses())), "live headless updates", 30)
            check_bound_readings(directory, initial)
        metrics = {f"senses{i + 1}": s["metrics"] for i, s in enumerate(senses())}
        for state in senses():
            assert state["metrics"]["retained"] <= 256 and state["metrics"]["clock_errors"] == 0
            if args.graphical: assert state["metrics"]["delivery_ms"]["p95"] <= 150, state["metrics"]
        # The Olfaction page has its own delivery clock: hold it and measure the 5 Hz nose samples.
        (directory / "senses-driver.json").write_text(json.dumps({"sequence": 2, "watch_olfaction": True}))
        wait(lambda: all(read(directory / f"driver-senses{i}.json").get("sequence") == 2 for i in (1, 2)), "olfaction pages selected")
        if args.graphical:
            wait(lambda: all(s.get("scent_metrics", {}).get("displays", 0) >= 60 for s in senses()), "steady olfaction display measurements", 40)
        else:
            keys = [s["scent_key"] for s in senses()]
            wait(lambda: all(s["scent_key"] != keys[i] for i, s in enumerate(senses())), "live headless nose updates", 30)
        for i, state in enumerate(senses()):
            metrics[f"senses{i + 1}_olfaction"] = state["scent_metrics"]
            assert state["scent_metrics"]["retained"] <= 256 and state["scent_metrics"]["clock_errors"] == 0
            if args.graphical: assert state["scent_metrics"]["delivery_ms"]["p95"] <= 150, state["scent_metrics"]
        costs = {f"senses{i + 1}": {k: s[k] for k in ("read_us_max", "update_us_max")} for i, s in enumerate(senses())}
        for owner in (1, 2):
            history = read(Path(initial["ai_trace_dir"]) / f"ai-{owner}.json")
            assert history["dropped_records"] == 0 and not history["writer_error"] and history["replay_status"] == "recording"
            costs[f"ai{owner}"] = {k: history[k] for k in ("publish_us", "dropped_records", "replay_bytes")}
        (sandbox / "performance.json").write_text(json.dumps({"graphical": args.graphical, "metrics": metrics if args.graphical else None, "costs": costs}, indent=2) + "\n")
        if args.graphical:
            print("Measured delivery p95: " + ", ".join(f"{slot} {m['delivery_ms']['p95']:.1f} ms" for slot, m in metrics.items()), flush=True)
        else:
            print("Headless live updates verified; rendering latency requires --graphical.", flush=True)
        (directory / "senses-driver.json").write_text(json.dumps({"sequence": 3, "capture_only": True}))
        wait(lambda: all(read(directory / f"driver-senses{i}.json").get("sequence") == 3 for i in (1, 2)), "vision pages restored")
        (directory / "driver.json").write_text(json.dumps({"sequence": 1, "capture": True, "senses": True}))
        (directory / "senses-driver.json").write_text(json.dumps({"sequence": 4, "capture_only": True}))
        wait(lambda: all(read(directory / f"driver-senses{i}.json").get("sequence") == 4 for i in (1, 2)), "live captures")
        before = read(directory / "p1.json")["tick"]
        pid = initial["senses_pids"]["senses1"]
        if args.graphical:
            windows = native_windows(sandbox, initial)
            subprocess.run(["wmctrl", "-ic", windows[pid].split()[0]], check=True)
        else:
            os.kill(pid, signal.SIGTERM)
        wait(lambda: session().get("senses_slots") == ["senses2"], "independent senses close")
        wait(lambda: read(directory / "p1.json").get("tick", 0) > before + 20, "battle after senses close")
        assert session()["ai_pids"] == initial["ai_pids"]
        visual = sandbox / "client/characters/visuals/triangle.tres"
        visual.write_text(visual.read_text() + "tint = Color(0.4, 1, 0.4, 1)\n")
        wait(lambda: session().get("visual_generation") == 1, "visual reload with one senses window closed")
        assert read(directory / "senses2.json")["visual_generation"] == 1
        script = sandbox / "client/dev/senses/vision_readings.gd"
        script.write_text(script.read_text() + "\n")
        wait(lambda: session().get("ai_run") != initial["ai_run"], "fresh content generation binding")
        current = session()
        assert current["senses_slots"] == ["senses2"] and current["closed_senses"] == ["senses1"]
        assert read(directory / "senses2.json")["run_id"] == current["ai_run"]
        (directory / "driver.json").write_text(json.dumps({"sequence": 2, "disconnect": True}))
        wait(lambda: read(directory / "p1.json").get("phase") == 0, "real round ending")
        wait(lambda: not read(directory / "senses2.json").get("record") and read(directory / "senses2.json").get("status") == "WAITING", "live readings cleared in lobby")
        process.send_signal(signal.SIGINT)
        assert process.wait(timeout=15) == 0
        for pid in owned: assert not Path(f"/proc/{pid}").exists(), f"Owned process survived: {pid}"
        previous_runs = set((sandbox / "build/dev").glob("*/session.json"))
        (sandbox / "fail-senses2").touch()
        checked(base + ["--headless", "--watch", "0", "--run-seconds", "1"], sandbox / "incomplete-launch.log")
        partial_path, = set((sandbox / "build/dev").glob("*/session.json")) - previous_runs
        partial = read(partial_path)
        assert partial["senses_slots"] == ["senses1"] and partial["closed_senses"] == ["senses2"]
        assert "Senses window launch incomplete: senses2" in (sandbox / "incomplete-launch.log").read_text()
        for log in (sandbox / "build/dev").glob("*/generation-*/*.log"):
            if log.name in ("ai1.log", "ai2.log", "senses1.log", "senses2.log", "p1.log", "p2.log", "host.log"):
                text = log.read_text()
                assert "SCRIPT ERROR:" not in text and "ERROR:" not in text, f"{log}\n{text[-2000:]}"
        mode = "six native windows and bounded rendered latency" if args.graphical else "six client/inspector roles and live headless updates"
        print(f"PASS: {mode}, private readings, olfaction page, uncertainty, loss, stale recovery, paused-brain independence, close, reload, round reset, failed launch and cleanup.", flush=True)
    finally:
        if process is not None and process.poll() is None:
            process.send_signal(signal.SIGTERM)
            process.wait(timeout=15)


if __name__ == "__main__":
    main()
