# CodexTouchBar development notes

- Keep the app native Swift/AppKit. Do not add Electron, Node, Python, Homebrew, or runtime package-manager dependencies.
- Never persist prompts, responses, transcript paths, tool inputs, tool outputs, absolute workspace paths, authentication tokens, or model names.
- Hook input is untrusted. Decode only the explicit allowlist in `HookPacket`.
- Touch Bar private APIs must be dynamically resolved and must fail closed to the on-screen preview when unavailable.
- Chrome integration may read front-window tab titles and numeric window/tab positions only in memory. Never read URLs or page contents, and never persist Chrome tab metadata.
- Installation and uninstallation must edit only CodexTouchBar-owned hook entries and must preserve unrelated Codex configuration.
- Build artifacts belong in `dist/`; never commit `.build/` or `dist/`.
