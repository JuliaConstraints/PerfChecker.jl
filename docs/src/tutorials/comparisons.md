# Compare versions and revisions

PerfChecker can compare released package versions, the current checkout, and
multiple Git branches, tags or commits in one plan. This supports parallel
implementation experiments without turning each implementation into a fake
business feature.

## Define candidates in Julia

```julia
candidates = [
    SuiteCandidate("parser-a", "feature/parser-a"),
    SuiteCandidate("parser-b", "91d3a2f4c0e8"),
    SuiteCandidate("release-candidate", "v0.5.0-rc1"),
]

package = PackageSuite(
    "MyParser";
    source = dirname(@__DIR__),
    environment = joinpath(@__DIR__, "runner"),
    versions = [v"0.3.0", v"0.4.0"],
    candidates,
    features,
)
```

`source` defaults to the package source. Supply a Git URL when a candidate lives
elsewhere. `compatibility_version` selects the feature variant used for a
revision whose declared version cannot represent its API surface:

```julia
SuiteCandidate(
    "api-redesign",
    "feature/api-redesign";
    source = "https://github.com/example/MyParser.jl.git",
    compatibility_version = v"0.5.0",
)
```

## Exact and grouped references

An exact policy compares a candidate to one reference:

```julia
ComparisonPolicy(
    "parser-a-vs-0.4";
    package = "MyParser",
    comparison_key = "parse-document/v1",
    baselines = ["0.4.0"],
    candidates = ["parser-a"],
)
```

A grouped policy summarizes several references before comparing candidates:

```julia
ComparisonPolicy(
    "experiments-vs-recent";
    package = "MyParser",
    comparison_key = "parse-document/v1",
    baselines = ["0.3.0", "0.4.0"],
    candidates = ["parser-a", "parser-b"],
    aggregation = :median,
)
```

Available aggregations are `:median`, `:mean`, `:minimum`, and `:maximum`.
Median is the usual default; minimum is useful only when “best observed
reference” is an intentional policy.

Attach policies to `SoftwareSuite(...; comparisons)` or provide them when
planning.

## Use the VS Code target picker

The visual suite editor scans the selected package repository and fills a native
drop-down grouped into branches, tags and recent commits. Selecting an entry
fills its revision and label. The free-form field also parses:

- plain Git references such as `feature/faster-parser`;
- `refs/heads/...`, `refs/tags/...`, and remote references;
- full GitHub or GitLab tree, tag and commit URLs;
- `owner/repository@reference` shorthand;
- full commit hashes.

After adding targets, the comparison matrix presents them beside release and
working-tree targets. Select one or several references, one or several
candidates, and the aggregation rule. Saving produces
`perfchecker-ui-config/1`, which the CLI can consume with `--config`.

## Use repeated CLI targets

```sh
perfchecker plan --suite=perf/suite.jl --profile=ci \
  --candidate='{"package":"MyParser","label":"parser-a","revision":"feature/parser-a"}' \
  --candidate='{"package":"MyParser","label":"parser-b","revision":"91d3a2f4c0e8"}'
```

For substantial configurations, prefer the shared UI configuration file over
shell-escaped JSON:

```sh
perfchecker run --suite=perf/suite.jl --profile=ci \
  --config=perf/perfchecker-ui.json --reports=perf/results/experiments
```

## Comparability rules

PerfChecker compares observations only when their measurement definitions and
`comparison_key` agree. Hardware, runtime, dependency and source identity remain
in the bundle so consumers can detect a confounded comparison.

Use a new comparison key when inputs, output semantics, warm-up policy or
measurement procedure changes. A missing result should remain `missing` or
`unavailable`; it must never be silently converted into an improvement.
