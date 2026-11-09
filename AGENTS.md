# voice-agent-ios

## Apple workflow through Argent

For Apple/iOS app work, use the existing shared Argent MCP for simulator interaction, visual acceptance, debugging and profiling. First read `D:\Workspace\Active\ios-deploy-engine\DEPLOYING.md` section **Argent-assisted Apple workflow**. Builds use the Mac's existing Xcode toolchain; signing/upload use the existing deployment engine. Argent does not replace either. Reuse the global Codex MCP entry; do not install project-local Argent or run its initializer/updater. Preserve other sessions and follow existing authorization and verification stopping rules.

Keep repository-specific instructions here. Do not store secrets, credentials, or deployment state in tracked files.
## Agent file conventions

This repository uses the shared, canonical agent-documentation layout. Do not invent alternative handoff or journal filenames.

| File | Purpose | Update rule |
|---|---|---|
| `AGENTS.md` | repo rules and session-close contract | rarely, deliberately |
| `CLAUDE.md` | Claude-only overrides (optional) | rarely |
| `docs/NEXT-SESSION.md` | the handoff: shipped, open, next repo and prompt | every session end |
| `memory/journal.md` | chronological work log | every session end |
| `.session/scratchpad.md` | ignored per-session working state | overwritten each session |

Durable facts, decisions, and cross-repository knowledge belong in `C:\Workspace\Active\brain`, not in additional repo-memory files.

## Prepare for session close

1. Check `git status`; never use `git add -A` or `git add .` on a dirty tree. Stop and report unrelated changes.
2. Update touched documentation so it matches reality.
3. Append what happened and what remains to `memory/journal.md`; put durable cross-repo facts in the brain vault.
4. Update `docs/NEXT-SESSION.md` with **Shipped**, **Open**, and **Next session** (exact repo and starting prompt).
5. If the next step is unclear, ask rather than guessing.
6. Report `Next session: <repo>`, `Prompt: <prompt>`, and `Start it?`.
