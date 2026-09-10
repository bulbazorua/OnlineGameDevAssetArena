#!/usr/bin/env python3
"""Own one repeatable local arena session; publish only validated builds."""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
IMAGE_TYPES = {".png", ".jpg", ".jpeg", ".webp", ".svg"}


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


def write_json(path: Path, value: dict) -> None:
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def validate_choices(root: Path, args: argparse.Namespace) -> None:
    data = root / "client/content/data"
    characters = [entry["key"] for entry in json.loads((data / "characters.json").read_text())["characters"]]
    arenas = [entry["key"] for entry in json.loads((data / "arenas.json").read_text())["arenas"]]
    for name, value, choices in [("P1", args.p1, characters), ("P2", args.p2, characters), ("ARENA", args.arena, arenas)]:
        if value not in choices:
            raise ValueError(f"Unknown {name}={value!r}. Available: {', '.join(choices)}")


def source_snapshot(root: Path) -> dict[str, str]:
    result = {}
    for directory in ("client", "server"):
        for path in sorted((root / directory).rglob("*")):
            if not path.is_file() or ".godot" in path.parts or path.suffix in {".tmp", ".swp", ".bak"}:
                continue
            result[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def live_visual_paths(changed: set[str], candidate: Path) -> list[str] | None:
    """Only known presentation resources; scripts/scenes/data use a fresh run."""
    resources = set()
    for relative in changed:
        path = Path(relative)
        if relative.startswith(("client/assets/Characters/", "client/characters/packages/", "client/generated/characters/", "client/players/packages/", "client/generated/players/")):
            return None  # Rebuild normalized art and reopen with a coherent bundle.
        if not (candidate / path).is_file():
            return None  # Deletions need a fresh resource cache.
        if path.suffix == ".import":
            path = path.with_suffix("")
        is_visual = path.parent.as_posix() == "client/characters/visuals" and path.suffix == ".tres"
        is_image = path.parts[0] == "client" and path.suffix.lower() in IMAGE_TYPES
        if not (is_visual or is_image):
            return None
        resources.add("res://" + path.relative_to("client").as_posix())
    return sorted(resources) or None


class DevSessionRunner:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.directory = ROOT / "build/dev" / f"{time.strftime('%Y%m%d-%H%M%S')}-{os.getpid()}"
        self.directory.mkdir(parents=True)
        self.children: list[subprocess.Popen] = []
        self.active: Path | None = None
        self.generation = 0
        self.visual_generation = 0
        self.port = 0
        self.slots = ["p1", "p2"] + [f"audience{i + 1}" for i in range(args.audience)]
        self.active_sources: dict[str, str] = {}
        self.deadline = float("inf")
        self.log(f"Logs and status: {self.directory}")

    @staticmethod
    def log(message: str) -> None:
        print(f"[dev] {message}", flush=True)

    def spawn(self, command: list[str], log: Path, cwd: Path = ROOT) -> subprocess.Popen:
        with log.open("w") as stream:
            process = subprocess.Popen(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        self.children.append(process)
        return process

    @staticmethod
    def stop(process: subprocess.Popen) -> None:
        # Every child owns a new process group; never search for/kill other hosts.
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                process.wait()
                return
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()

    def stop_session(self) -> None:
        for process in reversed(self.children):
            self.stop(process)
        self.children.clear()

    def checked(self, command: list[str], log: Path, cwd: Path = ROOT) -> None:
        process = self.spawn(command, log, cwd)
        try:
            code = process.wait(timeout=120)
        except subprocess.TimeoutExpired:
            self.stop(process)
            raise RuntimeError(f"Build/import timed out. See {log}") from None
        except BaseException:
            self.stop(process)
            raise
        finally:
            self.children.remove(process)
        output = log.read_text(errors="replace")
        # Godot can exit zero after a script/import error.
        if code or "SCRIPT ERROR:" in output or "ERROR:" in output:
            raise RuntimeError(f"Validation failed. See {log}\n{output[-3500:]}")

    def scenario_arguments(self, candidate: Path) -> list[str]:
        return ["--dev", "--bind=127.0.0.1", f"--dev-p1={self.args.p1}", f"--dev-p2={self.args.p2}",
                f"--audience-delay={self.args.audience_delay}", f"--seed={self.args.seed}", f"--dev-arena={self.args.arena}", f"--dev-countdown={self.args.countdown}",
                f"--content-dir={candidate / 'client/content/data'}"]

    def prepare(self, sources: dict[str, str]) -> Path:
        self.generation += 1
        candidate = self.directory / f"generation-{self.generation}"
        candidate.mkdir()
        # Running clients read a private snapshot, so half-saved JSON or imports
        # in the working tree cannot leak into an active match.
        for relative in sources:
            destination = candidate / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, destination)
        if source_snapshot(candidate) != sources:
            raise RuntimeError("Files changed while staging; waiting for the next stable save.")
        validate_choices(candidate, self.args)
        for name in ("process_character_assets.py", "prepare_characters.py"):
            destination = candidate / "tools" / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / "tools" / name, destination)
        self.checked([sys.executable, str(candidate / "tools/prepare_characters.py"), "--godot", self.args.godot], candidate / "characters.log")
        self.checked([sys.executable, str(candidate / "tools/prepare_characters.py"), "--godot", self.args.godot, "--family=players"], candidate / "players.log")
        server_changed = self.active is None or any(
            sources.get(path) != self.active_sources.get(path)
            for path in sources.keys() | self.active_sources.keys() if path.startswith("server/"))
        if server_changed:
            self.checked([self.args.odin, "build", str(candidate / "server"), f"-out:{candidate / 'host'}", "-debug",
                          f"-extra-linker-flags:-L{ROOT / 'build/deps'}"], candidate / "build.log")
        else:
            shutil.copy2(self.active / "host", candidate / "host")
        self.checked([str(candidate / "host"), *self.scenario_arguments(candidate), "--dev-validate-only"], candidate / "host-validation.log")
        client = candidate / "client"
        self.checked([self.args.godot, "--headless", "--path", str(client), "--editor", "--import"], candidate / "import.log")
        self.checked([self.args.godot, "--headless", "--path", str(client), "--script", "res://dev/validate_project.gd"], candidate / "client-validation.log")
        return candidate

    def wait_for(self, predicate, seconds: float, description: str) -> None:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            self.check_processes()
            if predicate():
                return
            time.sleep(0.05)
        raise RuntimeError(f"Timed out waiting for {description}. See {self.directory}")

    def check_processes(self) -> None:
        for process in self.children:
            if process.poll() is not None:
                raise RuntimeError(f"Owned process {process.pid} exited ({process.returncode}); stopping this session.")

    def status(self, slot: str) -> dict:
        return read_json(self.directory / f"{slot}.json")

    def start_session(self, candidate: Path) -> None:
        # Select an isolated port instead of interfering with make run_server.
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
            reservation.bind(("127.0.0.1", 0))
            self.port = reservation.getsockname()[1]
        for name in ["reload", *self.slots]:
            (self.directory / f"{name}.json").unlink(missing_ok=True)
        self.visual_generation = 0
        self.spawn([str(candidate / "host"), *self.scenario_arguments(candidate), f"--port={self.port}"], candidate / "host.log")
        self.wait_for(lambda: "Listening" in (candidate / "host.log").read_text(), 10, "host startup")
        for index, slot in enumerate(self.slots):
            command = [self.args.godot, "--path", str(candidate / "client")]
            if self.args.headless:
                command += ["--headless", "--max-fps", "120"]
            command += ["--", "--dev", "--host=127.0.0.1", f"--port={self.port}",
                        f"--dev-session-dir={self.directory}", f"--dev-slot={slot}"]
            if index >= 2:
                command += ["--audience"]
            self.spawn(command, candidate / f"{slot}.log")
            expected = index + 1 if index < 2 else 0
            self.wait_for(lambda s=slot, role=expected: self.status(s).get("connected") and self.status(s).get("player_id") == role,
                          15, f"{slot} Welcome/role {expected}")
        self.wait_for(lambda: all(self.status(slot).get("phase") == 3 and self.status(slot).get("summon_elapsed_ticks") == 90 and self.status(slot).get("audience") == self.args.audience
                                  for slot in self.slots), 10 + self.args.countdown + self.args.audience_delay, "arena snapshots in all windows")
        self.active = candidate
        self.publish_session()
        self.log(f"Arena ready: {self.args.p1} vs {self.args.p2}, {self.args.arena}, {self.args.audience} audience, {self.args.audience_delay:g}s audience delay, AI seed {self.args.seed} (port {self.port}).")

    def publish_session(self) -> None:
        write_json(self.directory / "session.json", {"scenario": vars(self.args), "active": str(self.active),
                   "port": self.port, "pids": [process.pid for process in self.children], "slots": self.slots,
                   "visual_generation": self.visual_generation})

    def apply_visuals(self, candidate: Path, resources: list[str], changed: set[str]) -> None:
        # Copy completed imports and their metadata before notifying ANY window.
        paths = [candidate / relative for relative in changed]
        paths += list((candidate / "client/.godot/imported").glob("*"))
        for resource in resources:
            import_file = candidate / "client" / (resource.removeprefix("res://") + ".import")
            if import_file.exists():
                paths.append(import_file)
        for source in paths:
            if not source.is_file():
                continue
            destination = self.active / source.relative_to(candidate)
            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary = destination.with_name(destination.name + ".dev-tmp")
            shutil.copy2(source, temporary)
            temporary.replace(destination)
        self.visual_generation += 1
        write_json(self.directory / "reload.json", {"generation": self.visual_generation, "paths": resources})
        self.wait_for(lambda: all(self.status(slot).get("visual_generation") == self.visual_generation for slot in self.slots),
                      10, "visual reload acknowledgments")
        errors = [self.status(slot).get("reload_error") for slot in self.slots if self.status(slot).get("reload_error")]
        if errors:
            raise RuntimeError("; ".join(errors))
        self.publish_session()
        self.log(f"Visuals reloaded in all {len(self.slots)} windows; match and connections preserved.")

    def reload(self, sources: dict[str, str]) -> None:
        changed = {path for path in sources.keys() | self.active_sources.keys() if sources.get(path) != self.active_sources.get(path)}
        if not changed:
            self.log("Sources restored to the working version; no reload needed.")
            return
        self.log("Validating saved changes: " + ", ".join(sorted(changed)))
        try:
            candidate = self.prepare(sources)
        except (RuntimeError, ValueError, OSError, KeyError) as error:
            self.log(f"{error}\nKeeping the working session. Save again to retry.")
            return
        if source_snapshot(ROOT) != sources:
            self.log("Newer save detected; keeping the match until that candidate is validated.")
            return
        resources = live_visual_paths(changed, candidate)
        if resources is not None:
            try:
                self.apply_visuals(candidate, resources, changed)
                self.active_sources = sources
                return
            except RuntimeError as error:
                self.log(f"Live refresh failed: {error}. Reopening the validated scenario.")
        self.log("Reopening the scenario for code, scene, or gameplay-data changes (positions reset).")
        previous = self.active
        self.stop_session()
        try:
            self.start_session(candidate)
            self.active_sources = sources
        except RuntimeError as error:
            self.log(f"Candidate startup failed: {error}. Restoring the last working scenario.")
            self.stop_session()
            self.start_session(previous)

    def run(self) -> None:
        sources = source_snapshot(ROOT)
        # Multiple launchers may start together, including on a fresh checkout.
        with (self.directory.parent / "dependency.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            if not (ROOT / "build/deps/libenet.a").exists():
                self.checked([sys.executable, str(ROOT / "tools/build_enet.py")], self.directory / "dependency.log")
        candidate = self.prepare(sources)
        self.start_session(candidate)
        self.active_sources = sources
        if self.args.run_seconds:
            self.deadline = time.monotonic() + self.args.run_seconds
        self.log("Watching client/ and server/. Ctrl+C or closing a window stops this run." if self.args.watch else "Watcher disabled. Ctrl+C or closing a window stops this run.")
        observed = sources
        attempted = sources
        stable_since = time.monotonic()
        while time.monotonic() < self.deadline:
            self.check_processes()
            if self.args.watch:
                try:
                    current = source_snapshot(ROOT)
                except OSError:
                    time.sleep(0.25)
                    continue
                if current != observed:
                    observed, stable_since = current, time.monotonic()
                elif observed != attempted and time.monotonic() - stable_since >= 0.5:
                    attempted = observed
                    self.reload(observed)
            time.sleep(0.25)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--p1", default="circle")
    parser.add_argument("--p2", default="square")
    parser.add_argument("--arena", default="meadow_crossing")
    parser.add_argument("--audience", type=int, default=0)
    parser.add_argument("--audience-delay", type=float, default=5, help="Host-enforced spectator delay in seconds (0..60; 0 disables)")
    parser.add_argument("--seed", type=int, default=1, help="Unsigned 32-bit per-scenario AI seed")
    parser.add_argument("--countdown", type=int, choices=(0, 5), default=0)
    parser.add_argument("--watch", type=int, choices=(0, 1), default=1)
    parser.add_argument("--headless", action="store_true", help="No windows (automation)")
    parser.add_argument("--run-seconds", type=float, default=0, help="Stop this many seconds after arena startup; 0 waits for Ctrl+C")
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--odin", default="odin")
    args = parser.parse_args()
    if not 0 <= args.seed <= 0xffffffff:
        parser.error("SEED must be an integer from 0 to 4294967295.")
    if not 0 <= args.audience <= 4093 or args.run_seconds < 0:
        parser.error("AUDIENCE must be 0..4093 and --run-seconds must be nonnegative.")
    if not math.isfinite(args.audience_delay) or not 0 <= args.audience_delay <= 60:
        parser.error("AUDIENCE_DELAY must be a finite number from 0 to 60 seconds.")
    try:
        validate_choices(ROOT, args)
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.error(str(error))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    runner = DevSessionRunner(args)
    try:
        runner.run()
        return 0
    except KeyboardInterrupt:
        return 0
    except (RuntimeError, ValueError, OSError, KeyError) as error:
        runner.log(str(error))
        return 1
    finally:
        runner.stop_session()
        runner.log("Owned host and clients stopped.")


if __name__ == "__main__":
    raise SystemExit(main())
