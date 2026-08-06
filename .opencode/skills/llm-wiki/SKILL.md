---
name: llm-wiki
description: "Use for TCG Cheap knowledge-base/wiki work: raw ingest, codebase updates, queries, and lint."
---

# TCG Cheap LLM Wiki

Maintain the persistent, LLM-readable TCG Cheap knowledge base. **Every path in
this skill is under `knowledge-base/`**; never create root-level `raw/` or
`wiki/` directories.

## Structure and initialization

- `knowledge-base/raw/` contains immutable external or pasted source captures.
- `knowledge-base/wiki/<topic>/<article>.md` contains compiled articles.
- `knowledge-base/wiki/index.md` is the global index; `log.md` is newest-first.

On first ingest, create only missing `raw/.gitkeep`, `wiki/index.md` (heading
`# Knowledge Base Index`), and `wiki/log.md` (heading `# Wiki Log`). Never
overwrite existing content. Keep wiki topics one directory deep.

## Ingest

For external or pasted sources, preserve the source in a dated raw file with
source/collection metadata, then compile it into a wiki article. Raw files are
immutable. Do not create raw files for product-owner plans or ordinary
codebase changes: those are durable wiki articles with `Raw: N/A — product
specification` or `Raw: N/A — codebase update`.

Every article must have exactly recognizable metadata fields:

```markdown
- Updated: YYYY-MM-DD
- Sources: ...
- Raw: ...
```

Use paths relative to the article. Keep durable articles linked with a `See
Also` section where useful. Update the index for every article, including its
link, summary, and date. Add a newest-first operation entry to `log.md`.

## Codebase updates

Read the index first, update an existing article when possible, and record
durable architecture, product, behavior, limitations, and validation state.
Do not make ordinary codebase changes into external raw captures. Refresh
metadata/index entries when content changes and add a newest-first log entry
with task, files, validation, and remaining notes.

Current and superseded north-star articles are first-class durable product articles. Query and update the current north star when planning or implementing product work; never silently narrow its requirements. Mark an article superseded only on explicit product-owner direction.

## Query

Read the index and relevant articles before answering. Prefer wiki knowledge
over unstated assumptions and cite answers with project-root-relative markdown
links such as `[Foundation](knowledge-base/wiki/architecture/application-foundation.md)`.
Queries do not write files unless explicitly requested.

## Deterministic lint

Check that every article has valid metadata, every indexed article exists and
every article is indexed, and all internal markdown links resolve. Validate
Raw links separately against `knowledge-base/raw/` (and only if present,
other explicitly cited source artifacts under `knowledge-base/`). Fix
deterministic missing-index, metadata, and path issues when unambiguous;
report heuristic issues such as stale claims, contradictions, or orphan pages.
Append a newest-first lint entry with issue and auto-fix counts. Do not add
archive, battle-log, or handoff workflows unless a future TCG Cheap request
explicitly requires them.
