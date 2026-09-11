#!/usr/bin/env python3
"""Real dedicated workers, two Godot inspectors, replay, reload and isolation."""
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

ROOT = Path(__file__).resolve().parents[1]


def read(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except (ValueError, OSError):
        return {}


def wait(condition, message: str, timeout: float = 60):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(0.1)
    raise AssertionError(f"Timed out: {message}")


def leaks_host_fields(value) -> bool:
    """Brain-side data must never carry host audit fields, even as attachments."""
    if isinstance(value, dict):
        return any(key in ("verdict", "candidates", "host_audit", "sight_tests", "origin_opaque", "host_scent_audit", "cells_sampled", "cells_blind", "cells_excluded", "peak", "coherence", "newest_age_ticks", "newest_detectable_age_ticks") or leaks_host_fields(item) for key, item in value.items())
    if isinstance(value, list):
        return any(leaks_host_fields(item) for item in value)
    return False


def journal_lines(traces: Path, owner: int) -> list[bytes]:
    """Every complete serialized record line for one creature, oldest first, across rotated segments."""
    lines = []
    for name in (f"ai-{owner}.jsonl.3", f"ai-{owner}.jsonl.2", f"ai-{owner}.jsonl.1", f"ai-{owner}.jsonl"):
        path = traces / name
        if path.exists():
            lines.extend(line for line in path.read_bytes().split(b"\n") if line.endswith(b"}"))
    return lines


def journal_records(traces: Path, owner: int) -> list[dict]:
    """Every complete decision for one creature, oldest first, across rotated segments."""
    return [json.loads(line) for line in journal_lines(traces, owner)]


def checked(command: list[str], log: Path, timeout: int = 60):
    with log.open("w") as output:
        result = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
    text = log.read_text()
    assert result.returncode == 0 and "SCRIPT ERROR:" not in text and "ERROR:" not in text, f"{log}\n{text[-3000:]}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--odin", default="odin")
    parser.add_argument("--graphical", action="store_true")
    args = parser.parse_args()
    sandbox = ROOT / "build/verification" / f"ai-debugger-{time.strftime('%Y%m%d-%H%M%S')}-{os.getpid()}"
    sandbox.mkdir(parents=True)
    print(f"AI debugger verification artifacts: {sandbox}", flush=True)
    for name in ("client", "server", "tools", "tests"):
        shutil.copytree(ROOT / name, sandbox / name, ignore=shutil.ignore_patterns(".godot", "__pycache__"))
    (sandbox / "build/deps").mkdir(parents=True)
    shutil.copy2(ROOT / "build/deps/libenet.a", sandbox / "build/deps/libenet.a")
    wrapper = sandbox / "godot-driver"
    wrapper.write_text("#!/usr/bin/env python3\nimport os, sys\nargs = sys.argv[1:]\n"
                       "if '--ai-debug' in args and '--ai-owner=2' in args and os.path.exists(" + repr(str(sandbox / "fail-ai2")) + "):\n    sys.exit(7)\n"
                       "if '--ai-debug' in args:\n"
                       "    args = [a for a in args if a != 'res://dev/ai/ai_debug_window.tscn']\n"
                       "    args = ['--script', " + repr(str(sandbox / "tests/ai_debugger_driver.gd")) + "] + args\n"
                       "elif any(a.startswith('--dev-slot=p') for a in args):\n"
                       "    args = ['--script', " + repr(str(sandbox / "tests/dev_client_driver.gd")) + "] + args\n"
                       "os.execvp(" + repr(args.godot) + ", [" + repr(args.godot) + "] + args)\n")
    wrapper.chmod(0o755)
    # Same-definition creatures on the staged close-quarters QA arena, so real
    # peripheral cues, focused sightings and memory flow through production sensing.
    base = [sys.executable, str(sandbox / "tools/dev_session.py"), "--godot", str(wrapper), "--odin", args.odin,
            "--p1", "archer", "--p2", "archer", "--seed", "42", "--ai-debug", "1", "--observe-only", "--audience", "1", "--audience-delay", "1",
            "--arena", "vision_range", "--qa-arena", "client/dev/fixtures/content/vision_range.arenas.json"]
    if not args.graphical:
        base.append("--headless")
    process = None
    owned: set[int] = set()
    try:
        with (sandbox / "runner.log").open("w") as output:
            process = subprocess.Popen(base, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        wait(lambda: list((sandbox / "build/dev").glob("*/session.json")), "two clients, audience and debuggers ready")
        session_path = next((sandbox / "build/dev").glob("*/session.json"))
        directory = session_path.parent

        def session():
            value = read(session_path)
            owned.update(value.get("pids", []))
            return value

        def statuses():
            return [read(directory / f"ai{i}.json") for i in (1, 2)]

        initial = session()
        assert initial["ai_slots"] == ["ai1", "ai2"], (initial, (sandbox / "runner.log").read_text())
        assert initial["senses_slots"] == ["senses1", "senses2"]
        wait(lambda: all(s.get("bound") and s.get("last_sequence", 0) > 180 for s in statuses()), "live trace histories")
        states = statuses()
        # Both creatures noticed each other at the edge of vision, turned one step
        # toward the cue and now hold with the other in focus; nobody translated.
        p1 = read(directory / "p1.json")
        wait(lambda: all(read(directory / f"p{i}.json").get("senses", {}).get("visible") for i in (1, 2)), "live vision cones in both arenas")
        assert not read(directory / "audience1.json")["senses"]["visible"], "Audience borrowed live sensory evidence"
        assert sorted(c["facing"] for c in p1["characters"]) == [3, 7], p1["characters"]
        assert all(c["locomotion"] == 0 for c in p1["characters"]), p1["characters"]
        (directory / "driver.json").write_text(json.dumps({"sequence": 1, "move": True}))
        wait(lambda: read(directory / "driver-p1.json").get("sequence") == 1, "real trainer input for QA recording")
        assert all(s["reader_error"] == "" and s["nodes"] > 0 for s in states), states
        # P1 follows live decisions; P2's driver paused before its first decision and must show that decision, not nothing.
        assert not states[0]["paused"] and states[0]["selected_sequence"] == states[0]["last_sequence"], states[0]
        assert states[1]["paused"] and states[1]["selected_sequence"] >= 1 and states[1]["last_sequence"] > states[1]["selected_sequence"], states[1]
        assert states[0]["worker_id"] != states[1]["worker_id"]
        trace_dir = Path(initial["ai_trace_dir"])
        sensory = read(trace_dir / "senses.json")
        assert sensory["run_id"] == initial["ai_run"] and len(sensory["records"]) == 2
        assert (trace_dir / "senses.json").stat().st_size <= 32 * 1024
        for record in sensory["records"]:
            assert set(record) == {"owner_id", "entity_id", "round_id", "tick", "definition_id", "map_id", "delivered_us", "vision", "sight_fan", "scent_delivered_us", "olfaction", "own_emitter"}
            matching = [r for r in journal_records(trace_dir, record["owner_id"]) if r["input"]["tick"] == record["tick"]]
            assert matching and record["vision"] == matching[-1]["input"]["senses"]["vision"]
            assert record["olfaction"] == matching[-1]["input"]["senses"]["olfaction"], "Arena nose sample differs from debugger evidence"
            assert record["sight_fan"] == matching[-1]["sight_fan"], "Arena fan differs from debugger evidence"
        for owner in (1, 2):
            snapshot = read(trace_dir / f"ai-{owner}.json")
            assert snapshot["schema_version"] == 5 and snapshot["owner_id"] == owner and snapshot["dropped_records"] == 0 and snapshot["oversized_records"] == 0 and not snapshot["writer_error"]
            reasons = set()
            for record in snapshot["records"]:
                assert record["schema_version"] == 5 and record["owner_id"] == owner and record["input"]["entity_id"] == record["after"]["entity_id"]
                assert record["nodes"][0]["thread_id"] == record["worker_id"]
                assert record["nodes"][-1]["stage"] == "Outcome"
                assert record["nodes"][-1]["thread_id"] != record["worker_id"], "Action applied on AI worker"
                sample = record["input"]["senses"]["vision"]
                assert sample["observer"] == record["input"]["entity_id"] and sample["sample_tick"] <= record["input"]["tick"]
                assert not leaks_host_fields(record["input"]) and not leaks_host_fields(record["before"]) and not leaks_host_fields(record["after"]), "host audit reached brain-side data"
                for index in range(sample["cue_count"]):
                    assert set(sample["cues"][index]) == {"observation_id", "sector", "band"}, sample["cues"][index]
                reasons.add(record["decision_reason"])
            # Journals rotate at 8 MiB, so the first decisions may already sit in an older segment.
            # Every serialized record line, as written, must fit the advertised ceiling.
            lines = journal_lines(trace_dir, owner)
            assert lines and max(len(line) for line in lines) <= snapshot["record_limit_bytes"], max(len(line) for line in lines)
            journal = [json.loads(line) for line in lines]
            observed = [r for r in journal if r["decision_reason"] == "Observe"]
            assert observed and observed[0]["input"]["senses"]["vision"]["focused_count"] >= 1, reasons
            oriented = [r for r in journal if r["decision_reason"] == "Orient"]
            assert oriented and oriented[0]["input"]["senses"]["vision"]["cue_count"] == 1 and oriented[0]["result"]["kind"] == "Turned", reasons
        if args.graphical:
            (directory / "driver.json").write_text(json.dumps({"sequence": 2, "capture": True, "senses": True}))
            wait(lambda: all(read(directory / f"driver-p{i}.json").get("sequence") == 2 for i in (1, 2)), "native arena cone captures")
            windows = subprocess.check_output(["wmctrl", "-lp"], text=True)
            (sandbox / "native-windows.txt").write_text(windows)
            for state in states:
                assert any(int(line.split()[2]) == state["pid"] and "AI DEBUG" in line for line in windows.splitlines())
        (directory / "ai-driver.json").write_text(json.dumps({"sequence": 1}))
        wait(lambda: all(read(directory / f"driver-ai{i}.json").get("passed") for i in (1, 2)), "tree stepping, pinned playback, filters, journal replay")
        assert not read(directory / "driver-ai1.json")["early_pause"] and read(directory / "driver-ai2.json")["early_pause"]
        checked([args.godot, "--headless", "--path", str(Path(initial["active"]) / "client"), "--script", str(ROOT / "tests/ai_trace_check.gd"),
                 "--", f"--fixture={trace_dir / 'ai-1.json'}", f"--legacy={ROOT / 'tests/fixtures/ai/legacy-schema1-snapshot.json'}"], sandbox / "reader-check.log")
        for owner in (1, 2):
            driver = read(directory / f"driver-ai{owner}.json")
            assert driver["decision_reason"] in ("Orient", "Observe") and driver["sample_tick"] <= driver["decision_tick"], driver
        before = read(directory / "p1.json")["tick"]
        # Close just one native inspector, or its process in headless mode.
        if args.graphical:
            windows = subprocess.check_output(["wmctrl", "-lp"], text=True)
            window = next(line.split()[0] for line in windows.splitlines() if int(line.split()[2]) == states[0]["pid"] and "AI DEBUG" in line)
            subprocess.run(["wmctrl", "-ic", window], check=True)
        else:
            os.kill(states[0]["pid"], signal.SIGTERM)
        wait(lambda: session().get("ai_slots") == ["ai2"], "optional debugger close")
        wait(lambda: read(directory / "p1.json").get("tick", 0) > before + 15, "game continues after inspector close")
        assert read(directory / "p1.json")["audience"] == 1
        assert read(directory / "audience1.json")["audience_delay_ms"] == 1000
        visual = sandbox / "client/characters/visuals/triangle.tres"
        visual.write_text(visual.read_text() + "tint = Color(0.4, 1, 0.4, 1)\n")
        wait(lambda: session().get("visual_generation") == 1, "visual reload without closed debugger acknowledgment")
        assert read(directory / "ai2.json")["visual_generation"] == 1
        old = session()
        script = sandbox / "server/ai/trace.odin"
        script.write_text(script.read_text() + "\n// Debugger reload integration fixture.\n")
        wait(lambda: session().get("ai_run") != old["ai_run"], "code relaunch with fresh trace identity")
        current = session()
        assert current["ai_slots"] == ["ai2"] and current["closed_ai"] == ["ai1"]
        assert read(directory / "ai2.json")["run_id"] == current["ai_run"]
        process.send_signal(signal.SIGINT)
        assert process.wait(timeout=15) == 0
        # The host receives SIGTERM, drains journals, publishes, then joins workers.
        for owner in (1, 2):
            journal = Path(current["ai_trace_dir"]) / f"ai-{owner}.jsonl"
            lines = journal.read_text().splitlines()
            assert lines and all(json.loads(line)["owner_id"] == owner for line in lines)
        for pid in owned:
            assert not Path(f"/proc/{pid}").exists(), f"Owned process survived cleanup: {pid}"
        playback = [args.godot, "--path", str(Path(initial["active"]) / "client"), "--script", str(ROOT / "tests/replay_check.gd")]
        if not args.graphical:
            playback.append("--headless")
        checked(playback + ["--", "--dev", f"--replay={initial['replay_path']}", f"--artifacts={sandbox}", f"--legacy={ROOT / 'tests/fixtures/ai/legacy-schema1-replay.jsonl'}"], sandbox / "replay-check.log", timeout=90)
        checked(base + ["--ai-debug", "0", "--watch", "0", "--run-seconds", "1"], sandbox / "disabled.log")
        disabled = [read(p) for p in (sandbox / "build/dev").glob("*/session.json") if read(p).get("scenario", {}).get("ai_debug") == 0]
        assert len(disabled) == 1 and disabled[0]["ai_slots"] == [] and disabled[0]["senses_slots"] == [] and not Path(disabled[0]["ai_trace_dir"]).exists()
        # An inspector that exits before its first frame must be reported as an
        # incomplete debug launch, while the required game processes still run.
        previous_runs = set((sandbox / "build/dev").glob("*/session.json"))
        (sandbox / "fail-ai2").touch()
        checked(base + ["--watch", "0", "--run-seconds", "1"], sandbox / "incomplete-launch.log")
        assert "AI debugger launch incomplete: ai2" in (sandbox / "incomplete-launch.log").read_text()
        partial_path, = set((sandbox / "build/dev").glob("*/session.json")) - previous_runs
        partial = read(partial_path)
        assert partial["ai_slots"] == ["ai1"] and partial["closed_ai"] == ["ai2"]
        assert read(partial_path.parent / "p1.json")["tick"] > 90
        assert all(not Path(f"/proc/{pid}").exists() for pid in partial["pids"])
        (sandbox / "fail-ai2").unlink()
        checked([args.odin, "build", str(ROOT / "server"), f"-out:{sandbox / 'host-release'}", "-o:speed", f"-extra-linker-flags:-L{ROOT / 'build/deps'}"], sandbox / "release-build.log")
        rejected = subprocess.run([str(sandbox / "host-release"), "--dev", f"--dev-ai-dir={sandbox / 'forbidden'}", "--dev-ai-run=test"], cwd=ROOT, capture_output=True, text=True, timeout=5)
        assert rejected.returncode != 0 and "debug host build" in rejected.stderr and not (sandbox / "forbidden").exists()
        for log in (sandbox / "build/dev").glob("*/generation-*/*.log"):
            if log.name in ("ai1.log", "ai2.log", "senses1.log", "senses2.log", "p1.log", "p2.log", "host.log", "audience1.log"):
                text = log.read_text()
                assert "SCRIPT ERROR:" not in text and "ERROR:" not in text, f"{log}\n{text[-2000:]}"
        print("PASS: dedicated threads, real peripheral/focused evidence, brain-side isolation, responsive inspectors, downward graphs, recorded match playback with retained samples, bounded logs, optional close, incomplete launch reporting, reload, audience isolation, release gate and cleanup.", flush=True)
    finally:
        if process is not None and process.poll() is None:
            process.send_signal(signal.SIGTERM)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()


if __name__ == "__main__":
    main()
