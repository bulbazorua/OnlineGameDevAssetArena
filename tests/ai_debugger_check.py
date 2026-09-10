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
    base = [sys.executable, str(sandbox / "tools/dev_session.py"), "--godot", str(wrapper), "--odin", args.odin,
            "--p1", "archer", "--p2", "archer", "--seed", "42", "--ai-debug", "1", "--audience", "1", "--audience-delay", "1"]
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
        wait(lambda: all(s.get("bound") and s.get("last_sequence", 0) > 180 for s in statuses()), "live trace histories")
        states = statuses()
        (directory / "driver.json").write_text(json.dumps({"sequence": 1, "move": True}))
        wait(lambda: read(directory / "driver-p1.json").get("sequence") == 1, "real trainer input for QA recording")
        assert all(s["reader_error"] == "" and s["nodes"] > 0 for s in states), states
        assert states[0]["worker_id"] != states[1]["worker_id"]
        trace_dir = Path(initial["ai_trace_dir"])
        for owner in (1, 2):
            snapshot = read(trace_dir / f"ai-{owner}.json")
            assert snapshot["owner_id"] == owner and snapshot["dropped_records"] == 0 and not snapshot["writer_error"]
            for record in snapshot["records"]:
                assert record["owner_id"] == owner and record["input"]["entity_id"] == record["after"]["entity_id"]
                assert record["nodes"][0]["thread_id"] == record["worker_id"]
                assert record["nodes"][-1]["stage"] == "Outcome"
                assert record["nodes"][-1]["thread_id"] != record["worker_id"], "Action applied on AI worker"
        if args.graphical:
            windows = subprocess.check_output(["wmctrl", "-lp"], text=True)
            (sandbox / "native-windows.txt").write_text(windows)
            for state in states:
                assert any(int(line.split()[2]) == state["pid"] and "AI DEBUG" in line for line in windows.splitlines())
        (directory / "ai-driver.json").write_text(json.dumps({"sequence": 1}))
        wait(lambda: all(read(directory / f"driver-ai{i}.json").get("passed") for i in (1, 2)), "tree stepping, pinned playback, filters, journal replay")
        checked([args.godot, "--headless", "--path", str(Path(initial["active"]) / "client"), "--script", str(ROOT / "tests/ai_trace_check.gd"),
                 "--", f"--fixture={trace_dir / 'ai-1.json'}"], sandbox / "reader-check.log")
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
        checked(playback + ["--", "--dev", f"--replay={initial['replay_path']}", f"--artifacts={sandbox}"], sandbox / "replay-check.log", timeout=90)
        checked(base + ["--ai-debug", "0", "--watch", "0", "--run-seconds", "1"], sandbox / "disabled.log")
        disabled = [read(p) for p in (sandbox / "build/dev").glob("*/session.json") if read(p).get("scenario", {}).get("ai_debug") == 0]
        assert len(disabled) == 1 and disabled[0]["ai_slots"] == [] and not Path(disabled[0]["ai_trace_dir"]).exists()
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
            if log.name in ("ai1.log", "ai2.log", "p1.log", "p2.log", "host.log", "audience1.log"):
                text = log.read_text()
                assert "SCRIPT ERROR:" not in text and "ERROR:" not in text, f"{log}\n{text[-2000:]}"
        print("PASS: dedicated threads, actual branches, responsive inspectors, downward graphs, recorded match playback, bounded logs, optional close, incomplete launch reporting, reload, audience isolation, release gate and cleanup.", flush=True)
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
