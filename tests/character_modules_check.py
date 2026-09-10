#!/usr/bin/env python3
"""Build Archer and Orc independently; verify pixels, mappings and incomplete candidates."""
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

EXPECTED = {
    "archer": {"span": 192, "reference": 64, "role_clips": {"idle": "bow_rest", "walk": "bow_run", "attack": "bow_shoot", "hurt": "bow_hurt", "death": "bow_fall"},
               "clips": {"bow_rest": ("Archer_Idle.png", 6), "bow_run": ("Archer_Run.png", 4), "bow_shoot": ("Archer_Shoot.png", 8), "bow_hurt": ("Archer_hurt.png", 6), "bow_fall": ("Archer_death.png", 7)}},
    "orc": {"span": 100, "reference": 14, "role_clips": {"idle": "orc_rest", "walk": "orc_walk", "hurt": "orc_hurt", "attack": "orc_axe", "death": "orc_fall"},
            "clips": {"orc_rest": ("Orc_Idle.png", 6), "orc_walk": ("Orc_Walk.png", 8), "orc_hurt": ("Orc_Hurt.png", 4), "orc_axe": ("Orc_Attack01.png", 6), "orc_fall": ("Orc_Death.png", 4)}}
}


def copy(relative, target_root):
    source, target = ROOT / relative, target_root / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir(): shutil.copytree(source, target, dirs_exist_ok=True)
    else: shutil.copy2(source, target)


def run(command):
    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    output = result.stdout + result.stderr
    assert result.returncode == 0 and "SCRIPT ERROR" not in output and "ERROR:" not in output, output
    return output


def check(key, godot):
    with tempfile.TemporaryDirectory(prefix=f"{key}-module-") as directory:
        root = Path(directory)
        module = f"client/characters/packages/{key}"
        for relative in (*pipeline.SHARED, module, "tests/character_processed_probe.gd"):
            copy(relative, root)
        manifest = json.loads((root / module / "source_manifest.json").read_text())
        for name in manifest["files"]:
            copy(manifest["raw_root"] + "/" + name, root)
        assert len(list((root / "client/characters/packages").iterdir())) == 1
        assert len(list((root / "client/assets/Characters").iterdir())) == 1
        pipeline.ROOT = root
        uri = "res://characters/packages/" + key
        first = pipeline.process(uri, godot)
        second = pipeline.process(uri, godot)
        assert first["status"] == second["status"] == "pass", (first, second)
        assert first["candidate_digest"] == second["candidate_digest"] and len(first["candidate_digest"]) == 64
        assert not first["selection_eligible"] and not first["diagnostics"]["selection_eligible"]
        assert any(check["id"] == "combat" and check["status"] == "not_run" for check in first["diagnostics"]["checks"])
        pointer = root / f"build/processed/characters/{key}/current.json"
        assert first["diagnostics"]["art_pass"] and pointer.is_file()
        previous_pointer = pointer.read_bytes() if pointer.exists() else None
        artifact_path = Path(first["staged_artifact"])
        artifact = json.loads(artifact_path.read_text())
        expected = EXPECTED[key]
        assert artifact["ai"] == {"mode": "player_only"}
        assert artifact["gameplay_definition"]["identity"]["key"] == key
        assert artifact["gameplay_definition"]["gameplay_size"] == 1
        assert artifact["metrics"]["reference_span_px"] == expected["reference"]
        assert set(artifact["clips"]) == set(expected["clips"])
        authored_sequences = {item["clip"]: item for item in json.loads((root / module / "art.json").read_text()).get("authored_sequences", [])}
        for clip, (filename, count) in expected["clips"].items():
            frames = artifact["clips"][clip]["frames"]
            assert len(frames) == count
            for index, frame in enumerate(frames):
                origin = frame["origin"]
                span = expected["span"]
                assert origin["source"] == filename and origin["frame"] == index and origin["clip"] == clip
                if clip in authored_sequences:
                    authored_frame = authored_sequences[clip]["frames"][index]
                    assert origin["rect"] == authored_frame["rect"]
                    transform, = origin["transforms"]
                    assert transform["kind"] == "resize_canvas" and transform["version"] == 1
                    assert transform["canvas_size"] == [192, 192] and transform["target_ground_px"] == [96, 128]
                    assert transform["source_ground_px"] == authored_frame["ground"]
                    assert artifact["clips"][clip]["loop"] is False
                    for axis in (0, 1):
                        ground = (authored_frame["ground"][axis] - origin["rect"][axis]) * transform["resize_to"][axis] / origin["rect"][axis + 2] + transform["offset"][axis]
                        assert abs(ground - transform["target_ground_px"][axis]) <= 0.5
                else:
                    assert origin["rect"] == [index * span, 0, span, span]
                    assert not origin.get("transforms")
                assert origin["source_sha256"] == manifest["files"][filename]
        for binding in artifact["bindings"]:
            assert binding["clip"] == expected["role_clips"][binding["role"]]
            assert binding["flip_h"] == ("west" in binding["facing"])
            assert binding["variant"] == ("primary" if binding["role"] == "attack" else "default")
        assert len(artifact["bindings"]) == len(expected["role_clips"]) * 8
        for name, digest in manifest["files"].items():
            assert pipeline.sha(root / manifest["raw_root"] / name) == digest

        # A wrong private layout fails in the owning importer, preserving published output.
        art_path = root / module / "art.json"
        art_text = art_path.read_text()
        authored = json.loads(art_text)
        if key == "archer": authored["strips"][0]["count"] = 7
        else: authored["animations"]["orc_rest"]["frames"] = 7
        art_path.write_text(json.dumps(authored))
        broken = pipeline.process(uri, godot)
        assert broken["status"] == "fail" and broken["stage"] == key + "_layout", broken
        assert (pointer.read_bytes() if pointer.exists() else None) == previous_pointer
        art_path.write_text(art_text)

        if key == "archer":
            authored = json.loads(art_text)
            authored["authored_sequences"][0]["frames"][0]["ground"] = [-1000, -1000]
            art_path.write_text(json.dumps(authored))
            bad_anchor = pipeline.process(uri, godot)
            assert bad_anchor["status"] == "fail" and bad_anchor["stage"] == "archer_normalize", bad_anchor
            assert pointer.read_bytes() == previous_pointer
            art_path.write_text(art_text)

        (root / "client/project.godot").write_text(pipeline.BOOTSTRAP)
        run([godot, "--headless", "--path", str(root / "client"), "--editor", "--import"])
        command = [godot, "--headless", "--path", str(root / "client"), "--script", str(root / "tests/character_processed_probe.gd"), "--", str(artifact_path), first["candidate_digest"]]
        run(command + ["--source-root=" + str(root / manifest["raw_root"])])

        # Incomplete candidates stay inspectable and cannot replace this successful build.
        exporter = root / module / "exporter.gd"
        exporter_text = exporter.read_text()
        before_return, final_return = exporter_text.rsplit("\treturn result", 1)
        exporter.write_text(before_return + '\tresult.art.bindings.assign(result.art.bindings.filter(func(binding): return binding.role not in ["hurt", "death"]))\n\treturn result' + final_return)
        incomplete = pipeline.process(uri, godot)
        assert incomplete["status"] == "fail" and incomplete["stage"] == "validate", incomplete
        assert pointer.read_bytes() == previous_pointer
        assert {row["id"] for row in incomplete["diagnostics"]["checks"] if row["status"] == "fail"} == {"role.hurt", "role.death"}
        run(command[:-2] + [incomplete["staged_artifact"], incomplete["candidate_digest"], "expect_incomplete"])
        exporter.write_text(exporter_text)
        # The same processed reader then runs with all raw/module files removed.
        shutil.rmtree(root / "client/characters/packages")
        shutil.rmtree(root / "client/assets")
        run(command)
        print(f"PASS: {key} isolated import, original pixels/order, canonical roles, explicit AI, stable output, owned layout failures and processed-only loading", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--prepare-workspace", action="store_true")
    args = parser.parse_args()
    for key in ("archer", "orc"): check(key, args.godot)
    if args.prepare_workspace:
        pipeline.ROOT = ROOT
        for key in ("archer", "orc"):
            result = pipeline.process("res://characters/packages/" + key, args.godot)
            assert result["status"] == "pass", result
            assert len(result.get("candidate_digest", "")) == 64, result
            assert result["diagnostics"]["art_pass"] and (ROOT / f"build/processed/characters/{key}/current.json").exists(), result
            print(f"Prepared {key}: {result['status']} at {result['stage']}; {result['report']}", flush=True)


if __name__ == "__main__":
    main()
