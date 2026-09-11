#!/usr/bin/env python3
"""Peak memory of the six-window development workload with recording enabled.
Launches tools/dev_session.py from a chosen tree, samples every launched process
(VmHWM, Pss, RSS) until the timed run ends, and writes a JSON and Markdown report."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


def status_kib(pid: int, key: str) -> int:
    try:
        for line in Path(f"/proc/{pid}/status").read_text().splitlines():
            if line.startswith(key + ":"):
                return int(line.split()[1])
    except OSError:
        pass
    return -1


def pss_kib(pid: int) -> int:
    try:
        for line in Path(f"/proc/{pid}/smaps_rollup").read_text().splitlines():
            if line.startswith("Pss:"):
                return int(line.split()[1])
    except OSError:
        pass
    return -1


def command_line(pid: int) -> str:
    try:
        return Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace").strip()
    except OSError:
        return ""


def role_of(pid: int, session: dict) -> str:
    for slot, owner in session.get("ai_pids", {}).items():
        if owner == pid: return slot
    for slot, owner in session.get("senses_pids", {}).items():
        if owner == pid: return slot
    text = command_line(pid)
    if "--dev-slot=" in text: return text.split("--dev-slot=")[1].split()[0]
    if "/host" in text.split(" ")[0]: return "host"
    return "process-%d" % pid


def wrapper_for(sandbox: Path, godot: str) -> Path:
    """Godot wrapper that keeps saved debug preferences inside the sandbox."""
    wrapper = sandbox / "godot-measure"
    wrapper.write_text("#!/usr/bin/env python3\nimport os, sys\nargs = sys.argv[1:]\n"
        "if '--dev' in args:\n    args += [" + repr("--dev-preferences-dir=" + str(sandbox / "preferences")) + "]\n"
        "os.execvp(" + repr(godot) + ", [" + repr(godot) + "] + args)\n")
    wrapper.chmod(0o755)
    return wrapper


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tree", default=str(ROOT), help="Repository root to launch from (a preserved baseline copy is allowed)")
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--odin", default="odin")
    parser.add_argument("--seconds", type=float, default=60)
    parser.add_argument("--p1", default="archer")
    parser.add_argument("--p2", default="orc")
    parser.add_argument("--arena", default="vision_range")
    parser.add_argument("--qa-arena", default="client/dev/fixtures/content/vision_range.arenas.json")
    parser.add_argument("--label", default="candidate")
    parser.add_argument("--output", default=str(ROOT / "build/verification/olfaction-fix-20260911/memory"))
    args = parser.parse_args()
    tree = Path(args.tree).resolve()
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    sandbox = output / f"{args.label}-run"
    sandbox.mkdir(exist_ok=True)
    wrapper = wrapper_for(sandbox, args.godot)
    known = set((tree / "build/dev").glob("*/session.json"))
    command = [sys.executable, str(tree / "tools/dev_session.py"), "--godot", str(wrapper), "--odin", args.odin,
               "--p1", args.p1, "--p2", args.p2, "--seed", "42", "--watch", "0", "--arena", args.arena,
               "--qa-arena", args.qa_arena, "--run-seconds", str(args.seconds)]
    started = time.monotonic()
    with (sandbox / "runner.log").open("w") as log:
        process = subprocess.Popen(command, cwd=tree, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    session_path = None
    while process.poll() is None and session_path is None and time.monotonic() - started < 180:
        fresh = set((tree / "build/dev").glob("*/session.json")) - known
        if fresh: session_path = fresh.pop()
        time.sleep(0.2)
    if session_path is None:
        process.kill()
        sys.exit("The development session never published session.json; see " + str(sandbox / "runner.log"))
    peaks: dict[int, dict] = {}
    samples = 0
    first_sample = None
    while process.poll() is None:
        session = read_json(session_path)
        pids = list(session.get("pids", [])) + list(session.get("ai_pids", {}).values()) + list(session.get("senses_pids", {}).values())
        for pid in pids:
            rss, hwm, pss = status_kib(pid, "VmRSS"), status_kib(pid, "VmHWM"), pss_kib(pid)
            if rss < 0: continue
            entry = peaks.setdefault(pid, {"role": role_of(pid, session), "command": command_line(pid)[:160], "peak_rss_kib": 0, "vm_hwm_kib": 0, "peak_pss_kib": 0, "samples": 0})
            entry["peak_rss_kib"] = max(entry["peak_rss_kib"], rss)
            entry["vm_hwm_kib"] = max(entry["vm_hwm_kib"], hwm)
            entry["peak_pss_kib"] = max(entry["peak_pss_kib"], pss)
            entry["samples"] += 1
        if pids and first_sample is None: first_sample = time.monotonic()
        samples += 1
        time.sleep(0.5)
    duration = time.monotonic() - (first_sample or started)
    session = read_json(session_path)
    report = {
        "label": args.label, "tree": str(tree), "arena": args.arena, "players": [args.p1, args.p2],
        "requested_seconds": args.seconds, "sampled_seconds": round(duration, 1), "sampling_passes": samples,
        "method": "Every 0.5 s: /proc/<pid>/status VmRSS and VmHWM plus /proc/<pid>/smaps_rollup Pss for the host, both clients, both AI debuggers and both senses windows. "
                  "Peak RSS and VmHWM include private and shared resident pages; Pss divides shared pages between sharers. "
                  "Excluded: GPU memory, kernel memory, page cache, the launcher and this script.",
        "windows": {"clients": session.get("slots", []), "ai": session.get("ai_slots", []), "senses": session.get("senses_slots", [])},
        "recording": session.get("replay_path", ""),
        "processes": sorted(peaks.values(), key=lambda entry: entry["role"]),
        "sum_vm_hwm_kib": sum(entry["vm_hwm_kib"] for entry in peaks.values()),
        "sum_peak_pss_kib": sum(entry["peak_pss_kib"] for entry in peaks.values()),
        "launcher_exit": process.returncode,
    }
    (output / f"{args.label}.json").write_text(json.dumps(report, indent=2) + "\n")
    lines = [f"# Peak memory · {args.label}", "", f"Tree `{tree}` · arena {args.arena} · {args.p1}/{args.p2} · {report['sampled_seconds']} s sampled · launcher exit {process.returncode}", "",
             "| Process | Peak RSS (MiB) | VmHWM (MiB) | Peak PSS (MiB) | Samples |", "| --- | --- | --- | --- | --- |"]
    for entry in report["processes"]:
        lines.append(f"| {entry['role']} | {entry['peak_rss_kib'] / 1024:.1f} | {entry['vm_hwm_kib'] / 1024:.1f} | {entry['peak_pss_kib'] / 1024:.1f} | {entry['samples']} |")
    lines += ["", f"Sum of VmHWM: {report['sum_vm_hwm_kib'] / 1024:.1f} MiB · sum of peak PSS: {report['sum_peak_pss_kib'] / 1024:.1f} MiB", "", report["method"]]
    (output / f"{args.label}.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
