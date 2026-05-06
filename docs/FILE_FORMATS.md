# Input file formats

This document describes the exact layout the analyzer expects for each
input file. Sample files of every format live under [`../examples/`](../examples).

## 1 · MariaDB / Node-RED container CSV

Both the MariaDB and the Node-RED CSVs share the same structure — only the
content differs. The first line is the container name (free-form) and is
discarded; the second line is the CSV header.

```
gi4_mariadb
date,stream,content
2026/05/04 10:43:28,stderr,2026-05-04 10:43:28 0 [Warning] mariadbd: io_uring_queue_init() failed
2026/05/04 10:43:28,stderr,2026-05-04 10:43:28 0 [Warning] InnoDB: liburing disabled: falling back…
…
```

| Column    | Type   | Notes                                                                |
|-----------|--------|----------------------------------------------------------------------|
| `date`    | string | `yyyy/MM/dd HH:mm:ss`. Used as the canonical event timestamp.        |
| `stream`  | string | `stdout` or `stderr`. Preserved on the parsed event but not filtered. |
| `content` | string | Raw log line. May span multiple lines if quoted with `"`.            |

### Edge cases handled by the parser

- **Multi-line content** — any quoted `content` field that contains embedded
  newlines is parsed as a single record. Common in TLS certificates dumped
  by Node-RED or in MSSQL connection strings.
- **Blank rows** between records are skipped silently.
- **Malformed rows** (fewer than 3 columns, unparseable date) are counted
  and surfaced as a parser warning in the report header — they never abort
  the analysis.
- **Windows line endings** (`\r\n`) are normalized.

## 2 · MariaDB slow query log

The analyzer accepts the standard MySQL/MariaDB slow-query log layout:

```
mariadbd, Version: 11.8.2-MariaDB-ubu2404-log (mariadb.org binary distribution). started with:
Tcp port: 0  Unix socket: /run/mysqld/mysqld.sock
Time		    Id Command	Argument
# Time: 251114 14:53:24
# User@Host: root[root] @  [172.18.0.1]
# Thread_id: 3414  Schema: GI4  QC_hit: No
# Query_time: 0.577709  Lock_time: 0.017307  Rows_sent: 1  Rows_examined: 3871
# Rows_affected: 1000  Bytes_sent: 153
use `GI4`;
SET timestamp=1763128404;
SELECT fe_LotDopoLotNew('599ac3e77230fcfccead22a481e73094');
```

### Parsing rules

- **Timestamp** is taken from `SET timestamp=<epoch>` when present (epoch
  seconds), otherwise from the most recent `# Time: YYMMDD HH:MM:SS` line.
  For the legacy header, `YY < 70` maps to `20YY`; otherwise to `19YY`.
- A block without `# Time:` inherits the previous one's timestamp — this is
  standard MariaDB behavior.
- The banner sequence `mariadbd, Version: …` / `Tcp port: …` /
  `Time\tId Command\tArgument` is **always** treated as a server restart
  marker; banner lines are skipped (never parsed as queries).
- `# User@Host:` is decoded into `user` and `host` (the IP in brackets).
- `use \`SCHEMA\`;` updates the current schema and is *not* included in the
  SQL excerpt.
- The SQL text continues until either a `# Time:` / `# User@Host:` /
  banner line is encountered, at which point the previous block is
  flushed and a new one starts.
- Restarts outside the effective time window are filtered before rendering.

### Effective time window

The analyzer computes the effective range as
`intersect(CSV span, [user-from, user-to])` and applies it to **both** the
container CSVs and the slow log. If the slow log has no events in the
window, you'll see a `Slow log timestamps do not overlap…` warning at the
top of the report and no slow queries in the output. This is by design —
the typical slow log spans months and would otherwise drown out a 24-hour
container window.

## 3 · Empty / partial inputs

- The **Analyze** button activates as soon as one source is selected.
- The slow log is optional. If omitted, the report skips the slow-query
  sections entirely.
- The MariaDB CSV is optional too; you can run an analysis with only
  Node-RED logs.

## 4 · File-system gotchas

- On Windows, paths with non-ASCII characters or paths inside OneDrive may
  be slow to read. Prefer copying the logs to a local SSD path before
  analyzing 100MB+ files.
- The CSV parser holds the whole file in memory once. For very large files
  (>500MB) split them server-side first. The 2.8MB slow log in
  [`../examples/`](../examples) parses in ~250ms on commodity hardware.
