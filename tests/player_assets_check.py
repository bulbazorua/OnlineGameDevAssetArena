#!/usr/bin/env python3
"""Verify isolated Player1 processing, recorded pixels and failed-build recovery."""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("asset_processor", ROOT / "tools/process_character_assets.py")
pipeline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pipeline)
ROLES = {"idle", "walk", "run", "advise", "hurt", "cheer", "surprised", "disappointed"}


def run(command):
    result = subprocess.run(command, capture_output=True, text=True, timeout=45)
    output = result.stdout + result.stderr
    assert result.returncode == 0 and "SCRIPT ERROR" not in output and "ERROR:" not in output, output
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    args = parser.parse_args()
    module = "client/players/packages/player1"
    uri = "res://players/packages/player1"
    raw = "client/assets/Characters/Player1"
    with tempfile.TemporaryDirectory(prefix="player1-assets-") as directory:
        root = Path(directory)
        for relative in (*pipeline.SHARED, module, raw, "tests/character_processed_probe.gd"):
            source, target = ROOT / relative, root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if source.is_dir(): shutil.copytree(source, target)
            else: shutil.copy2(source, target)
        assert not (root / "client/characters/packages").exists()
        pipeline.ROOT = root
        first = pipeline.process(uri, args.godot, family="players")
        second = pipeline.process(uri, args.godot, family="players")
        assert first["status"] == second["status"] == "pass", (first, second)
        assert first["generation"] == second["generation"]
        assert set(first["diagnostics"]["renderable_roles"]) == ROLES
        assert first["diagnostics"]["art_pass"] and not first["diagnostics"]["selection_eligible"]
        pointer = root / "build/processed/players/player1/current.json"
        previous = pointer.read_bytes()
        manifest = json.loads((root / module / "source_manifest.json").read_text())
        artifact = json.loads(Path(first["artifact"]).read_text())
        assert artifact["contract_id"] == "player.trainer" and len(artifact["bindings"]) == 64
        assert set(artifact["clips"]) == {"trainer_" + role for role in ROLES}
        art_path = root / module / "art.json"
        art_text = art_path.read_text()
        authored = json.loads(art_text)
        for sequence in authored["sequences"]:
            clip = artifact["clips"][sequence["clip"]]
            assert len(clip["frames"]) == (8 if sequence["clip"] == "trainer_walk" else 6)
            for index, frame in enumerate(clip["frames"]):
                origin = frame["origin"]
                assert origin["source"] == sequence["file"] and origin["frame"] == index
                assert origin["source_sha256"] == manifest["files"][sequence["file"]]
                assert origin["rect"] == sequence["frames"][index]["rect"]
                transform, = origin["transforms"]
                assert transform["source_ground_px"] == sequence["frames"][index]["ground"]
                for axis in (0, 1):
                    mapped = ((transform["source_ground_px"][axis] - origin["rect"][axis]) *
                              transform["resize_to"][axis] / origin["rect"][axis + 2] + transform["offset"][axis])
                    assert abs(mapped - transform["target_ground_px"][axis]) <= 0.5
        (root / "client/project.godot").write_text(pipeline.BOOTSTRAP)
        run([args.godot, "--headless", "--path", str(root / "client"), "--editor", "--import"])
        command = [args.godot, "--headless", "--path", str(root / "client"), "--script",
                   str(root / "tests/character_processed_probe.gd"), "--", first["artifact"], first["generation"]]
        run(command + ["--source-root=" + str(root / raw)])

        # Missing required art remains inspectable, and cannot replace a good generation.
        authored["sequences"] = [seq for seq in authored["sequences"] if seq["clip"] != "trainer_advise"]
        art_path.write_text(json.dumps(authored))
        missing = pipeline.process(uri, args.godot, family="players")
        assert missing["status"] == "fail" and missing["stage"] == "validate", missing
        assert {row["id"] for row in missing["diagnostics"]["checks"] if row["status"] == "fail"} == {"role.advise"}
        assert missing["candidate_digest"] and Path(missing["staged_artifact"]).is_file()
        assert pointer.read_bytes() == previous
        art_path.write_text(art_text)

        authored = json.loads(art_text)
        authored["sequences"][0]["frames"][0]["ground"] = [-1000, -1000]
        art_path.write_text(json.dumps(authored))
        broken = pipeline.process(uri, args.godot, family="players")
        assert broken["status"] == "fail" and broken["stage"] == "player1_normalize", broken
        assert broken["source"] == "player_idle.png" and pointer.read_bytes() == previous
        assert '"frame":0' in Path(broken["trace"]).read_text().replace(" ", "")
        art_path.write_text(art_text)

        wrong_family = pipeline.process(uri, args.godot)
        assert wrong_family["status"] == "fail" and wrong_family["stage"] == "validate", wrong_family
        assert not (root / "build/processed/characters/player1/current.json").exists()
        for name, digest in manifest["files"].items():
            assert pipeline.sha(root / raw / name) == digest
        shutil.rmtree(root / "client/players")
        shutil.rmtree(root / "client/assets")
        run(command)
        print("PASS: Player1 alone processes all 50 frames; provenance replays exactly, bad states/anchors preserve current, wrong family fails, processed art needs no originals/importer")


if __name__ == "__main__":
    main()
