# Julia RC and nightly campaigns

A package release comparison and a Julia runtime comparison answer different
questions. Runtime campaigns keep the package source, workloads and measurement
definitions fixed while changing Julia itself.

## Prepare Julia channels

PerfChecker does not install Julia versions implicitly. With juliaup, make the
desired channels available first:

```sh
juliaup add release
juliaup add rc
juliaup add nightly
```

Then probe each runtime from a fresh process. The evidence records the resolved
Julia version, Julia commit, binary directory and LLVM version.

## Run from the CLI

```sh
perfchecker julia-campaign \
  --suite=perf/suite.jl \
  --baseline=release \
  --candidate=rc \
  --candidate=nightly \
  --profile=ci \
  --reports=perf/julia-campaign \
  --limit=julia.wall.time=0.05 \
  --min-samples=10 \
  --progress=jsonl
```

Each runtime gets a child controller and normal isolated feature workers. Startup
files and history files are disabled. The campaign is resumable with
`--resume=true` after an interrupted nightly or remote run.

## Use explicit runtime specs

```julia
specs = [
    JuliaRuntimeSpec(:stable, "release"; role = :baseline),
    JuliaRuntimeSpec(:next, "rc"; role = :candidate),
    JuliaRuntimeSpec(:nightly, "nightly"; role = :candidate),
]

campaign = run_julia_runtime_campaign(
    specs;
    suite = "perf/suite.jl",
    reports = "perf/julia-campaign",
    profile = :ci,
    relative_limits = Dict("julia.wall.time" => 0.05),
    min_samples = 10,
)
```

`source = :executable` can point at an explicit Julia binary when juliaup is not
the deployment mechanism.

## Attribute a regression

```julia
investigation = investigate_julia_regressions(campaign;
    max_frames = 50, obvious_share = 0.6)
write_julia_investigation(investigation, "perf/julia-campaign/investigation")
```

PerfChecker ranks source lines whose sampled CPU or allocation weight increased,
and classifies them as Julia runtime code or package/dependency code. Failure
reports retain the first useful stack frames and distinguish launch, resolver,
test and timeout failures.

::: warning Attribution is not causality
A dominant Base, stdlib or compiler frame is a candidate for reduction. It is
not proof of a Julia bug. PerfChecker deliberately reports when evidence is only
ranked and insufficient for an automatic minimal working example.
:::

## Produce a useful Julia issue

Keep the campaign evidence and reduce in this order:

1. one package feature and one check type;
2. the smallest deterministic fixture that preserves the delta;
3. the stable and candidate runtime identities;
4. the effective project/manifest and hardware context;
5. a short command that reproduces the result;
6. the ranked source/profile artifact as supporting evidence.

This distinguishes “the package is slower under the candidate runtime” from a
maintainer-ready report about where the difference appears.
