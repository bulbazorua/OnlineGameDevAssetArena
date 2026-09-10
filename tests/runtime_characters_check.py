#!/usr/bin/env python3
"""Runtime bundles survive without source modules; failures cannot publish mixed output."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(command, success=True):
    result = subprocess.run(command, capture_output=True, text=True, timeout=90)
    output = result.stdout + result.stderr
    if success:
        assert result.returncode == 0 and "ERROR:" not in output, output
    else:
        assert result.returncode != 0, output
    return output


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="runtime-character-") as temporary:
        root = Path(temporary)
        for name in ("client", "tools"):
            shutil.copytree(ROOT / name, root / name, ignore=shutil.ignore_patterns(".godot", "__pycache__"))
        command = ["python3", str(root / "tools/prepare_characters.py"), "--godot", args.godot]
        run(command)
        index = root / "client/generated/characters/catalog.json"
        original = index.read_bytes()
        timestamp = index.stat().st_mtime_ns
        run(command)
        assert index.read_bytes() == original and index.stat().st_mtime_ns == timestamp
        exporter = root / "client/characters/packages/orc/exporter.gd"
        source = exporter.read_text()
        exporter.write_text(source.replace('"hurt": "orc_hurt", ', ''))
        assert "Cannot bundle orc" in run(command, success=False)
        assert index.read_bytes() == original, "Failed build replaced a successful runtime bundle"
        exporter.write_text(source)
        shutil.rmtree(root / "client/assets/Characters")
        shutil.rmtree(root / "client/characters/packages")
        shutil.rmtree(root / "tools")
        shutil.rmtree(root / "build", ignore_errors=True)
        probe = root / "client/runtime_probe.gd"
        probe.write_text('extends SceneTree\nfunc _initialize():\n\tvar content = load("res://content/game_content.gd").new()\n\tvar error = content.load_catalog()\n\tif not error.is_empty() or content.character_art.size() != 2:\n\t\tpush_error("Runtime art load failed: " + error)\n\t\tquit(1)\n\t\treturn\n\tquit()\n')
        run([args.godot, "--headless", "--path", str(root / "client"), "--editor", "--import"])
        load = [args.godot, "--headless", "--path", str(root / "client"), "--script", "res://runtime_probe.gd"]
        run(load)
        entries = json.loads(original)["modules"]
        artifact = root / "client" / entries["archer"]["artifact"].removeprefix("res://")
        # A valid trainer contract cannot enter the gladiator roster, even with
        # matching identity/footprint and intact processed frame hashes.
        artifact_bytes = artifact.read_bytes()
        trainer = json.loads(artifact_bytes)
        trainer["contract_id"] = "player.trainer"
        bindings = []
        mapping = {"idle": ["idle"], "walk": ["walk", "run"], "attack": ["advise"],
                   "hurt": ["hurt", "cheer", "surprised"], "death": ["disappointed"]}
        for binding in trainer["bindings"]:
            for role in mapping[binding["role"]]:
                entry = copy.deepcopy(binding)
                entry.update(role=role, variant="default")
                bindings.append(entry)
        trainer["bindings"] = bindings
        artifact.write_text(json.dumps(trainer))
        swapped = json.loads(original)
        swapped["modules"]["archer"]["digest"] = hashlib.sha256(artifact.read_bytes()).hexdigest()
        index.write_text(json.dumps(swapped))
        assert "animation contract" in run(load, success=False)
        artifact.write_bytes(artifact_bytes)
        index.write_bytes(original)
        frames = next(iter(json.loads(artifact.read_text())["clips"].values()))["frames"]
        (artifact.parent / frames[0]["path"]).write_bytes(b"corrupted frame")
        assert "SHA-256 mismatch" in run(load, success=False)
        print("PASS: cached runtime bundles, failed import retention, no raw/module/build dependency, trainer/character separation and corrupted frame rejection")


if __name__ == "__main__":
    main()
