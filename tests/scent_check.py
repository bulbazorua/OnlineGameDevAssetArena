#!/usr/bin/env python3
"""Real scent trails: olfaction pages, smell-guided search, host heatmap, saved filters, reset and replay."""
from __future__ import annotations

import argparse
import base64
import json
import math
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

from ai_debugger_check import checked, journal_records, read, wait
from search_check import stop
from senses_windows_check import check_bound_olfaction, check_coverage, native_windows

ROOT = Path(__file__).resolve().parents[1]


def prepare(args, sandbox: Path) -> list[str]:
    for name in ("client", "server", "tools", "tests"):
        shutil.copytree(ROOT / name, sandbox / name, ignore=shutil.ignore_patterns(".godot", "__pycache__"))
    (sandbox / "build/deps").mkdir(parents=True)
    shutil.copy2(ROOT / "build/deps/libenet.a", sandbox / "build/deps/libenet.a")
    wrapper = sandbox / "godot-driver"
    wrapper.write_text("#!/usr/bin/env python3\nimport os, sys\nargs = sys.argv[1:]\n"
        "if '--dev' in args:\n    args += [" + repr("--dev-preferences-dir=" + str(sandbox / "preferences")) + "]\n"
        "if any(a.startswith('--dev-slot=p') for a in args):\n"
        "    args = ['--script', " + repr(str(sandbox / "tests/scent_client_driver.gd")) + "] + args\n"
        "elif '--ai-debug' in args:\n"
        "    args = ['--script', " + repr(str(sandbox / "tests/search_ai_driver.gd")) + "] + [a for a in args if a != 'res://dev/ai/ai_debug_window.tscn']\n"
        "elif '--senses-debug' in args:\n"
        "    args = ['--script', " + repr(str(sandbox / "tests/senses_window_driver.gd")) + "] + [a for a in args if a != 'res://dev/senses/senses_window.tscn']\n"
        "os.execvp(" + repr(args.godot) + ", [" + repr(args.godot) + "] + args)\n")
    wrapper.chmod(0o755)
    # A blind Orc keeps the scenario deterministic: with working eyes the two creatures may
    # find each other first, and a creature pursuing a visible opponent rightly ignores smell.
    command = [sys.executable, str(sandbox / "tools/dev_session.py"), "--godot", str(wrapper), "--odin", args.odin,
        "--p1", "archer", "--p2", "orc", "--seed", "42", "--watch", "0", "--arena", "scent_trail",
        "--qa-arena", "client/dev/fixtures/content/scent_trail.arenas.json",
        "--qa-senses", "client/dev/fixtures/content/blind_tracker.senses.json"]
    if not args.graphical: command.append("--headless")
    return command


def field_cells(traces: Path) -> tuple[int, int, dict]:
    """The published host field: its publication time and the number of cells holding scent."""
    value = read(traces / "scent.json")
    field = value.get("field", {})
    if not field.get("valid"): return int(value.get("published_us", -1)), -1, field
    painted = 0
    width, height = int(field["width"]), int(field["height"])
    layers = [base64.b64decode(layer) for layer in field["levels"]]
    for index in range(width * height):
        if any(layer[index] for layer in layers): painted += 1
    return int(value["published_us"]), painted, field


def sample_trail(scent, timeout: float = 90) -> list[dict]:
    """Follow the trainer while it lays its trail: one position sample every 0.2 s until the driver says done."""
    deadline = time.monotonic() + timeout
    samples = []
    while time.monotonic() < deadline:
        state = scent(1)
        phase = state.get("trail_phase")
        if "trainer" in state and phase in ("approach", "retreat"):
            samples.append({"phase": phase, "position": state["trainer"], "tick": state["tick"]})
        if phase == "done": return samples
        time.sleep(0.2)
    raise AssertionError("Timed out: trainer finished laying its trail")


def human_levels(traces: Path) -> tuple[dict, list[int]]:
    """The published field and its Human layer as bytes."""
    value = read(traces / "scent.json")
    field = value.get("field", {})
    if not field.get("valid"): return field, []
    return field, list(base64.b64decode(field["levels"][0]))


def trail_wake(traces: Path, samples: list[dict], final: list[float]) -> dict:
    """Human levels under the path the trainer walked, read from the host publication only."""
    field, levels = human_levels(traces)
    width, tile = int(field["width"]), float(field["tile_size"])
    cells = []
    for sample in samples:
        cell = (int(sample["position"][0] // tile), int(sample["position"][1] // tile))
        if cells and cells[-1]["cell"] == list(cell): continue
        distance = math.dist(sample["position"], final) / tile
        cells.append({"cell": list(cell), "phase": sample["phase"], "tiles_from_final": round(distance, 2), "level": levels[cell[1] * width + cell[0]]})
    current = (int(final[0] // tile), int(final[1] // tile))
    return {"field_tick": field["tick"], "published_us": read(traces / "scent.json")["published_us"], "cells": cells,
            "current_cell": list(current), "current_level": levels[current[1] * width + current[0]]}


def far_from_emitters(cell: list[int], state: dict, final: list[float], tile: float = 32, tiles: float = 3) -> bool:
    """A walked cell that no body (trainer or creature) stands near, so only decay can change its level."""
    centre = [(cell[0] + 0.5) * tile, (cell[1] + 0.5) * tile]
    points = [final] + [c["position"] for c in state.get("creatures", [])]
    return all(math.dist(centre, p) >= tiles * tile for p in points)


def decay_candidates(wake: dict, state: dict, final: list[float]) -> list[dict]:
    return sorted((c for c in wake["cells"] if c["level"] >= 10 and far_from_emitters(c["cell"], state, final)), key=lambda c: -c["level"])


def smell_reading(state: dict, scent_class: str) -> dict:
    for row in state.get("scent_readings", []):
        if row["class"] == scent_class: return row
    return {}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--odin", default="odin")
    parser.add_argument("--graphical", action="store_true")
    args = parser.parse_args()
    sandbox = ROOT / "build/verification" / f"scent-{time.strftime('%Y%m%d-%H%M%S')}-{os.getpid()}"
    sandbox.mkdir(parents=True)
    print(f"Scent verification: {sandbox}", flush=True)
    command = prepare(args, sandbox)
    prior = set()
    first_recording = None
    expected = ((False, False), (True, False))  # (P1 scent field, P2 scent field) at each launch
    for attempt in (1, 2):
        process = None
        try:
            with (sandbox / f"runner-{attempt}.log").open("w") as log:
                process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            paths = lambda: set((sandbox / "build/dev").glob("*/session.json")) - prior
            wait(lambda: paths(), "fresh scent session")
            session_path = next(iter(paths()))
            prior.add(session_path)
            session = read(session_path)
            directory = session_path.parent
            traces = Path(session["ai_trace_dir"])
            scent = lambda owner: read(directory / f"scent-p{owner}.json")
            search = lambda owner: read(directory / f"search-p{owner}.json")
            senses = lambda owner: read(directory / f"senses{owner}.json")
            wait(lambda: all(scent(i).get("scent_preferences", {}).get("path") for i in (1, 2)), "saved scent preference binding")
            for i in (1, 2):
                flags = scent(i)["scent_preferences"]["flags"]
                assert flags["field"] == expected[attempt - 1][i - 1] and not scent(i)["scent_preferences"]["error"], scent(i)
                assert scent(i)["scent"]["enabled"] == expected[attempt - 1][i - 1]
            assert session["senses_slots"] == ["senses1", "senses2"] and session["ai_slots"] == ["ai1", "ai2"]
            if args.graphical and attempt == 1: native_windows(sandbox, session)
            wait(lambda: all(senses(i).get("olfaction_status") == "LIVE" and senses(i).get("record", {}).get("olfaction", {}).get("status") == "Sampled" for i in (1, 2)), "live nose samples in both senses windows", 30)
            if attempt == 1:
                first_recording = traces / "match.replay.jsonl"
                for owner in (1, 2):
                    state = senses(owner)
                    check_bound_olfaction(state, state["record"], journal_records(traces, owner))
                assert senses(1)["record"]["own_emitter"]["class"] == "Human" and senses(2)["record"]["own_emitter"]["class"] == "Orc"
                assert senses(2)["record"]["vision"]["status"] == "Disabled" and senses(2)["status"] == "DISABLED", "The staged blind tracker must report disabled eyes, not an empty view"
                assert senses(1)["record"]["vision"]["status"] == "Sampled" and senses(1)["status"] == "LIVE"
                assert senses(2)["record"]["olfaction"]["profile"]["range"] > senses(1)["record"]["olfaction"]["profile"]["range"], "The orc nose must reach farther"
                # The 30 x 16 arena is 512 units tall and ringed by trees: a 256-unit reach always meets unmeasurable ground.
                orc_nose = senses(2)["record"]["olfaction"]
                check_coverage(senses(2), orc_nose)
                assert orc_nose["coverage"].count("Sampled") < 16 and orc_nose["coverage"].count("Sampled") > 0, orc_nose["coverage"]
                # F6 on in both windows so the private search evidence is visible; the trail comes from P1's trainer.
                (directory / "search-command.json").write_text(json.dumps({"sequence": 1, "slots": ["p1", "p2"]}))
                wait(lambda: all(search(i).get("enabled") and search(i).get("readings") == 2 for i in (1, 2)), "F6 live search overlay")
                (directory / "scent-command.json").write_text(json.dumps({"sequence": 1, "slots": ["p1"], "action": "lay_trail", "target_owner": 2}))
                samples = sample_trail(scent)
                assert any(s["phase"] == "retreat" for s in samples), "trainer never turned back"
                # Moving emitter: the published field holds a wake under the path, behind the trainer's current position.
                final = scent(1)["trainer"]
                wait(lambda: field_cells(traces)[2].get("tick", 0) >= scent(1)["tick"] - 60, "field published after the walk")
                wake = trail_wake(traces, samples, final)
                behind = [c for c in wake["cells"] if c["tiles_from_final"] >= 2]
                assert len(behind) >= 4 and wake["current_level"] > 0, wake
                scented = [c for c in behind if c["level"] > 0]
                assert len(scented) >= 0.8 * len(behind), f"the wake is missing under the walked path: {wake}"
                candidates = decay_candidates(wake, scent(1), final)
                assert candidates, f"no walked cell away from every body: {wake}"
                wake_taken = time.monotonic()
                wait(lambda: smell_reading(senses(2), "Human").get("strength") not in (None, "None"), "the orc smells generic human scent after the trainer left", 20)
                reading = smell_reading(senses(2), "Human")
                assert reading["observation_id"] >= 2 ** 31 and "position" not in reading, reading
                check_coverage(senses(2), senses(2)["record"]["olfaction"])
                (sandbox / "orc-human-reading.json").write_text(json.dumps({"reading": reading, "senses2": senses(2)["record"]["olfaction"]}, indent=2))
                # Every orc decision is journaled, so a brief scent transition cannot be missed; a
                # visual cue of the trainer may first spend the shared weak-evidence budget and cooldown.
                trail_tick = scent(1)["tick"]
                def scent_decisions():
                    return [r for r in journal_records(traces, 2) if r["input"]["tick"] >= trail_tick and r["after"]["search"]["evidence"] in ("Scent", "Scent_Memory")]
                wait(lambda: scent_decisions(), "the orc's private search acts on the smell", 90)
                decision = scent_decisions()[0]
                evidence = decision["after"]["search"]
                assert evidence["scent"]["valid"] and evidence["scent"]["class"] == "Human" and evidence["transition"] in ("Scent_Trail", "Scent_Presence"), evidence
                (sandbox / "scent-search-evidence.json").write_text(json.dumps({"tick": decision["input"]["tick"], "search": evidence, "live_overlay": scent(1).get("search_evidence", {})}, indent=2))
                # The trace explains the transition with the scent observation it referenced.
                reference = decision["after"]["search"]["scent"]["observation_id"]
                assert any(node["reference"] == reference and node["status"] == "Selected" for node in decision["nodes"]), decision["nodes"]
                assert decision["after"]["search"]["acquisition_count"] == decision["before"]["search"]["acquisition_count"], "Smell alone acquired a target"
                # Host heatmap: F8 in P1 only; what it draws is the published field, cell for cell.
                (directory / "scent-command.json").write_text(json.dumps({"sequence": 2, "slots": ["p1"], "action": "toggle_scent"}))
                wait(lambda: scent(1)["scent"]["enabled"] and scent(1)["scent"]["painted_cells"] > 0 and not scent(1)["scent"]["stale"], "host scent heatmap enabled and painted")
                assert not scent(2)["scent"]["enabled"], "F8 in P1 changed P2's window"
                assert scent(1)["scent_preferences"]["flags"]["field"] and not scent(2)["scent_preferences"]["flags"]["field"]
                seen = {}
                def heatmap_matches():
                    published, painted, _ = field_cells(traces)
                    if painted >= 0: seen[published] = painted
                    shown = scent(1)["scent"]
                    return shown["published_us"] in seen and seen[shown["published_us"]] == shown["painted_cells"]
                wait(heatmap_matches, "drawn cells equal the published field for the same publication", 20)
                published, painted, field = field_cells(traces)
                assert field["round_id"] == scent(1)["round"] and field["width"] == 30 and field["height"] == 16, field
                assert (traces / "scent.json").stat().st_size <= 96 * 1024
                # Inspector minimap: both senses windows draw the same published cells, from their own bounded readers.
                def minimap_matches():
                    published_now, painted_now, _ = field_cells(traces)
                    if painted_now >= 0: seen[published_now] = painted_now
                    fields = [senses(i).get("scent_field", {}) for i in (1, 2)]
                    return all(f.get("status") == "LIVE" and f.get("published_us") in seen and seen[f["published_us"]] == f.get("painted_cells") for f in fields)
                wait(minimap_matches, "minimap cells equal the published field in both senses windows", 20)
                for owner in (1, 2):
                    field_state = senses(owner)["scent_field"]
                    assert field_state["matches"] and field_state["width"] == 30 and field_state["height"] == 16 and 1 <= field_state["rebuilds"] <= field_state["polls"], field_state
                # Decay as published: the strongest walked cell away from the trainer must lose level with time.
                time.sleep(max(0.0, 12 - (time.monotonic() - wake_taken)))
                later = trail_wake(traces, samples, final)
                still_far = [c for c in candidates if far_from_emitters(c["cell"], scent(1), final)]
                assert still_far, f"every walked cell gained a body nearby: {candidates}"
                decay_cell = still_far[0]
                later_level = next(c["level"] for c in later["cells"] if c["cell"] == decay_cell["cell"])
                assert later["field_tick"] > wake["field_tick"] and later_level < decay_cell["level"], (decay_cell, later_level, later["field_tick"], wake["field_tick"])
                (sandbox / "moving-emitter-trail.json").write_text(json.dumps({"samples": samples, "wake": wake, "decay_cell": decay_cell, "later_level": later_level, "later_field_tick": later["field_tick"], "seconds_between": round(time.monotonic() - wake_taken, 1), "minimap": {f"senses{i}": senses(i)["scent_field"] for i in (1, 2)}}, indent=2))
                (sandbox / "scent-field.json").write_text(json.dumps({"published_us": published, "painted_cells": painted, "field": {k: v for k, v in field.items() if k not in ("levels", "ages")}}, indent=2))
                if args.graphical:
                    (directory / "scent-command.json").write_text(json.dumps({"sequence": 3, "slots": ["p1"], "action": "capture", "label": "scent-heatmap"}))
                    wait(lambda: (directory / "p1-scent-heatmap.png").exists(), "rendered heatmap capture")
                    (directory / "senses-driver.json").write_text(json.dumps({"sequence": 1, "capture_only": True}))
                    wait(lambda: all((directory / f"senses{i}-{label}.png").exists() for i in (1, 2) for label in ("olfaction", "olfaction-local", "memory", "live")), "rendered senses page captures with the trail on the arena field")
                # F7 reset: the field and both noses start over in the new round; nothing teleports a trail.
                previous_round = scent(1)["round"]
                (directory / "search-command.json").write_text(json.dumps({"sequence": 2, "slots": ["p1"], "action": "reset"}))
                wait(lambda: all(scent(i).get("round", 0) == previous_round + 1 for i in (1, 2)), "reset-button click and synchronized new round")
                wait(lambda: field_cells(traces)[2].get("round_id") == previous_round + 1, "published field rebound to the new round")
                _, painted_after, _ = field_cells(traces)
                assert 0 <= painted_after <= 12, f"The new round started with an old trail: {painted_after} cells"
                wait(lambda: all(senses(i)["record"].get("round_id") == previous_round + 1 for i in (1, 2)), "senses windows rebound to the new round")
                for owner in (1, 2):
                    fresh = senses(owner)["record"]["olfaction"]
                    assert fresh["round_id"] == previous_round + 1 and int(fresh["reading_count"]) <= 1, fresh
                assert scent(1)["scent"]["enabled"] and search(1)["enabled"], "Reset changed saved debug toggles"
            else:
                wait(lambda: all(search(i).get("enabled") for i in (1, 2)), "restored F6 settings")
                assert scent(1)["scent"]["enabled"] and not scent(2)["scent"]["enabled"], "Saved scent heatmap settings did not survive restart"
                wait(lambda: scent(1)["scent"]["painted_cells"] > 0, "restored heatmap paints the new run's field")
            for log in (directory / "generation-1").glob("*.log"):
                text = log.read_text()
                assert "SCRIPT ERROR:" not in text and "ERROR:" not in text, (log, text[-2000:])
        finally:
            if process is not None: stop(process)
    checked([args.godot, "--headless", "--path", str(first_recording.parent.parent / "client"),
        "--script", str(ROOT / "tests/scent_replay_check.gd"), "--", "--fixture=" + str(first_recording)], sandbox / "replay-check.log")
    print("PASS: real trainer trail, blind-orc anonymous human reading, smell-driven private search with trace references, no smell acquisition, host heatmap equal to the published field, independent saved F8/F6 settings across restart, F7 clearing the round and recorded olfaction replay.", flush=True)


if __name__ == "__main__":
    main()
