# Claude Usage Menu Bar

macOS menu bar app that shows your Claude.ai usage pacing at a glance.

Polls the Claude.ai usage endpoint every 60 seconds and displays pace-colored percentages in the menu bar. Green means you're under pace, yellow means you're approaching it, red means you're over.

## Menu Bar

```
✦ D12% W39%
```

- **D** — 5-hour window utilization
- **W** — 7-day window utilization
- Colors based on pacing within each window, not raw percentage

## Dropdown

- Per-window usage with time remaining until reset
- Session key expiry tracking
- Clickable "Updated" timestamp to force refresh

## Features

- Pace-based coloring (proportional threshold — works correctly at any point in the window)
- Session key rotation (automatically captures new keys from Set-Cookie)
- Session key expiry warnings (configurable yellow/red thresholds)
- Optional Sonnet usage display
- File-based IPC — writes `~/.config/claude-usage/latest.json` after each poll so other tools can read usage data without any sockets or HTTP
- First-launch setup dialog with org ID auto-discovery
- Single-file Swift, no Xcode project, no dependencies beyond Cocoa

## Build

```bash
./build.sh
```

Requires macOS 13+ and Swift 5.9+.

## Install

```bash
cp -r ClaudeUsage.app /Applications/
```

Add to System Settings > General > Login Items to start on boot.

## Configuration

Credentials are stored in `~/.config/claude-usage/`:

- `session-key` — from browser DevTools > Application > Cookies > claude.ai > sessionKey
- `org-id` — auto-discovered from session key, or manually from lastActiveOrg cookie

## Acknowledgments

Inspired by [linuxlewis/claude-usage](https://github.com/linuxlewis/claude-usage). This is an independent implementation — no code was shared.
