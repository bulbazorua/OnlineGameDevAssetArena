# Team Lead vision regression checks

These independent checks call the production perception and host APIs. They cover
requirements missed by the initial 6B.1 suite: both sides of a wall boundary,
accepted large sight ranges on small tiles, and replacement of just one creature.
They also check nearby clear/blocked controls and the replacement's empty memory.

Run from the repository root after the normal server build has prepared ENet:

```sh
odin test tests/vision_review -out:build/vision_review_tests -extra-linker-flags:"-L$(pwd)/build/deps"
odin test tests/vision_review -debug -out:build/vision_review_tests_debug -extra-linker-flags:"-L$(pwd)/build/deps"
```

At the initial Team Lead review on **2026-09-11**, both commands compiled and
exited 1: all three tests exposed contract failures. The harness was then outside
the existing Make targets. After correction, the unchanged tests pass in both
builds and are included in normal verification, as independently rechecked by the
Team Lead.

See [the review](../../docs/06i-vision-team-lead-review.md) and the current
[coding assignment](../../docs/delegation.md). Keep these assertions meaningful
through the correction; changing implementation is the coding agent's work.

## Routine verification (correction pass, 2026-09-11)

`make check_vision_review` runs both commands above. `make check_vision` and the full
`make check` include it, so the guarantees stay in the normal verification path. The
assertions are unchanged from the initial review.
