# Opponent search: ownership and flow

See [the feature record](../06m-naturalistic-opponent-search.md) for player-facing behavior, tuning and QA.

`simulation_tick` binds one `Battle_Runtime` per round and one private agent per creature. The scenario seed, round and entity initialize a separate random stream in `agent_reset`. Default simulations select `Search`; the explicit development/test Observe mode preserves the stationary visual receptor regressions.

`senses_prepare` samples the frozen pre-action world separately for each observer. `battle_tick` constructs a `Decision_Context` with self condition and that observer's `Sense_Input`. The host hands a by-value `Agent`, context and configuration to each dedicated worker. `server/ai` imports the data-only observations contract and cannot access host map/session objects.

`agent_decide` routes to `search_decide`. Its phases are deliberately separate:

1. Existing visual memory ingests only new samples and ages old observations.
2. `search_interpret_scent` turns the private scent memory into one candidate smell, discounting same-class zones that point at the searcher's own recent visits ([olfaction](olfaction.md)). `search_read_evidence` then chooses a state and retains original observation times: focused creature, remembered focused position, visual cue, smell (`search_follow_scent`), local-search budget, extensive search. A cue or a smell only supplies a bearing hypothesis; its local search center is the observer's own position when investigation begins, never an invented coordinate.
3. `search_remember_visit` updates only places actually occupied. Fixed arrays bound memory and keep worker requests self-contained. `search_memory_strength` decays old visit penalties using simulation ticks.
4. `search_choose_heading` scores eight local directions when a leg ends or evidence/blocked feedback interrupts it. Scores use private continuity, a private random draw, permitted evidence, a local radius preference and remembered penalties. A long relocation resamples the broad heading. No candidate is checked against a hidden terrain map.
5. `character_resolve_intent` alone changes world state. Existing terrain collision, sliding and walk preparation remain authoritative. A zero roam radius means no spawn leash; positive limits remain available and tested for other actions.
6. `search_record_result` remembers failed local directions. A successful slide can still report a partial block, so the next decision can choose another direction.

Repeated weak evidence has two clocks: the short receptor-memory lifetime and a fixed investigation episode. A continuously refreshed anonymous cue may justify looking, but cannot restart the episode forever. Budget exhaustion temporarily suppresses weak cues; focused targets remain eligible. This is deliberately fallible hypothesis management, not hidden identification of the cue source.

Search profiles are stored separately in the agents even though initial values are equal. Long-term learning does not exist yet. Adding it requires a durable individual identity distinct from player slot and temporary entity ID, evidence provenance, bounded storage, versioning and explicit lifecycle tests.

The debug writer receives its own copies after action resolution. `dev_search.odin` publishes the latest two lifecycle-matched search records; it does not enrich beliefs from the host world. The arena search overlay reads that small file only when enabled. The AI Search tab uses the selected recorded trace and labels it as recorded. Neither UI can submit an AI decision. Senses inspectors read the separate observation-only feed for Vision and the existing search feed for their Exploration memory page.

## Live exploration-memory display

`senses_window.gd` owns an `exploration_memory_panel.gd` instance bound to its player. The panel polls `search.json` at most every 100 ms during normal updates, even if its tab or the arena's F6 overlay is hidden. A lifecycle change triggers an immediate read. The shared search reader validates the run, fingerprint, size, records and publication order. Its accepted world identity must match the senses feed before the panel displays memory.

`exploration_memory.gd` selects the assigned owner and checks active round, map and entity. It copies only self position, profile limits and the occupied visit entries. It never forwards target beliefs, opponent positions, action scores or the other agent's history to the map. A changed identity clears old data while the sources catch up; a same-identity read failure retains a dimmed, explicitly stale view.

Visit age is the unsigned 32-bit difference between the record's simulation tick and `visited_tick`. Strength uses the same linear decay as `search_memory_strength`; expired entries are omitted. No wall-clock interpolation changes the memory. Both publication freshness and per-creature decision progress are checked, so a running heartbeat cannot disguise a frozen agent. The status reports stale after 750 ms and disconnected after three seconds without a new publication.

`exploration_memory_map.gd` fits a north-up grid around that creature's remembered regions and self position. A square marks the region containing a visit; its dot marks the exact last occupied position. It does not imply full region coverage. Region numbers link the map to table rows and are not a chronological route. The `opponent_seen` marker belongs to the latest visit stored in that region, not to durable encounter learning. Empty space means unvisited or forgotten. There is no terrain/world query in this view.

The table updates its bounded rows in place, keeps selection by region and shows the selected visit's age and remaining decay time. The map emits a region selection and cannot write to the simulation. QA status stores only the current projected memory, freshness, selection and peak read time. Tests compare both live projections against their own journals; production presentation never loads those journals.

`search_preferences.gd` saves a boolean per player window in Godot user storage. Both the arena and that player's AI inspector reload that setting. The run/generation directory is deliberately absent from its identity so a launcher restart preserves it. Test processes supply their own absolute directory. Preferences affect displays only; release/ordinary game flows do not load the debug overlay.

Acquisition becomes a minimal public presentation signal: a flag and original simulation tick, appended by protocol 10. No target identity, position or memory is added to that signal. `target_alert.gd` renders the replaceable texture; `replay_stage.gd` uses the recorded flag/tick so seeks and pauses do not restart a local timer. Historical protocol 9 is accepted only by `decode_recorded`, which supplies inactive markers; live transport still requires the current protocol.

## Development search reset

`search_reset_control.gd` sends a reliable `Dev_Reset_Search` command with the expected round, never client-selected coordinates. `session_apply` checks the welcomed player and round. `dev_search_reset` additionally requires a debug build, a local development host with the Search controller, and completed summoning. Concurrent old-round clicks cannot reset the new round again.

`dev_search_reset_placements` computes safe spawn pairs before mutating anything. A bounded host-only flood fill checks connected ground with the larger required footprint, including elevation transitions; a farthest-point sweep chooses separated creature/trainer groups. This operation creates no path for a creature and shares no world knowledge with its brain. A failed placement leaves the session untouched.

Successful reset reuses `session_enter_arena` for fresh entity IDs and clean action/presentation state, then installs the validated positions. The new round makes `battle_sync` rebuild both private brains and receptors before their next decision. Existing round handling clears client prediction and old live readings; recorded replay retains the old and new rounds. The host logs the reset round, creature positions and separation. Saved display preferences and native windows are independent of this lifecycle.
