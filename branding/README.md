# PerfChecker visual identity

The mark is generated from Julia source with Luxor.jl. It represents the core
PerfChecker workflow as a discrete comparison plot: package versions, a local
development target, and a Git commit are placed on the x axis; speed,
allocations, garbage-collection cost, network traffic, and CI test coverage are
attached directly to their traces. Coverage is CI evidence, not a PerfChecker
workload backend.
Each straight segment joins two measured targets, so the slope changes only at
an observed version or revision.

The segmented border uses the familiar Julia green, blue, purple, and red while
remaining an original PerfChecker mark.

## Regenerate

```sh
julia --project=branding -e 'using Pkg; Pkg.instantiate()'
julia --project=branding branding/generate_logo.jl
```

Generated files live in `branding/exports`. The script also refreshes the
DocumenterVitepress hero asset. Keep the source, SVG master, 1024 px PNG, light
and dark lockups, and preview sheet in sync.
