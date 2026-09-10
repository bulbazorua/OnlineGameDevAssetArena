#!/usr/bin/env python3
"""Bundle validated processed character art inside the client, without runtime importers."""
import argparse
import fcntl
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import uuid

import process_character_assets as pipeline


def intact(root, entry):
    try:
        artifact = pipeline.local_path(root / "client", entry["artifact"].removeprefix("res://"))
        if pipeline.sha(artifact) != entry["digest"]:
            return False
        document = json.loads(artifact.read_text())
        return all(pipeline.sha(pipeline.local_path(artifact.parent, frame["path"])) == frame["sha256"]
                   for clip in document["clips"].values() for frame in clip["frames"])
    except (OSError, ValueError, KeyError, TypeError):
        return False


def prepare(root, godot):
    pipeline.ROOT = root
    folder = root / "client/generated/characters"
    folder.mkdir(parents=True, exist_ok=True)
    with (folder / ".prepare.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        declarations = json.loads((root / "client/content/presentation/characters.json").read_text())
        if declarations.get("schema_version") != 1 or not isinstance(declarations.get("modules"), dict):
            raise ValueError("Invalid runtime character module declarations")
        previous = pipeline.read_json(folder / "catalog.json") or {}
        bundle = {"schema_version": 1, "modules": {}}
        version = subprocess.check_output([godot, "--version"], text=True).strip()
        for key, uri in declarations["modules"].items():
            module = pipeline.local_path(root / "client", uri.removeprefix("res://"))
            if module.name != key or not uri.startswith("res://"):
                raise ValueError("Runtime module key/path mismatch: " + key)
            manifest = json.loads((module / "source_manifest.json").read_text())
            inputs = pipeline.code_files(module)
            inputs["tools/prepare_characters.py"] = root / "tools/prepare_characters.py"
            raw = pipeline.local_path(root, manifest["raw_root"])
            for name in manifest["files"]:
                path = pipeline.local_path(raw, name)
                inputs[path.relative_to(root).as_posix()] = path
            signature = hashlib.sha256(json.dumps({"godot": version, "files": {
                name: pipeline.sha(path) for name, path in sorted(inputs.items())}}, sort_keys=True).encode()).hexdigest()
            old = previous.get("modules", {}).get(key, {})
            if old.get("source_digest") == signature and intact(root, old):
                bundle["modules"][key] = old
                continue
            result = pipeline.process(uri, godot)
            if result["status"] != "pass":
                raise ValueError(f"Cannot bundle {key}: {result['stage']}: {result.get('error', '')}. Report: {result['report']}")
            digest = result["generation"]
            destination = folder / key / digest
            entry = {"artifact": "res://" + (destination / "artifact.json").relative_to(root / "client").as_posix(),
                     "digest": digest, "source_digest": signature}
            if destination.exists():
                if not intact(root, entry):
                    raise ValueError("Modified runtime generation: " + str(destination))
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                staging = destination.with_name(".staging-" + uuid.uuid4().hex)
                shutil.copytree(Path(result["artifact"]).parent, staging)
                staging.rename(destination)
            bundle["modules"][key] = entry
        if bundle != previous:
            pipeline.write_json(folder / "catalog.json", bundle, atomic=True)
        print("Runtime character art ready: " + ", ".join(bundle["modules"]), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--godot", default="godot")
    args = parser.parse_args()
    try:
        prepare(args.root.resolve(), args.godot)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        parser.exit(1, str(error) + "\n")


if __name__ == "__main__":
    main()
