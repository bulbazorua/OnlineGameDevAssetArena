# 6B.2 olfaction — assignment closed

Updated **2026-09-12**. **The corrected candidate passes Team Lead technical
re-review. R1–R3 are closed. There is no active coding assignment in this packet.**

The owner sends future assignments to the coding agent manually and returns the
report to the Team Lead for independent review. Do not restart these corrections
or begin the next sense from this completed packet.

## Accepted result

- Confirmed movement deposits scent on every crossed cell under the documented
  edge/corner convention, without painting untouched neighboring cells.
- Freshness comes from detectable scent; an undetectable fresh trace no longer
  makes an older detected trail appear fresh.
- Both live Olfaction pages distinguish measured, partly measured and unknown
  zones. Zero measured ground stays unknown. Coverage follows the delivered
  sample into diagnostics and recorded evidence.
- Anonymous scent classes, independent receptors/private memories, vision
  priority, six development windows, saved filters and reset behavior remain.

## Independent verification

The Team Lead reproduced the original regression passes in normal/debug builds,
inspected rendered coverage at both sizes, ran the full `make check` (exit 0,
42 PASS checks), and ran fresh graphical scent, senses and AI-debugger checks.
An actual older recording decodes and seeks without fabricated coverage.

Read [the technical review](06p-olfaction-team-lead-review.md) for the exact
results, evidence paths, memory qualifications and remaining limits. The
[implementation record](06n-olfactory-trails.md) and
[coding-agent report](06o-olfaction-coding-agent-report.md) explain the feature.
The [original assignment](06q-olfaction-original-delegation.md) is historical;
the completed correction packet is pinned beside the re-review evidence as
`delegation-before-rereview.md`.

## Owner manual QA

```sh
make dev_scent P1=archer P2=orc
```

Select **Olfaction** in each Senses window. **F8** toggles the separate host scent
field; **F4** opens its filters; **F7** resets the search. The implementation
record includes the blind-tracker option for testing smell without vision.

Physical keyboard/mouse and exported-release acceptance remain untested. The
review records the roughly 48-second recording cap, large AI-inspector memory
use and the display requirement for `make check`. These are follow-ups, not a
new implementation assignment. Keep changes unstaged and uncommitted unless the
owner explicitly requests otherwise.
