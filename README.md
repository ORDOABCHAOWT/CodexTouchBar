# CodexTouchBar

A lightweight native macOS companion that shows active Codex tasks and ChatGPT Codex quota windows as colored glass blocks on MacBook Pro Touch Bar models.

## First-version scope

- Up to three active Codex sessions, showing workspace name, current phase, and elapsed time.
- Tap any task block to open its exact `codex://threads/<id>` page in the Codex desktop app.
- Five-hour and weekly remaining quota, including reset time, from the official local Codex App Server protocol.
- A Monterey-style glass treatment: flat translucent color, a fine luminous border, and rounded corners—without gradients.
- Reserved space at both ends so native playback and system controls are not visually crowded.
- A built-in on-screen preview that uses the exact same views as the physical Touch Bar.
- No prompt or transcript collection. No third-party runtime dependencies.

## Important Touch Bar limitation

Apple only exposes public Touch Bar APIs to the foreground app. Persistent presentation while Codex is foreground therefore uses dynamically resolved, undocumented DFRFoundation and AppKit selectors. The app falls back to its on-screen preview if those APIs are unavailable after a macOS update.

## Build and test

```bash
swift run CodexTouchBarCoreChecks
./scripts/build_app.sh
```

The app bundle is written to `dist/CodexTouchBar.app`.

## Task status connection

Launch the app, then choose **Install Codex Status Connection** from its menu. The app adds a clearly marked block to `~/.codex/config.toml`, leaving a Harness-managed `hooks.json` symlink and all unrelated settings untouched. Removing the connection deletes only that marked block.

## Privacy model

The hook helper accepts only:

- session id
- turn id
- hook event name
- workspace basename
- canonical tool name
- event time

It ignores transcript paths, absolute working directories, prompts, responses, tool inputs, tool outputs, models, and permission mode. Status is transferred through a user-only Unix socket and kept in memory.

## Third-party acknowledgement

The private Control Strip technique was cross-checked against Alexsander Akers' MIT-licensed `touch-baer` example. No third-party source is bundled at runtime.
