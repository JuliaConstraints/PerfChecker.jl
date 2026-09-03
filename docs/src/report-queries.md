# Report queries and documentation blocks

`perfchecker-query/1` is the shared selection language for JSON/TOML tools,
Oxygen, documentation generators, notebooks, CI, and AI agents. It does not
contain Julia expressions and never launches a worker.

```julia
query = PerformanceQuery(
    id = "candidate-parser-regressions",
    resources = [:comparison, :plots, :diagnostics],
    predicates = [
        QueryPredicate("manifest.runtime.language", :equals, "julia"),
        QueryPredicate("package", :equals, "BibParser"),
        QueryPredicate("feature", :prefix, "parse"),
        QueryPredicate("metric", :one_of,
            ["julia.wall.time", "julia.alloc.bytes"]),
    ],
    order_by = ["relative_delta" => :desc],
    limit = 100,
)

result = query_bundle(bundle, query)
```

Fields can address a record directly, fall back to its `attributes`, or use a
`manifest.` prefix. The initial deterministic operators are `equals`,
`not_equals`, `one_of`, `contains`, `prefix`, `greater_or_equal`,
`less_or_equal`, and `exists`. Later schemas can add boolean groups and
ecosystem-specific semantic-version predicates without changing `/1`.

Oxygen exposes the same grammar through `POST /query`. It caps the request body
and result size. `POST /agent-evidence` returns a bounded
`perfchecker-agent-evidence/1` envelope and explicitly separates evidence from
authority: consuming a report does not authorize a rerun, code edit,
publication or issue submission.

## Portable documentation block

```julia
block = PerformanceDocumentBlock(
    "parser-performance",
    "BibParser performance",
    query;
    views = [:summary, :comparison, :diagnostics, :plots],
    interactive_url = "https://perf.example/runs/<run-id>",
)

model = performance_document_block(bundle, block)
documenter_page(bundle, "src/performance.md"; blocks = [block])
```

The `perfchecker-document-block/1` model contains the query result, requested
views, interactive link and run/runtime/environment provenance. Documenter and
DocumenterVitepress materialize it before their build; other documentation
systems can consume the same dictionary. Documentation rendering never executes
the measured workload.

The long-term report-view contract adds named datasets, facets, selections,
URL-serializable cross-filters and drill-down actions. A typical allocation path
is pie slice → file/line hotspots → allocation stack → source. Static Markdown
or SVG remains the fallback when the interactive renderer is unavailable.
