#!/usr/bin/env python3
"""Run each 4A reference module without other modules, assets, app, or server."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(command):
    result = subprocess.run(command, capture_output=True, text=True, timeout=60)
    output = result.stdout + result.stderr
    if result.returncode or "SCRIPT ERROR" in output or "ERROR:" in output:
        raise RuntimeError(output)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    args = parser.parse_args()
    for key in ("reference16", "reference32"):
        with tempfile.TemporaryDirectory(prefix="character-isolation-") as directory:
            target = Path(directory) / "client"
            target.mkdir()
            (target / "project.godot").write_text('config_version=5\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
            dependencies = [
                "content/contracts", "content/character_contract.gd", "characters/import",
                "characters/character_animation_set.gd", "presentation/asset_scale.gd",
                f"dev/fixtures/characters/{key}",
            ]
            for relative in dependencies:
                source = ROOT / "client" / relative
                destination = target / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                if source.is_dir():
                    shutil.copytree(source, destination)
                else:
                    shutil.copy2(source, destination)
            shutil.copy2(ROOT / "tests/character_module_probe.gd", target / "probe.gd")
            shutil.copytree(ROOT / f"asset_sources/characters/{key}", Path(directory) / f"asset_sources/characters/{key}")
            run([args.godot, "--headless", "--path", str(target), "--editor", "--import"])
            output = run([args.godot, "--headless", "--path", str(target), "--script", "res://probe.gd", "--", key])
            assert "PASS:" in output, output
            print(output.strip())


if __name__ == "__main__":
    main()
