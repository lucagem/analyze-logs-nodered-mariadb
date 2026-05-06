# Log Analyzer

Desktop Flutter app that ingests Docker-container CSV logs from **MariaDB**
and **Node-RED**, plus an optional MariaDB **slow query log**, and produces a
Markdown report of suspicious events: errors, warnings, exceptions, slow
queries, restarts, and (optionally) an AI-generated executive summary.

The tool is read-only: it never writes back to the source files and never
sends raw log lines to a remote service. The only network call happens — if
explicitly enabled — to the Anthropic API, with an *aggregated digest*
(counts, categories, top excerpts), never the raw log corpus.

---

## Features

- File pickers for one MariaDB CSV, one or more Node-RED CSVs, and an
  optional MariaDB slow-query log.
- Optional `from` / `to` date-time picker; the effective window is the
  intersection with the CSV span and is also applied to the slow log so
  events stay temporally correlated.
- Rule-based detection of suspicious events with severity ranking
  (CRITICAL / ERROR / WARN), restart detection, repeating-query bursts.
- Markdown report with summary, severity breakdown, restart timeline,
  per-source sections, and top-N slow queries.
- Optional AI Insights (Anthropic API) appended as a final report section.
- Rules and thresholds configurable in [`assets/rules.json`](assets/rules.json).
- Multi-platform Flutter desktop build (Windows, macOS, Linux).

## Quick start

```bash
# 1. Install Flutter 3.x and a desktop toolchain (VS Build Tools on Windows,
#    Xcode CL on macOS, GTK/clang on Linux).
flutter pub get

# 2. Run on the host platform
flutter run -d windows     # or -d macos / -d linux

# 3. (Optional) Run the headless smoke test against ./examples
dart run tool/smoke.dart
```

The first run lands on the home screen. Pick at least one log file —
**Analyze** activates as soon as one source is present.

## Usage

1. **MariaDB container CSV** — pick the single MariaDB stdout/stderr export.
2. **Node-RED container CSVs** — add one entry per Node-RED port (1880, 1881,
   1882, 1883, …); the slot is repeatable.
3. **MariaDB slow query log** — optional `.log` (or `.txt`) MySQL/MariaDB
   slow-log file.
4. **Time range** — optional. Both fields take date+time. The effective
   window is `intersect(CSV-span, [from, to])`; the slow log is then filtered
   to that window. This matters because slow logs typically cover a much
   wider period than container logs and would otherwise dominate the report.
5. **Analyze** — kicks off parsing → rule matching → Markdown rendering. The
   report opens in an in-app viewer with **Copy** and **Save to disk**
   actions; saved reports land in `<Documents>/log-analysis/report-*.md`.

## Settings

Open the gear icon in the top-right.

- **Anthropic API key** — required only for AI Insights. Stored in
  `<applicationSupportDir>/settings.json` as plain text. Treat the host
  machine as part of the trust boundary; OS user-account permissions are
  the only protection.
- **Model** — `claude-opus-4-7`, `claude-sonnet-4-6` (default), or
  `claude-haiku-4-5-20251001`.
- **Include AI Insights** — when on (and the key is set), every analysis
  appends an `## AI Insights` section based on a digest, never raw lines.

## Configuring rules

`assets/rules.json` ships with a curated default rule set. Edit it to add /
remove patterns or change thresholds, then rebuild. See
[`docs/RULES.md`](docs/RULES.md) for the full schema and the matching
semantics (first-match-wins per line, specific rules listed before generic
catch-all rules).

## Input file formats

See [`docs/FILE_FORMATS.md`](docs/FILE_FORMATS.md) for the expected layout of
the container CSV exports and the MariaDB slow-query log.

## AI Insights

See [`docs/AI_INSIGHTS.md`](docs/AI_INSIGHTS.md) for what is sent to
Anthropic, the prompt structure, and how to disable / replace it.

## Project layout

```
lib/
├── analyzers/    # rule matcher, slow-query analyzer, orchestrator
├── models/       # LogEvent, SuspiciousEvent, AnalysisResult, RulesConfig…
├── parsers/      # container CSV parser, MySQL slow-log parser
├── reporters/    # Markdown reporter
├── services/     # Anthropic client, settings, rules loader
└── ui/           # home, report, settings screens
assets/
└── rules.json    # editable rule set
tool/
└── smoke.dart    # headless analyzer test against ./examples
```

## Limitations and known caveats

- API key storage is plaintext on disk. If you need encryption-at-rest, swap
  [`SettingsService`](lib/services/settings_service.dart) for a
  Keychain/DPAPI-backed implementation.
- A given log line emits **one** suspicious event — the first matching rule
  in declaration order wins. Reorder `rules.json` if you need a different
  precedence.
- The slow-log parser handles timestamps with the legacy `YYMMDD HH:MM:SS`
  format (`YY < 70` → `20YY`) **and** prefers `SET timestamp=<epoch>` when
  present.

## License

Internal tool — no public license attached.
