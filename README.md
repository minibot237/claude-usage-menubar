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

## Integration

After each successful poll, the app writes usage data to:

```
~/.config/claude-usage/latest.json
```

Other tools can read this file to get current usage without making their own API calls. No sockets, no HTTP — just read the file.

### Schema (v1)

```json
{
  "v": 1,
  "updated_at": "2026-03-17T14:32:00-07:00",
  "five_hour": {
    "utilization": 42.5,
    "resets_at": "2026-03-17T18:00:00Z"
  },
  "seven_day": {
    "utilization": 15.3,
    "resets_at": "2026-03-20T00:00:00Z"
  },
  "seven_day_sonnet": {
    "utilization": 8.1,
    "resets_at": "2026-03-20T00:00:00Z"
  }
}
```

| Field | Description |
|-------|-------------|
| `v` | Schema version (integer, currently 1) |
| `updated_at` | When this file was written (Pacific time) |
| `five_hour.utilization` | 5-hour window usage (0–100) |
| `seven_day.utilization` | 7-day window usage (0–100) |
| `resets_at` | UTC ISO 8601 timestamp when the window resets |
| `seven_day_sonnet` | Optional, only present when the API returns it |

The file is written atomically (readers never see partial data) with `0644` permissions. Poll frequency is 60 seconds, so the file is never more than ~1 minute stale.

### Example: read from shell

```bash
jq '.five_hour.utilization' ~/.config/claude-usage/latest.json
```

### Example: read from Node

```javascript
const usage = JSON.parse(fs.readFileSync(
  path.join(os.homedir(), '.config/claude-usage/latest.json'), 'utf-8'
));
console.log(`5h: ${usage.five_hour.utilization}%`);
```

## Acknowledgments

Inspired by [linuxlewis/claude-usage](https://github.com/linuxlewis/claude-usage). This is an independent implementation — no code was shared.
