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
