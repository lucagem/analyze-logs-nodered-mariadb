# Rules reference

The analyzer is rule-driven. All rules live in
[`assets/rules.json`](../assets/rules.json) and are loaded at app start. To
change rules, edit the file and rebuild (`flutter pub get && flutter run`).

## Top-level shape

```jsonc
{
  "version": 1,
  "description": "...",
  "mariadb":   { "patterns": [ ... ], "restartMarkerRegex": "...", "ignoreNoteCategories": [ ... ] },
  "nodered":   { "patterns": [ ... ], "restartMarkerRegex": "..." },
  "slowQuery": { "minQueryTimeSeconds": 1.0, ... },
  "report":    { "timelineLimit": 200, "excerptMaxChars": 240 }
}
```

## Pattern object

Each entry of `mariadb.patterns` and `nodered.patterns` is:

| Field         | Type    | Description                                                    |
|---------------|---------|----------------------------------------------------------------|
| `id`          | string  | Stable identifier shown in the report metadata.                |
| `regex`       | string  | Dart regex pattern. Inline `(?i)` is accepted and converted to `caseSensitive: false` automatically. |
| `severity`    | string  | One of `CRITICAL`, `ERROR`, `WARN`, `INFO`.                    |
| `category`    | string  | Free-form label aggregated under "By category".                |
| `description` | string  | Human-readable note (rendered nowhere by default — for documentation). |

### Matching semantics

- For each parsed log line the matcher iterates patterns **in declaration
  order** and emits **one** `SuspiciousEvent` for the first match. A line
  that matches `mdb_aborted` will not also match the generic `mdb_warning`.
- This is why the shipped order lists specific rules first
  (`mdb_oom`, `mdb_disk_full`, `mdb_crash`, …) and the catch-all rules
  (`mdb_error`, `mdb_warning`) last.
- Reorder freely. Just remember: more specific → first.

## AX_LOG state selection

`axLog` in `rules.json`:

| Key                      | Meaning                                                                |
|--------------------------|------------------------------------------------------------------------|
| `defaultIncludedStates`  | Array of STATE values flagged as suspicious when the UI does not override the choice. Default `[1, 2]` (WARNING + ERROR). |

State values are mapped as follows (hard-coded in `AxState`):

| STATE | Label    | Severity | Category    |
|-------|----------|----------|-------------|
| 0     | OK       | INFO     | AX ok       |
| 1     | WARNING  | WARN     | AX warning  |
| 2     | ERROR    | ERROR    | AX error    |
| 3     | DEBUG    | INFO     | AX debug    |

The home screen renders one `FilterChip` per state when at least one
AX_LOG file is selected; toggling a chip overrides
`defaultIncludedStates` for that single analysis run. In the report
viewer each AX state has its own background color (dark red for ERROR,
amber for WARNING, dark green for OK, blue-grey for DEBUG).

## Slow-query thresholds

`slowQuery` in `rules.json`:

| Key                              | Meaning                                                            |
|----------------------------------|--------------------------------------------------------------------|
| `minQueryTimeSeconds`            | Flag a query if its `Query_time` ≥ this value. Default `1.0`.       |
| `minLockTimeSeconds`             | Flag if `Lock_time` ≥ this. Default `0.5`.                          |
| `minRowsExaminedAbsolute`        | Selectivity check skipped unless `Rows_examined` ≥ this. Default `10000`. |
| `minRowsExaminedToSentRatio`     | Flag if `Rows_examined / Rows_sent` ≥ this. Default `1000`.         |
| `topN`                           | How many rows to render in "Top slow queries". Default `20`.        |
| `repeatWindowSeconds`            | Sliding-window size for repeat-burst detection. Default `60`.       |
| `repeatThreshold`                | Number of identical-fingerprint executions in the window that triggers a "repeated" warning. Default `5`. |

A query can flag multiple sub-categories at once (e.g. `Slow query`,
`Slow query · lock`, `Slow query · selectivity`, `Slow query · repeated`).
This is intentional — slow-query analysis is independent of the
first-match-wins rule above.

## Restart detection

- `mariadb.restartMarkerRegex` — default `ready for connections`. Matches
  the MariaDB startup banner.
- `nodered.restartMarkerRegex` — default `Started flows`.
- The slow-log parser additionally treats every `mariadbd, Version: …` /
  `Tcp port: …` / `Time\tId Command\tArgument` block as a restart marker
  (and skips its banner lines).

Restarts outside the effective time window are filtered out before
rendering.

## Default rule catalog

### MariaDB
| ID                | Severity  | Category             |
|-------------------|-----------|----------------------|
| `mdb_oom`         | CRITICAL  | Resource exhaustion  |
| `mdb_disk_full`   | CRITICAL  | Resource exhaustion  |
| `mdb_crash`       | CRITICAL  | Crash                |
| `mdb_deadlock`    | ERROR     | Concurrency          |
| `mdb_lock_wait`   | ERROR     | Concurrency          |
| `mdb_access_denied` | ERROR   | Authentication       |
| `mdb_innodb_error`  | ERROR   | Storage engine       |
| `mdb_aborted`     | WARN      | Connection           |
| `mdb_error`       | ERROR     | MariaDB error        |
| `mdb_warning`     | WARN      | MariaDB warning      |

### Node-RED
| ID               | Severity | Category           |
|------------------|----------|--------------------|
| `nr_unhandled`   | CRITICAL | Node.js exception  |
| `nr_fatal`       | CRITICAL | Node-RED fatal     |
| `nr_typeerror`   | ERROR    | Node.js exception  |
| `nr_referror`    | ERROR    | Node.js exception  |
| `nr_syntaxerror` | ERROR    | Node.js exception  |
| `nr_econnrefused`| ERROR    | Connection         |
| `nr_econnreset`  | WARN     | Connection         |
| `nr_etimedout`   | WARN     | Connection         |
| `nr_mssql_disc`  | WARN     | MSSQL connection   |
| `nr_opcua_pending` | WARN   | OPC-UA pending     |
| `nr_unencrypted` | WARN     | Security           |
| `nr_job_unexpected` | WARN  | Application        |
| `nr_error`       | ERROR    | Node-RED error     |
| `nr_warn`        | WARN     | Node-RED warning   |

## Adding your own rule

1. Append an object to the relevant `patterns` array.
2. Pick a stable `id` not already in use.
3. Place it **before** any rule it should preempt (more specific first).
4. Restart the app.

Example — flag any "table is full" message under its own bucket:

```json
{ "id": "mdb_table_full", "regex": "(?i)table\\s+is\\s+full", "severity": "ERROR",
  "category": "Resource exhaustion", "description": "MyISAM/Aria table at capacity." }
```
