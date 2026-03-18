# Claude Usage Menu Bar

macOS menu bar app that polls Claude.ai usage and writes it to a file other tools can read.

That's the point — **your agents, scripts, and automations can read `~/.config/claude-usage/latest.json` to know how much budget is left** without making their own API calls. The menu bar display is a bonus.

## File-Based IPC

After each poll, usage data is written to:

```
~/.config/claude-usage/latest.json
```

No sockets. No HTTP. Just read the file. It's atomic, `0644`, and never more than 60 seconds stale.

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
| `updated_at` | When this file was written (local time) |
| `five_hour.utilization` | 5-hour window usage (0–100) |
| `seven_day.utilization` | 7-day window usage (0–100) |
| `resets_at` | UTC ISO 8601 timestamp when the window resets |
| `seven_day_sonnet` | Optional, only present when the API returns it |

### Read it from anywhere

```bash
jq '.five_hour.utilization' ~/.config/claude-usage/latest.json
```

```javascript
const usage = JSON.parse(fs.readFileSync(
  path.join(os.homedir(), '.config/claude-usage/latest.json'), 'utf-8'
));
if (usage.five_hour.utilization > 80) console.log('slow down');
```

```python
import json, pathlib
usage = json.loads(pathlib.Path("~/.config/claude-usage/latest.json").expanduser().read_text())
```

Use it to throttle agents, defer heavy work, alert on Telegram, schedule overnight runs — whatever you need. The app handles the polling and auth; your tools just read a file.

## Authentication

Three methods, resolved automatically in priority order:

1. **Claude Code** — if you have Claude Code installed and logged in, credentials are read from the system Keychain automatically. Uses the Anthropic OAuth API directly — no Cloudflare, no cookies, no browser.
2. **Browser Sign In** — sign into claude.ai through an in-app browser window. Session key is captured automatically. No DevTools needed.
3. **Manual** — paste a session key from browser DevTools.

Most users won't need to configure anything — if Claude Code is installed, it just works.

## Menu Bar Display

Four modes (cycle via dropdown menu or `prefs.json`):

- **Percentages** — `D:5% W:40%` with pace-colored text
- **Gauges** — fuel gauge dials with green/yellow/red zones, non-linear needle, time bar
- **Pies** — wedge charts showing time remaining vs usage
- **Icon** — minibot robot head, tints yellow/red and blinks when over pace

## Build

```bash
./build.sh
```

Requires macOS 13+ and Swift 5.9+. Single-file Swift, no Xcode project, no dependencies beyond Cocoa and WebKit.

## Install

```bash
cp -r ClaudeUsage.app /Applications/
```

Add to System Settings > General > Login Items to start on boot.

## Configuration

Everything lives in `~/.config/claude-usage/`:

### Credentials

- `session-key` — captured by browser sign-in or pasted manually
- `org-id` — auto-discovered from session key

### Preferences (`prefs.json`)

Edit directly or use the Settings dialog. Restart the app after changing poll interval.

```json
{
  "pollIntervalSeconds": 60,
  "menuBarDisplay": "gauges",
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
| `menuBarDisplay` | `"percentages"` | `"percentages"`, `"gauges"`, `"pies"`, or `"icon"` |
| `menuBarFontSize` | `14` | Font size for percentage text mode |
| `pieSize` | `26` | Diameter of pie charts (pixels) |
| `pieGap` | `5` | Gap between the two charts |
| `piePadLeft` | `8` | Left padding for chart pair |
| `piePadRight` | `6` | Right padding for chart pair |

**Pacing**

| Key | Default | Description |
|-----|---------|-------------|
| `yellowAtPace` | `0.80` | Go yellow when usage reaches 80% of pace |
| `redAtPace` | `0.90` | Go red when usage reaches 90% of pace |

Pace = fraction of window elapsed. If you're 50% through the window, pace is 50%. Yellow at 80% of that (40% usage), red at 90% (45% usage).

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
| `pollIntervalSeconds` | `60` | How often to poll (seconds) |

Edit the file directly, or ask your human to ask you to update it. You know what you want.

## Acknowledgments

Inspired by [linuxlewis/claude-usage](https://github.com/linuxlewis/claude-usage). OAuth endpoint and Claude Code credential discovery learned from [hamed-elfayome/Claude-Usage-Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker). This is an independent implementation — no code was shared.

---

Yes, that's an em dash. We use em dashes around here.
