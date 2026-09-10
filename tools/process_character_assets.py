#!/usr/bin/env python3
"""Process one character's declared originals; retain every attempt and publish atomically."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
SHARED = (
    "client/characters/import", "client/characters/character_animation_set.gd",
    "client/characters/character_artifact.gd", "client/content/character_contract.gd",
    "client/content/contracts", "client/presentation/asset_scale.gd",
    "client/dev/process_character_assets.gd", "tools/process_character_assets.py",
)
BOOTSTRAP = 'config_version=5\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n'


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path: Path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def write_json(path: Path, value, *, atomic=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    target = path.with_name(path.name + ".tmp") if atomic else path
    target.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    if atomic:
        target.replace(path)


def local_path(root: Path, relative: str) -> Path:
    if not isinstance(relative, str) or not relative or Path(relative).is_absolute() or ".." in Path(relative).parts or "\\" in relative:
        raise ValueError(f"Expected a relative path: {relative!r}")
    result = (root / relative).resolve()
    if not result.is_relative_to(root.resolve()):
        raise ValueError(f"Path leaves its declared root: {relative}")
    return result


def code_files(module: Path) -> dict[str, Path]:
    files = {}
    for root in [module, *(ROOT / entry for entry in SHARED)]:
        paths = root.rglob("*") if root.is_dir() else [root]
        for path in paths:
            if path.is_file() and path.suffix in (".gd", ".json", ".py", ".tres", ".tscn"):
                files[path.relative_to(ROOT).as_posix()] = path
    return files


class ProcessingError(Exception):
    def __init__(self, stage, message, source=""):
        super().__init__(message)
        self.stage, self.source = stage, source


def process(module_uri: str, godot: str, timeout: float = 60) -> dict:
    if not module_uri.startswith("res://"):
        raise ValueError("MODULE must be a local res:// module directory")
    module = local_path(ROOT / "client", module_uri.removeprefix("res://"))
    key = module.name
    if not re.fullmatch(r"[a-z][a-z0-9_]*", key):
        raise ValueError("Module directory must use a lowercase character key")
    processed = ROOT / "build/processed/characters" / key
    processed.mkdir(parents=True, exist_ok=True)
    with (processed / ".lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return _attempt(module_uri, module, key, processed, godot, timeout)


def _attempt(module_uri, module, key, processed, godot, timeout):
    now = datetime.now(timezone.utc)
    attempt = now.strftime("%Y%m%dT%H%M%S") + "-" + uuid.uuid4().hex[:12]
    job = ROOT / "build/asset-jobs" / key / attempt
    job.mkdir(parents=True)
    trace = job / "trace.jsonl"
    report_path = job / "report.json"
    report = {"schema_version": 1, "module": key, "attempt": attempt, "status": "running",
              "stage": "inventory", "scope": "art_processing_only", "selection_eligible": False,
              "started_at": now.isoformat(), "report": str(report_path), "trace": str(trace),
              "godot_log": str(job / "godot.log"), "staged_artifact": str(job / "stage/artifact.json")}
    write_json(report_path, report)

    def event(stage, status, **details):
        with trace.open("a") as stream:
            stream.write(json.dumps({"stage": stage, "status": status, **details}) + "\n")

    def run(command, log, stage):
        report["stage"] = stage
        event(stage, "started", log=str(log))
        with log.open("w") as stream:
            try:
                result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout, cwd=ROOT)
            except subprocess.TimeoutExpired as error:
                raise ProcessingError(stage, f"Godot timed out after {timeout:g}s; see {log}") from error
        output = log.read_text()
        if result.returncode or "SCRIPT ERROR" in output or "ERROR:" in output:
            raise ProcessingError(stage, f"Godot failed (exit {result.returncode}); see {log}")
        event(stage, "pass", log=str(log))

    try:
        manifest_path = module / "source_manifest.json"
        manifest_hash = sha(manifest_path)
        manifest = json.loads(manifest_path.read_text())
        if not isinstance(manifest, dict) or manifest.get("schema_version") != 1 or manifest.get("module_key") != key or not isinstance(manifest.get("files"), dict) or not manifest["files"]:
            raise ProcessingError("inventory", "Invalid source inventory or module key", str(manifest_path))
        raw_root = local_path(ROOT, manifest["raw_root"])
        report["original_root"] = str(raw_root)
        files = code_files(module)
        expected_raw_hashes = {}
        for name, expected in manifest["files"].items():
            source = local_path(raw_root, name)
            event("snapshot_source", "started", source=str(source))
            if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected) or not source.is_file() or sha(source) != expected:
                raise ProcessingError("snapshot_source", "Missing original or source SHA-256 mismatch", str(source))
            destination = job / "raw" / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
            if sha(destination) != expected:
                raise ProcessingError("snapshot_source", "Original changed during snapshot", str(source))
            files[source.relative_to(ROOT).as_posix()] = source
            expected_raw_hashes[source.relative_to(ROOT).as_posix()] = expected
            event("snapshot_source", "pass", source=str(source), snapshot=str(destination), sha256=expected)
        hashes = {}
        for relative, path in sorted(files.items()):
            # Snapshot processing code as well as raw files. The worker never runs live module code.
            destination = job / "inputs" / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)
            hashes[relative] = sha(destination)
            if relative in expected_raw_hashes and hashes[relative] != expected_raw_hashes[relative]:
                raise ProcessingError("snapshot_source", "Original changed while processing inputs were copied", str(path))
        if hashes[manifest_path.relative_to(ROOT).as_posix()] != manifest_hash:
            raise ProcessingError("inventory", "Source inventory changed during snapshot", str(manifest_path))
        version = subprocess.check_output([godot, "--version"], text=True, timeout=10).strip()
        inputs = {"module": module_uri, "files": hashes, "godot": version, "worker_project": BOOTSTRAP}
        input_digest = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()
        report["input_digest"] = input_digest
        write_json(job / "inputs.json", inputs)
        worker = job / "inputs/client"
        (worker / "project.godot").write_text(BOOTSTRAP)
        output = job / "stage"
        output.mkdir()
        request = {"module": module_uri, "raw_snapshot": str(job / "raw"), "output": str(output),
                   "trace": str(trace), "result": str(job / "worker_result.json"), "input_digest": input_digest}
        write_json(job / "request.json", request)
        run([godot, "--headless", "--path", str(worker), "--editor", "--import"], job / "import.log", "import_scripts")
        run([godot, "--headless", "--path", str(worker), "--script", "res://dev/process_character_assets.gd", "--check-only"], job / "compile.log", "compile_pipeline")
        for entry in ("importer.gd", "exporter.gd"):
            run([godot, "--headless", "--path", str(worker), "--script", module_uri + "/" + entry, "--check-only"], job / (entry + ".log"), "compile_module")
        run([godot, "--headless", "--path", str(worker), "--script", "res://dev/process_character_assets.gd", "--", str(job / "request.json")], job / "godot.log", "custom_processing")
        result = json.loads((job / "worker_result.json").read_text())
        report["diagnostics"] = result.get("diagnostics", {})
        report["candidate_digest"] = result.get("artifact_digest", "")
        if not result.get("ok"):
            raise ProcessingError(result.get("stage", "custom_processing"), result.get("error", "Worker did not succeed"))
        report["stage"] = "verify_inputs"
        current_files = code_files(module)
        for name in manifest["files"]:
            source = local_path(raw_root, name)
            current_files[source.relative_to(ROOT).as_posix()] = source
        if set(current_files) != set(hashes) or any(not path.is_file() or sha(path) != hashes[relative] for relative, path in current_files.items()):
            raise ProcessingError("verify_inputs", "Inputs or processing code changed during this attempt")
        if any(sha(job / "raw" / name) != expected for name, expected in manifest["files"].items()):
            raise ProcessingError("verify_inputs", "Processing modified its raw source snapshot")
        if any(sha(job / "inputs" / relative) != expected for relative, expected in hashes.items()):
            raise ProcessingError("verify_inputs", "Processing modified its input/code snapshot")
        digest = result["artifact_digest"]
        if not re.fullmatch(r"[0-9a-f]{64}", digest) or sha(output / "artifact.json") != digest:
            raise ProcessingError("publish", "Worker artifact digest mismatch")
        generation = processed / "generations" / digest
        generation.parent.mkdir(parents=True, exist_ok=True)
        report["stage"] = "publish"
        if generation.exists():
            existing = {p.relative_to(generation).as_posix(): sha(p) for p in generation.rglob("*") if p.is_file()}
            staged = {p.relative_to(output).as_posix(): sha(p) for p in output.rglob("*") if p.is_file()}
            if existing != staged:
                raise ProcessingError("publish", "Existing immutable generation was modified; refusing to overwrite it")
        else:
            destination = processed / "generations" / (".staging-" + attempt)
            shutil.copytree(output, destination)
            destination.rename(generation)
        write_json(processed / "current.json", {"generation": digest, "attempt": attempt, "report": str(report_path)}, atomic=True)
        report.update(status="pass", stage="published", generation=digest, artifact=str(generation / "artifact.json"))
        event("publish", "pass", generation=digest)
    except (ProcessingError, OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        # Prefer a structured worker failure; syntax errors/timeouts may leave only a trace/log.
        worker_result = job / "worker_result.json"
        result = read_json(worker_result)
        if not isinstance(result, dict): result = {}
        stage = error.stage if isinstance(error, ProcessingError) else report["stage"]
        message = str(error)
        if result and not result.get("ok"):
            stage, message = result.get("stage", stage), result.get("error", message)
            report["diagnostics"] = result.get("diagnostics", {})
            report["candidate_digest"] = result.get("artifact_digest", "")
        failures = []
        for line in trace.read_text().splitlines() if trace.exists() else []:
            try:
                entry = json.loads(line)
                if isinstance(entry, dict): failures.append(entry)
            except ValueError:
                failures.append({"stage": stage, "status": "incomplete_trace", "text": line})
        failure = next((entry for entry in reversed(failures) if entry.get("status") == "fail"), {})
        source = error.source if isinstance(error, ProcessingError) else ""
        if failure:
            stage, source, message = failure["stage"], failure.get("source", source), failure.get("message", message)
        report.update(status="fail", stage=stage, error=message, source=source)
        if failures: report["last_event"] = failures[-1]
        event(stage, "fail", source=source, message=message)
    report["finished_at"] = datetime.now(timezone.utc).isoformat()
    write_json(report_path, report)
    write_json(processed / "latest_attempt.json", report, atomic=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--module")
    selection.add_argument("--character")
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--timeout", type=float, default=60)
    parser.add_argument("--open-harness", action="store_true")
    parser.add_argument("--candidate", action="store_true", help="Open the latest staged candidate instead of the last successful generation")
    args = parser.parse_args()
    try:
        if args.module is None:
            registry = json.loads((ROOT / "client/characters/packages/registry.json").read_text())
            key = args.character or "reference16"
            entries = [entry for entry in registry["modules"] if entry["key"] == key]
            if len(entries) != 1:
                raise ValueError("Unknown or duplicated character key: " + key)
            args.module = entries[0]["module"]
        args.module = args.module.rstrip("/")
        result = process(args.module, args.godot, args.timeout)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.error(str(error))
    print(f"{result['status'].upper()}: {result['module']} at {result['stage']}")
    if result.get("error"): print(result["error"])
    print("Report:", result["report"])
    if result.get("artifact"): print("Processed:", result["artifact"])
    if args.open_harness:
        command = [args.godot, "--path", str(ROOT / "client"), "res://dev/character_harness.tscn", "--", "--module=" + args.module]
        current = ROOT / "build/processed/characters" / result["module"] / "current.json"
        if not args.candidate and not current.exists() and result.get("candidate_digest"):
            args.candidate = True
            print("No successful generation; previewing the latest processed candidate with its validation failures.", flush=True)
        if args.candidate: command.append("--candidate")
        return subprocess.call(command)
    return 0 if result["status"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
