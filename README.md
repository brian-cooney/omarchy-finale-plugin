# Finale MTB Trail Status — Omarchy plugin

A bar widget for [Omarchy](https://omarchy.org) that shows the live
mountain-bike trail status for the **Finale Outdoor Region** (Finale Ligure,
Italy), with a detail panel listing the currently closed trails and the latest
notices from the official site.

- **Bar label** — a bike glyph plus a compact token, in the normal bar
  foreground colour:
  `✓` all open · `N` N trails closed · `✗` full-network closure · `…` unknown / stale.
- **Panel** (left click) — closed trails grouped by area with any "(until 2pm)"
  qualifiers, the reference date and fetch age, a stale warning when the source
  hasn't updated recently, the latest bulletins verbatim, and a link to the
  source page. Press `R` to refresh, `Esc` to close.
- **Middle click** refreshes; **right click** sends the summary as a notification.

## Data source

The widget does **not** scrape the website itself. A companion repo,
[`finale-mtb-status`](https://github.com/brian-cooney/finale-mtb-status), runs a
GitHub Actions cron job that scrapes
[`finaleoutdoor.com/en/live/bike`](https://www.finaleoutdoor.com/en/live/bike)
every 30 minutes and publishes a small `status.json` via GitHub Pages. This
plugin's only network call is a `curl` of that file (default every 30 min).

Rationale: parsing the CMS page in QML would be brittle and would break every
install at once on a markup change; a central scraper is fixed once, is polite
to a small tourism org's site, and serves last-known-good data with a timestamp.

## Install

```bash
omarchy plugin add https://github.com/brian-cooney/omarchy-finale-plugin.git --enable
```

Then add the **Finale MTB** widget to a bar section via the Omarchy bar
settings (or `~/.config/omarchy/shell.json`).

## Remove

```bash
omarchy plugin remove com.github.brian-cooney.finale-mtb
```

This disables the widget and deletes
`~/.config/omarchy/plugins/com.github.brian-cooney.finale-mtb`. The plugin
writes nothing outside that directory (no services, no files elsewhere), so
nothing else needs cleaning up.

### Local development

```bash
git clone https://github.com/brian-cooney/omarchy-finale-plugin.git \
  ~/.config/omarchy/plugins/com.github.brian-cooney.finale-mtb
omarchy-shell shell rescanPlugins
omarchy plugin enable com.github.brian-cooney.finale-mtb

# validate the manifest
omarchy plugin validate ~/.config/omarchy/plugins/com.github.brian-cooney.finale-mtb

# lint the QML against the installed shell (needs qt6-declarative)
./scripts/qmllint

# model unit tests (no Omarchy needed)
node test/model-test.js
```

`scripts/qmllint` reports no errors. It still prints `missing-property`
warnings for `bar.*`, the loaded panel, and `Style.font.*` — the shell injects
those objects untyped at runtime, so qmllint can't see their members.

## Settings

Per-widget keys in the `shell.json` layout entry:

| key                 | default                                                                 | meaning                                   |
|---------------------|-------------------------------------------------------------------------|-------------------------------------------|
| `jsonUrl`           | `https://brian-cooney.github.io/finale-mtb-status/data/status.json`          | status feed to poll                       |
| `refreshMinutes`    | `30` (min 5)                                                            | poll interval                             |
| `staleAfterMinutes` | `720` (min 60)                                                          | age of the feed's `checked_at` past which the reading is shown stale |
| `glyph`             | `` (nf-fa-bicycle)                                                     | label icon; set `""` for text only        |

## Files

| file            | role                                                                   |
|-----------------|-----------------------------------------------------------------------|
| `manifest.json` | plugin manifest (`kinds: ["bar-widget"]`)                             |
| `BarWidget.qml` | bar slot: renders the label, routes clicks, hosts the panel loader   |
| `Panel.qml`     | the `curl` loop, refresh/stale timers, and the detail popup UI       |
| `Model.js`      | pure parse/format helpers (unit-tested under node)                   |
| `test/`         | `model-test.js`                                                       |
| `scripts/`      | `qmllint` wrapper for local development                              |

## License

MIT — see [LICENSE](LICENSE).
