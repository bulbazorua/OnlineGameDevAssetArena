# Critical

- Keep this file's rules in active context for every prompt in this repo.
- Codex: do not access `CLAUDE.md`.
- Claude: do not access `AGENTS.md`.

## Code clarity and comments — hard rules

- Code must explain itself through clear names, focused responsibilities, and control/data flow that can be traced from entry point to outcome.
- Add comments only when complex, non-obvious code needs an explanation. Prefer a single line; omit comments that merely restate the code.
- Comments are for humans: use plain, simple words in an **ELI5 / oonga boonga style**. Explain the idea accurately in everyday language; avoid jargon and dense technical shorthand.
- A comment block must never exceed **3 physical lines**. This limit applies to consecutive line comments, block comments, and documentation comments. Do not split a long explanation into adjacent comment blocks to bypass the limit.
- If code is difficult to understand on its own or trace from start to finish, treat it as a refactoring candidate. Split it into focused, clearly named sub-procedures or functions when that makes the flow easier to follow.
- Improve unclear code instead of compensating with more comments.
- When code needs a deeper technical explanation, create or update a focused Markdown document under **`docs/codebase/`**. Explain the reasoning and flow in depth, reference the relevant code, and keep the explanation consistent with the implementation. Code comments stay short and simple.

## Development UI consistency - permanent rules

- Dev tools must use consistent layouts, controls, labels, visual meanings, and interactions so switching views does not require learning a different interface.
- Before implementing any new dev view or changing an existing one, check for a component that already displays similar data or provides a similar visual structure. Reuse its shared UI base where appropriate instead of building a parallel lookalike.
- Shared UI bases own common presentation and interactions, such as frames, layout, styling, coordinate transforms, and selection signals. Feature-specific data, state, validation, polling, interpretation, and behavior stay with that feature's adapter or controller.
- Give shared controls narrow, explicit display inputs and signals. They must not import feature-specific feeds, reach into another feature's internal state, or collect unrelated feature behavior behind mode switches.
- Vision and olfaction radars must share one radar UI component for their common frame, plot layout, compass, range guides, and presentation rules. Matching colors alone is not sufficient. Keep sense-specific geometry and data in focused adapters or drawing layers.
- Keep spacing, typography, selection styling, coordinate conventions, and status presentation consistent across consumers. Preserve actual sensor ranges and the meaning of each color or symbol; consistency must not hide differences in the data.
- Shared presentation must not merge data ownership, freshness clocks, or knowledge boundaries. Clearly distinguish developer-only world truth, delivered sensor readings, and private creature memory.
- If a suitable existing widget is tightly coupled to its feature, extract its small presentation base before reusing it. Do not make another feature depend on the original feature's internals just to share its appearance.
- Prefer small composed controls over a monolithic universal inspector or a new UI framework. Share what is genuinely common without forcing unrelated data or feature-specific details into the same model.
- Apply these rules to every future dev UI feature and to existing dev views touched by a refactor. Document reusable component ownership and usage under `docs/codebase/` when a deeper explanation is needed.
