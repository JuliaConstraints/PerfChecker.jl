```@raw html
---
layout: home

hero:
  name: "PerfChecker.jl"
  text: "Measure what actually runs"
  tagline: Deep, reproducible performance testing for Julia packages and complete software suites.
  image:
    src: /assets/perfchecker.svg
    alt: PerfChecker performance pulse
  actions:
    - theme: brand
      text: Start measuring
      link: /guide/first-check
    - theme: alt
      text: Explore the feature catalog
      link: /reference/checks
    - theme: alt
      text: View on GitHub
      link: https://github.com/Mirage-Interactive-Fr/PerfChecker.jl

features:
  - icon: "⚗️"
    title: Isolated measurements
    details: Every feature/version run gets a fresh Malt process without the controller or visualization stack.
    link: /software-suites
  - icon: "↔️"
    title: Versions and revisions
    details: Compare releases, working trees, branches, tags, commits and Julia stable/RC/nightly runtimes.
    link: /tutorials/comparisons
  - icon: "🔥"
    title: Deep attribution
    details: Inspect timings, allocations by line, typed flame graphs, native libraries and network traffic.
    link: /reference/checks
  - icon: "▦"
    title: Interactive everywhere
    details: Use VS Code, Oxygen, WGLMakie, Pluto, the REPL or generated documentation over one result grammar.
    link: /interfaces/vscode
  - icon: "✓"
    title: CI-ready evidence
    details: Produce integrity-protected bundles, JSONL, Markdown and JUnit, then gate on explicit regression budgets.
    link: /tutorials/ci
  - icon: "⌘"
    title: Agent-ready contracts
    details: Query precise evidence and exchange bounded, machine-readable results with human and AI workflows.
    link: /reference/run-bundles
---
```

## Performance checks as software tests

PerfChecker treats performance as a versioned contract attached to a **business
feature**. `import_bibtex`, `solve_model`, or `render_frame` is the feature;
BenchmarkTools, Chairmarks, allocation tracking, profiling and network accounting
are selectable ways to evaluate it. This separation keeps the suite readable and
lets every interface offer the same choices.

```text
software suite
  └─ package
      └─ business feature
          ├─ check type
          └─ target: release | working tree | branch | tag | commit
```

The controller resolves this plan, performs compatibility checks and launches
bounded workers. The measured worker loads only the target package, workload and
collector. Results return as a portable run bundle consumed by every UI and CI
adapter.

## Pick a path

<div class="feature-grid">
  <div><strong>I maintain one package</strong>Start with <a href="/guide/first-check">your first feature check</a>, then add versions and CI.</div>
  <div><strong>I maintain a software suite</strong>Model package boundaries and version pins in <a href="/software-suites">software suites</a>.</div>
  <div><strong>I am investigating a regression</strong>Compare <a href="/tutorials/comparisons">releases and Git revisions</a> or <a href="/tutorials/julia-runtimes">Julia runtimes</a>.</div>
  <div><strong>I need interactive analysis</strong>Choose <a href="/interfaces/vscode">VS Code</a>, <a href="/interfaces/web-studio">Oxygen</a>, or <a href="/interfaces/visualization">Makie</a>.</div>
  <div><strong>I run a hosted service</strong>Review the <a href="/operations/hosted">controller, authentication and remote-agent model</a>.</div>
  <div><strong>I build automation</strong>Consume <a href="/reference/run-bundles">run bundles</a> and <a href="/report-queries">bounded queries</a>.</div>
</div>

## Candidate status

PerfChecker `1.0.0-rc2` is a V1 release candidate. The package preserves the
original `@check` API while introducing feature suites, common protocols and
interactive tooling. The [V1 candidate page](v1-candidate.md) distinguishes the
implemented surface from longer-term roadmap items.

::: tip Mirage Interactive
PerfChecker is an open-source Mirage Interactive project built for the wider
Julia package ecosystem. Its documentation theme and contribution conventions
are intentionally reusable by future Mirage Interactive repositories.
:::
