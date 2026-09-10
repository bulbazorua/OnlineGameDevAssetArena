#!/usr/bin/env python3
"""Exercise actual processing and failed attempts in a disposable repository."""
import argparse
import hashlib
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


def copy(relative, destination):
    source = ROOT / relative
    target = destination / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir():
        shutil.copytree(source, target, dirs_exist_ok=True)
    else:
        shutil.copy2(source, target)


def run(command):
    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    output = result.stdout + result.stderr
    assert result.returncode == 0 and "ERROR" not in output, output
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="character-pipeline-") as temporary:
        root = Path(temporary)
        for relative in (*pipeline.SHARED, "client/dev/fixtures/characters", "asset_sources/characters"):
            copy(relative, root)
        pipeline.ROOT = root
        module = "res://dev/fixtures/characters/reference16"
        originals = {p.relative_to(root): p.read_bytes() for p in (root / "asset_sources").rglob("*.png")}
        first = pipeline.process(module, args.godot)
        assert first["status"] == "pass", first
        second = pipeline.process(module, args.godot)
        assert second["status"] == "pass" and second["generation"] == first["generation"], second
        other = pipeline.process("res://dev/fixtures/characters/reference32", args.godot)
        assert other["status"] == "pass", other
        assert first["attempt"] != second["attempt"]
        for relative, content in originals.items():
            assert (root / relative).read_bytes() == content, "Processing rewrote an original"
        artifact = json.loads(Path(first["artifact"]).read_text())
        assert len(artifact["clips"]) == 5 and len(artifact["bindings"]) == 40
        for key, clip in artifact["clips"].items():
            for index, frame in enumerate(clip["frames"]):
                origin = frame["origin"]
                assert origin["clip"] == key and origin["frame"] == index
                assert origin["source"] == "sheet.png" and len(origin["source_sha256"]) == 64 and len(origin["rect"]) == 4
                assert pipeline.sha(Path(first["artifact"]).parent / frame["path"]) == frame["sha256"]
        print("PASS: original bytes preserved, two independent layouts, deterministic output and per-frame lineage", flush=True)

        pointer = root / "build/processed/characters/reference16/current.json"
        stable_pointer = pointer.read_bytes()

        def fails(stage, timeout=60):
            result = pipeline.process(module, args.godot, timeout)
            assert result["status"] == "fail" and result["stage"] == stage, result
            assert pointer.read_bytes() == stable_pointer, "Failed attempt replaced current generation"
            assert Path(result["report"]).is_file() and Path(result["trace"]).is_file()
            return result

        raw = root / "asset_sources/characters/reference16/sheet.png"
        raw_bytes = raw.read_bytes()
        raw.write_bytes(raw_bytes + b"broken")
        failure = fails("snapshot_source")
        assert failure["source"] == str(raw)
        raw.write_bytes(raw_bytes)
        folder = root / "client/dev/fixtures/characters/reference16"
        inventory = folder / "source_manifest.json"
        inventory_bytes = inventory.read_bytes()
        inventory.write_text("[]")
        fails("inventory")
        inventory.write_bytes(inventory_bytes)
        raw.write_bytes(b"not a PNG")
        data = json.loads(inventory_bytes)
        data["files"]["sheet.png"] = pipeline.sha(raw)
        inventory.write_text(json.dumps(data))
        fails("decode_source")
        raw.write_bytes(raw_bytes)
        inventory.write_bytes(inventory_bytes)
        importer = folder / "importer.gd"
        importer_text = importer.read_text()
        importer.write_text(importer_text.replace("Rect2i(index * 32, row * 32, 32, 32)", "Rect2i(99999, 0, 32, 32)"))
        failure = fails("extract_frame")
        assert failure["last_event"]["rect"] == [99999, 0, 32, 32]
        assert failure["last_event"]["clip"] == "rest"
        importer.write_text(importer_text)
        exporter = folder / "exporter.gd"
        exporter_text = exporter.read_text()
        exporter.write_text(exporter_text.replace('"hurt": "flinch", ', ""))
        failure = fails("validate")
        assert Path(failure["staged_artifact"]).is_file(), "Failed candidate output was discarded"
        assert any(row["id"] == "role.hurt" and row["status"] == "fail" for row in failure["diagnostics"]["checks"])
        exporter.write_text(exporter_text + "\nthis is invalid syntax !!!\n")
        fails("compile_module")
        exporter.write_text(exporter_text.replace("\tvar result :=", "\twhile true: pass\n\tvar result :="))
        fails("custom_processing", timeout=3)
        exporter.write_text(exporter_text)
        worker = root / "client/dev/process_character_assets.gd"
        worker_text = worker.read_text()
        worker.write_text(worker_text.replace("var written := Artifact.write", 'request.output = request.raw_snapshot + "/sheet.png"\n\tvar written := Artifact.write'))
        fails("serialize")
        worker.write_text(worker_text.replace('_finish(true, "processed", "", reloaded.report, written.digest)', 'var changed := FileAccess.open(request.raw_snapshot + "/sheet.png", FileAccess.WRITE)\n\tchanged.store_string("modified snapshot")\n\tchanged.close()\n\t_finish(true, "processed", "", reloaded.report, written.digest)'))
        fails("verify_inputs")
        worker.write_text(worker_text.replace('_finish(true, "processed", "", reloaded.report, written.digest)', 'var partial := FileAccess.open(request.result, FileAccess.WRITE)\n\tpartial.store_string("{")\n\tpartial.close()\n\tquit(1)'))
        fails("custom_processing")
        worker.write_text(worker_text)
        print("PASS: malformed inventory, source checksum, PNG decode, crop, missing role, syntax, timeout, output-write, modified snapshot and partial-result failures preserve the current generation", flush=True)

        # A second tiny project contains only the data reader and its public types.
        reader_root = root / "reader"
        for relative in ("client/characters/character_artifact.gd", "client/characters/character_animation_set.gd",
                         "client/characters/import/character_exports.gd", "client/content/character_contract.gd",
                         "client/content/contracts", "client/presentation/asset_scale.gd", "tests/character_processed_probe.gd"):
            copy(relative, reader_root)
        (reader_root / "client/project.godot").write_text(pipeline.BOOTSTRAP)
        run([args.godot, "--headless", "--path", str(reader_root / "client"), "--editor", "--import"])
        command = [args.godot, "--headless", "--path", str(reader_root / "client"), "--script", str(reader_root / "tests/character_processed_probe.gd"), "--", first["artifact"], first["generation"]]
        # Remove originals and modules entirely before running the data-only consumer.
        shutil.rmtree(root / "asset_sources")
        shutil.rmtree(root / "client/dev/fixtures")
        print(run(command).strip(), flush=True)
        frame = Path(first["artifact"]).parent / next(iter(artifact["clips"].values()))["frames"][0]["path"]
        frame.write_bytes(b"corrupt processed output")
        print(run(command + ["expect_failure"]).strip(), flush=True)
        print("PASS: character asset processing pipeline", flush=True)


if __name__ == "__main__":
    main()
