# Daily development log cleanup

[`tools/purge_logs.py`](../tools/purge_logs.py) removes generated diagnostics older
than **24 hours**. Preview before running it manually:

```sh
python3 tools/purge_logs.py --dry-run
python3 tools/purge_logs.py --apply
python3 tools/purge_logs.py --apply --older-than-hours 72
```

It scans `build/`, `logs/` and `replays/` for runtime `.log` files, rotated AI journals,
AI snapshots and `*.replay.jsonl` recordings. It skips active development/verification
runs, source/dependency directories, symlinks and any directory containing `.keep-logs`.
It rechecks activity, file identity and modification time before deletion. A lock
prevents overlapping cleanup invocations. Default execution is a dry run.

To retain a QA recording beyond the normal period, create `.keep-logs` in its run
directory. Remove that marker when the investigation is complete. Source files,
screenshots, staged projects, imported art and executables are outside this log-only
cleanup; large build artifacts still require a separate deliberate cleanup policy.

Installed in **burpazor's user crontab on 2026-09-10**, daily at **03:30 Asia/Manila**
(the machine's current timezone). The existing cron service was verified active.

```cron
30 3 * * * /usr/bin/python3 /home/burpazor/Code/Personal/BulbaZorua/OnlineGameDevAssetArena/tools/purge_logs.py --apply --older-than-hours 24 > /home/burpazor/Code/Personal/BulbaZorua/OnlineGameDevAssetArena/build/log-cleanup.log 2>&1
```

The entry is enclosed by `BEGIN/END OnlineGameDevAssetArena log cleanup` comments.
Other crontab entries are preserved. The previous crontab is saved privately at
`build/crontab-before-log-cleanup.txt`. The cleanup report is overwritten each run,
so it does not grow indefinitely. Check it at `build/log-cleanup.log`; `crontab -l`
shows the installed schedule. If this repository moves, update the two absolute paths.
Cron runs when the PC is on; it does not replay a missed run after shutdown.

Verification: `python3 tests/log_cleanup_check.py` passed three tests covering deletion, retention,
active-run, pinned-directory, source-preservation, dry-run and symlink cases in a
temporary workspace. A real temporary process protects its old log until exit.
A real dry run found 55 eligible old files (132,659 bytes) and
deleted nothing. The installed crontab was read back and compared to the intended entry.
