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

Credentials and preferences are stored in `~/.config/claude-usage/`:

### Credentials

- `session-key` — from browser DevTools > Application > Cookies > claude.ai > sessionKey
- `org-id` — auto-discovered from session key, or manually from lastActiveOrg cookie

### Preferences (`prefs.json`)

Edit directly or use the Settings dialog. Restart the app after changing poll interval.

```json
{
  "pollIntervalSeconds": 60,
  "menuBarDisplay": "percentages",
  "menuBarFontSize": 14,
  "pieSize": 26,
  "pieGap": 5,
  "piePadLeft": 8,
  "piePadRight": 6,
  "yellowAtPace": 0.80,
  "redAtPace": 0.90,
  "colorGreen": "#5CD88A",
  "colorYellow": "#F0DC5A",
  "colorRed": "#FF2D2D",
  "showSonnet": false,
  "yellowEnabled": true,
  "yellowDays": 3,
  "redEnabled": true,
  "redDays": 0
}
```

**Display**

| Key | Default | Description |
|-----|---------|-------------|
| `menuBarDisplay` | `"percentages"` | `"percentages"`, `"pies"`, or `"icon"` |
| `menuBarFontSize` | `14` | Font size for percentage text mode |
| `pieSize` | `26` | Diameter of pie charts (pixels) |
| `pieGap` | `5` | Gap between the two pie charts |
| `piePadLeft` | `8` | Left padding for pie pair |
| `piePadRight` | `6` | Right padding for pie pair |

**Pacing**

| Key | Default | Description |
|-----|---------|-------------|
| `yellowAtPace` | `0.80` | Go yellow when usage reaches 80% of pace |
| `redAtPace` | `0.90` | Go red when usage reaches 90% of pace |

Pace = fraction of window elapsed. If you're 50% through the window, pace is 50%. Yellow at 80% of that (40% usage), red at 90% (45% usage). The pie geometry shows time vs usage visually — color tells you whether you're on track to run out.

**Colors**

| Key | Default | Description |
|-----|---------|-------------|
| `colorGreen` | `"#5CD88A"` | Comfortable — well under pace |
| `colorYellow` | `"#F0DC5A"` | Caution — approaching pace |
| `colorRed` | `"#FF2D2D"` | Danger — at or over pace |

**Session key expiry warnings**

| Key | Default | Description |
|-----|---------|-------------|
| `showSonnet` | `false` | Show Sonnet usage in dropdown menu |
| `yellowEnabled` | `true` | Show yellow warning when session key is expiring |
| `yellowDays` | `3` | Days before expiry to show yellow warning |
| `redEnabled` | `true` | Show red warning when session key is expiring |
| `redDays` | `0` | Days before expiry to show red warning |

**Polling**

| Key | Default | Description |
|-----|---------|-------------|
| `pollIntervalSeconds` | `60` | How often to poll claude.ai (seconds) |

Edit the file directly, or ask your human to ask you to update it. You know what you want.

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

Inspired by [linuxlewis/claude-usage](https://github.com/linuxlewis/claude-usage). OAuth endpoint and Claude Code credential discovery learned from [hamed-elfayome/Claude-Usage-Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker). This is an independent implementation — no code was shared.

---

Yes, that's an em dash. We use em dashes around here.
