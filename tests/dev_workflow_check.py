#!/usr/bin/env python3
"""Exercise real host/client processes and saves in an isolated source copy."""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


def wait(condition, description, timeout=45):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(0.1)
    raise AssertionError(f"Timed out: {description}")


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--odin", default="odin")
    parser.add_argument("--graphical", action="store_true")
    args = parser.parse_args()
    sandbox = ROOT / "build/verification" / f"dev-check-{time.strftime('%Y%m%d-%H%M%S')}-{os.getpid()}"
    sandbox.mkdir(parents=True)
    for name in ("client", "server", "tools", "tests"):
        shutil.copytree(ROOT / name, sandbox / name, ignore=shutil.ignore_patterns(".godot", "__pycache__"))
    (sandbox / "build/deps").mkdir(parents=True)
    shutil.copy2(ROOT / "build/deps/libenet.a", sandbox / "build/deps/libenet.a")
    wrapper = sandbox / "godot-driver"
    wrapper.write_text("#!/usr/bin/env python3\nimport os, sys\nargs = sys.argv[1:]\n"
                       "if '--dev' in args and '--ai-debug' not in args and '--senses-debug' not in args:\n    args = ['--script', " + repr(str(sandbox / "tests/dev_client_driver.gd")) + "] + args\n"
                       "os.execvp(" + repr(args.godot) + ", [" + repr(args.godot) + "] + args)\n")
    wrapper.chmod(0o755)
    base = [sys.executable, str(sandbox / "tools/dev_session.py"), "--godot", str(wrapper), "--odin", args.odin, "--audience-delay", "0", "--seed", "42"]
    if not args.graphical:
        base.append("--headless")
    bad = subprocess.run(base + ["--p1", "not_a_character"], capture_output=True, text=True)
    assert bad.returncode != 0 and "circle, square, triangle, diamond" in bad.stderr
    for value in ("-1", "60.001", "nan", "inf"):
        invalid = subprocess.run(base + ["--audience-delay", value], capture_output=True, text=True)
        assert invalid.returncode != 0 and "AUDIENCE_DELAY" in invalid.stderr
        invalid_host = subprocess.run([str(ROOT / "build/server"), f"--audience-delay={value}"], capture_output=True, text=True)
        assert invalid_host.returncode != 0 and "audience-delay" in invalid_host.stderr
    assert not (sandbox / "build/dev").exists(), "Invalid choices started a session"
    for seed in ("-1", "4294967296", "nan"):
        invalid = subprocess.run(base + ["--seed", seed], capture_output=True, text=True)
        assert invalid.returncode != 0
    owned = set()
    process = None
    probe = None
    try:
        # An unrelated host must survive reloads and Ctrl+C cleanup.
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
            reservation.bind(("127.0.0.1", 0))
            probe_port = reservation.getsockname()[1]
        with (sandbox / "unrelated-host.log").open("w") as output:
            probe = subprocess.Popen([str(ROOT / "build/server"), "--bind=127.0.0.1", f"--port={probe_port}"], cwd=ROOT,
                                     stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        wait(lambda: "Listening" in (sandbox / "unrelated-host.log").read_text(), "unrelated host startup", 5)
        with (sandbox / "runner.log").open("w") as output:
            process = subprocess.Popen(base + ["--p1", "triangle", "--p2", "diamond", "--arena", "sandbar", "--audience", "1"],
                                       stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        wait(lambda: list((sandbox / "build/dev").glob("*/session.json")), "initial session")
        session_path = next((sandbox / "build/dev").glob("*/session.json"))
        directory = session_path.parent
        print(f"Development check logs: {sandbox}", flush=True)

        def session():
            value = read(session_path)
            owned.update(value.get("pids", []))
            return value

        def statuses():
            return [read(directory / f"{slot}.json") for slot in ("p1", "p2", "audience1")]

        def command(sequence, move=False):
            (directory / "driver.json").write_text(json.dumps({"sequence": sequence, "move": move, "capture": args.graphical}))
            wait(lambda: all(read(directory / f"driver-{slot}.json").get("sequence") == sequence for slot in ("p1", "p2", "audience1")), "input/render driver")
            time.sleep(0.3)

        initial = session()
        spawn_y = statuses()[0]["trainers"][0]["y"]
        assert [s["player_id"] for s in statuses()] == [1, 2, 0]
        assert all(s["phase"] == 3 and s["map"] == 2 and s["camera_enabled"] for s in statuses())
        assert all([c["definition"] for c in s["characters"]] == [3, 4] for s in statuses())
        command(1, move=True)
        before = statuses()
        assert all(s["trainers"][0]["y"] > spawn_y + 15 for s in before), "Movement not replicated"
        position = before[0]["trainers"][0]["y"]
        visual = sandbox / "client/characters/visuals/triangle.tres"
        visual.write_text(visual.read_text() + "tint = Color(0.4, 1, 0.4, 1)\n")
        wait(lambda: session().get("visual_generation") == 1, "visual hot reload")
        after = statuses()
        assert session()["pids"] == initial["pids"], "Visual reload restarted processes"
        assert all(s["visuals"]["3"]["tint"] == "66ff66ff" for s in after)
        assert all(s["round"] == before[0]["round"] and abs(s["trainers"][0]["y"] - position) < 0.01 for s in after)
        assert after[0]["sequence"] > before[0]["sequence"]
        command(2, move=True)
        assert all(s["trainers"][0]["y"] > position + 15 for s in statuses()), "Movement failed after live reload"
        old_texture = read(directory / "driver-p1.json")["texture_hash"]
        visual.write_text(visual.read_text().replace("tint = Color(0.4, 1, 0.4, 1)\n", ""))
        wait(lambda: session().get("visual_generation") == 2, "default visual property reload")
        assert all(s["visuals"]["3"]["tint"] == "ffffffff" for s in statuses()), "Removed property did not reset to its default"
        # A different existing tilesheet is an import/cache fixture, not new art.
        shutil.copyfile(sandbox / "client/assets/ninja_adventure/TilesetNature.png", sandbox / "client/assets/ninja_adventure/TilesetFloor.png")
        wait(lambda: session().get("visual_generation") == 3, "texture import hot reload")
        command(3)
        assert session()["pids"] == initial["pids"]
        assert all(read(directory / f"driver-{slot}.json")["texture_width"] == 384 for slot in ("p1", "p2", "audience1")), "Bound terrain texture did not reload"
        # Godot's dummy headless renderer leaves texture_replace pixel storage
        # unchanged. OpenGL mode verifies actual uploaded pixels as well.
        if args.graphical:
            assert all(read(directory / f"driver-{slot}.json")["texture_hash"] != old_texture for slot in ("p1", "p2", "audience1")), "Live terrain pixels did not refresh"

        # Failed resources, compile, and content validation all retain the match.
        for path, invalid in [(visual, "invalid resource"), (sandbox / "server/simulation/movement.odin", "not valid Odin"),
                              (sandbox / "client/world/game_arena.gd", "not valid GDScript"),
                              (sandbox / "client/content/data/arenas.json", "{bad json")]:
            original = path.read_text()
            previous_logs = (sandbox / "runner.log").read_text().count("Keeping the working session")
            path.write_text(invalid)
            wait(lambda: (sandbox / "runner.log").read_text().count("Keeping the working session") > previous_logs, "reject invalid save")
            assert session()["pids"] == initial["pids"] and all(alive(pid) for pid in initial["pids"])
            path.write_text(original)
            time.sleep(1)

        # Real Odin logic edit -> fresh processes and same scenario/roles.
        movement = sandbox / "server/simulation/movement.odin"
        source = movement.read_text()
        assert "CHARACTER_SPEED :: f32(120)" in source
        movement.write_text(source.replace("CHARACTER_SPEED :: f32(120)", "CHARACTER_SPEED :: f32(90)", 1))
        wait(lambda: session().get("pids") != initial["pids"], "Odin rebuild/relaunch")
        second = session()
        assert all(not alive(pid) for pid in initial["pids"])
        assert all(s["map"] == 2 and [c["definition"] for c in s["characters"]] == [3, 4] for s in statuses())
        assert all(s["trainers"][0]["y"] == spawn_y for s in statuses())

        # Shared JSON changes are accepted by both content readers before restart.
        characters = sandbox / "client/content/data/characters.json"
        data = json.loads(characters.read_text())
        old_fingerprint = statuses()[0]["fingerprint"]
        data["characters"][2]["display_name"] = "Development Triangle"
        characters.write_text(json.dumps(data))
        wait(lambda: session().get("pids") != second["pids"], "shared data reload")
        assert len({s["fingerprint"] for s in statuses()}) == 1 and statuses()[0]["fingerprint"] != old_fingerprint
        third = session()
        # A nested pure-AI package edit must rebuild/relaunch with the same seed.
        observe = sandbox / "server/ai/observe.odin"
        observe.write_text(observe.read_text().replace("return {{180, 30}, 30, 1}", "return {{180, 30}, 24, 1}"))
        wait(lambda: session().get("pids") != third["pids"], "nested AI source reload")
        assert session()["scenario"]["seed"] == 42
        third = session()
        script = sandbox / "client/world/game_arena.gd"
        script.write_text(script.read_text().replace('"Arena sandbox"', '"Reloaded arena sandbox"'))
        wait(lambda: session().get("pids") != third["pids"], "client code relaunch")
        assert probe.poll() is None, "Unrelated host was stopped"
        process.send_signal(signal.SIGINT)
        assert process.wait(timeout=12) == 0
        wait(lambda: all(not alive(pid) for pid in owned), "owned process cleanup")
        assert probe.poll() is None

        # Mirrors, another map and the real countdown; no watcher required.
        result = subprocess.run(base + ["--p1", "circle", "--p2", "circle", "--arena", "stone_garden", "--countdown", "5",
                                       "--watch", "0", "--run-seconds", "1", "--audience", "1", "--audience-delay", "1.25"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60)
        assert result.returncode == 0, result.stdout
        fractional_checked = False
        for path in (sandbox / "build/dev").glob("*/session.json"):
            saved = read(path)
            assert all(not alive(pid) for pid in saved["pids"])
            if saved["scenario"]["audience_delay"] == 1.25:
                fractional_checked = True
                assert read(path.parent / "audience1.json")["audience_delay_ms"] == 1250
                assert read(path.parent / "p1.json")["audience_delay_ms"] == 0
        assert fractional_checked, "Nondefault delay did not reach the launched host/client"
        print("PASS: roles, audience, cameras, countdown, movement, live visual/texture reload, failed saves, code/data relaunch, isolation and cleanup.")
    finally:
        if process is not None and process.poll() is None:
            process.send_signal(signal.SIGTERM)
            process.wait(timeout=15)
        if probe is not None:
            probe.terminate()
            probe.wait(timeout=5)


if __name__ == "__main__":
    main()
