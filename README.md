# CodexTouchBar

A lightweight native macOS companion that shows active Codex tasks and ChatGPT Codex quota windows as colored glass blocks on MacBook Pro Touch Bar models.

## First-version scope

- Up to six active Codex desktop or CLI tasks, detected from local status metadata and showing the same compact display title as Codex's task list, plus phase and elapsed time. Request bodies are never used directly as labels. Blocks expand into unused Touch Bar space and compress equally as more tasks appear.
- The app bundle includes the supplied Codex Touch Bar icon.
- Tap any task block to open its exact `codex://threads/<id>` page in the Codex desktop app.
- Five-hour and weekly remaining quota, including reset time, from the official local Codex App Server protocol.
- A Monterey-style glass treatment: flat translucent color, a fine luminous border, and rounded corners—without gradients.
- Actual previous, play/pause, and next-track controls grouped together on the left, without Accessibility or Input Monitoring permission.
- Native AppKit button hit-testing and press feedback for every interactive control; the first physical touch sends the action and status blocks fill the available Touch Bar region proportionally.
- The private modal bar is shown only while `com.openai.codex` is frontmost and is dismissed when another app becomes active, restoring the system Touch Bar.
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

The layout follows Apple's Touch Bar guidance: use AppKit controls and convenience sizing, let the system manage constrained composition, and use a principal item instead of hard-coded centering. See Apple's [NSTouchBar](https://developer.apple.com/documentation/appkit/nstouchbar?changes=l_11), [NSTouchBarItem](https://developer.apple.com/documentation/appkit/nstouchbaritem?language=objc), and [Buttons HIG](https://developer.apple.com/design/human-interface-guidelines/buttons).

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

It ignores transcript paths, absolute working directories, prompts, responses, tool inputs, tool outputs, models, and permission mode. Status is transferred through a user-only Unix socket and kept in memory. The desktop-task fallback reads only task IDs and timestamps from Codex's local log index, then resolves the compact `display_title` maintained by Codex's local task catalog. It never uses generated database `title`, `preview`, first-message, or log-body fields as labels, and never writes task data to disk.

## Third-party acknowledgement

The private Control Strip technique was cross-checked against Alexsander Akers' MIT-licensed `touch-baer` example. No third-party source is bundled at runtime.
