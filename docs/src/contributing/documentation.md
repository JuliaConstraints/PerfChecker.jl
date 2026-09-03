# Documentation guide

PerfChecker's documentation structure and visual language are intended to be
reusable across future Mirage Interactive repositories, while each project keeps
its own domain content and API boundaries.

## Local build

```sh
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl
```

Documenter writes the intermediate Markdown site and DocumenterVitepress builds
the final static output. Treat warnings, dead links, missing docstrings, and
VitePress build failures as release blockers even though exploratory local
builds may use `warnonly`.

## Information architecture

- **Get started** explains the mental model and first successful run.
- **Tutorials** are complete, reproducible outcomes.
- **Interfaces** document one shared contract through different workflows.
- **Reference** states exact schemas, options, APIs, and limitations.
- **Operations** covers hosting, trust boundaries, and maintenance.
- **Roadmap** clearly separates implemented facts from proposals.

Do not duplicate feature claims across pages without linking to the canonical
reference. Never present a planned collector, platform, or attribution method as
implemented.

## Screenshot policy

Store images under `docs/src/assets/screenshots/<interface>/` or a similarly
specific folder. Use actual application output only—never a fabricated UI—and:

1. capture a fixed, readable desktop size and an additional narrow layout when
   responsive behavior matters;
2. remove tokens, private endpoints, usernames, local absolute paths, and private
   package data;
3. use stable demo bundles so screenshots can be regenerated;
4. provide descriptive alt text and a caption that explains the user outcome;
5. prefer SVG for diagrams, PNG/WebP for UI, and static Makie export for plots;
6. verify both light and dark themes when the component supports them;
7. refresh images when labels or flows change, not merely on every release.

Use the `doc-screenshot` figure class for consistent borders and captions.

## Reusable Mirage layer

The reusable layer is intentionally small: colour tokens, typography, navigation
depth, screenshot styles, contribution rules, and repository/footer metadata.
Project-specific suite examples, screenshots, schemas, and API pages remain in
their repository. Extract a shared theme package only after at least two real
repositories demonstrate the same stable contract.

## Pull-request checklist

- build DocumenterVitepress locally;
- check internal and external links;
- run doctests and package TestItems affected by examples;
- verify screenshots at their rendered size;
- scan for stale organization/repository identities;
- state which commands passed and which optional integrations were not exercised.
