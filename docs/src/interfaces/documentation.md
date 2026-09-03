# Documenter integration

PerfChecker can materialize selected run evidence inside any documentation
project without rerunning the workload during the docs build. The selection is
described by the same language-neutral query grammar used by Oxygen and agents.

## Build one performance page

```julia
using PerfChecker, Documenter

bundle = read_run_bundle("perf/results/bundles/release")
query = PerformanceQuery(
    id = "parser-latency",
    resources = [:observations, :comparison, :plots],
    predicates = [
        QueryPredicate("package", :equals, "BibParser"),
        QueryPredicate("feature", :equals, "parse_bibtex"),
        QueryPredicate("metric", :equals, "julia.wall.time"),
    ],
)
block = PerformanceDocumentBlock(
    "parser-latency",
    "BibParser latency",
    query;
    views = [:summary, :comparison, :plots],
    interactive_url = "https://perf.example/runs/release",
)

documenter_page(bundle, "docs/src/generated/performance.md"; blocks = [block])
```

Call `documenter_makedocs` or `documenter_vitepress_makedocs` when you want the
adapter to materialize blocks immediately before the normal documentation build.
The generated `perfchecker-document-block/1` model retains the query result,
requested views, interactive link, run identity, runtime, and environment.

## Shared declarative configuration

VS Code and the web studio can save documentation blocks beside UI selections in
`perf/perfchecker-ui.json`:

```json
{
  "schema_version": "perfchecker-ui-config/1",
  "selection": { "run_ids": ["example-run"] },
  "documentation": {
    "blocks": [{
      "schema_version": "perfchecker-document-block/1",
      "id": "network-budget",
      "title": "Network budget",
      "views": ["summary", "observations", "plots"],
      "query": {
        "schema_version": "perfchecker-query/1",
        "id": "network-budget",
        "resources": ["observations", "plots"],
        "where": [{
          "field": "metric",
          "operator": "prefix",
          "value": "network."
        }],
        "order_by": [],
        "limit": 100
      }
    }]
  }
}
```

`read_document_blocks` validates this file. Other documentation systems can
consume `performance_document_block(bundle, block)` directly; they do not need
Julia-specific rendering logic.

## Publication rules

- Publish immutable or explicitly refreshed bundles, never an unlabelled local
  “latest” directory.
- Show runtime, source/dependency provenance, measurement definition, and
  freshness near the chart.
- Link to the interactive studio for deep inspection, but preserve a static
  Markdown/SVG fallback.
- Redact logs, local paths, tokens, packet captures, and private endpoints before
  public documentation.
- Keep documentation generation read-only with respect to the measured project.
