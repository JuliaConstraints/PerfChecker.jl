# Run bundles

`perfchecker-run-bundle/1` is the durable boundary between measurement workers
and every consumer. It is self-contained and language-neutral.

```text
run-directory/
├─ manifest.json
├─ measurement-definitions.json
├─ observations.jsonl
├─ diagnostics.jsonl
├─ artifacts.json
├─ integrity.json
└─ artifacts/
```

## Contents

- `manifest.json`: run/attempt identity, state, suite plan, runtime,
  environment, capabilities, timestamps, reuse key, and warnings;
- `measurement-definitions.json`: versioned meaning, unit, preference, method,
  scope, and comparability of each metric;
- `observations.jsonl`: numeric or categorical evidence with comparison keys and
  attributes;
- `diagnostics.jsonl`: compatibility failures, collector warnings, attribution
  findings, and other non-observation evidence;
- `artifacts.json`: metadata for profiles, plots, logs, and provider artifacts;
- `integrity.json`: SHA-256 and byte length for every immutable protocol file.

Large files live under `artifacts/`; metadata should carry media type,
sensitivity, and provenance. Integrity covers the protocol documents, while
artifact-specific digests belong in artifact records.

## Julia API

```julia
bundle = read_run_bundle("perf/results/bundles/run-123")
verify_run_bundle("perf/results/bundles/run-123"; require_integrity = true)

bundle_passed(bundle)
bundle_dict(bundle)
list_run_bundles("perf/results"; recursive = true)
```

`write_run_bundle` writes to a temporary sibling and atomically renames the
directory. It refuses to overwrite an existing destination. `migrate_run_bundle`
rewrites supported legacy data into a new destination rather than mutating the
source in place.

## Identity and reuse

`run_id` is the logical experiment; `attempt_id` identifies one physical
attempt. A content-derived `reuse_key` describes the normalized plan, runtime,
and measurement definitions. Reused evidence must remain labelled as reused and
must never silently impersonate a fresh run.

Consumers must verify integrity, schema version, completion state, diagnostic
severity, measurement-definition identity, and semantic outcome before making a
regression decision.
