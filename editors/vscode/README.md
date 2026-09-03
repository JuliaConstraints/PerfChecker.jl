# PerfChecker for VS Code

PerfChecker turns a package's performance suite into a Test Explorer-style
workspace. It uses the same `perfchecker-suite-plan/1` contract as the Julia
REPL, CI, Oxygen, Pluto, Makie and documentation integrations.

## What the extension does

- Shows `package → business feature → check type → version` in both the
  PerfChecker activity view and VS Code Testing. Technical collectors such as
  allocations or profiling stay options of `import_bibtex`; they do not become
  fake business features such as `import_bibtex_allocations`.
- Lets developers select check types globally or per feature/version, filter
  version ranges, sort, colour-label, drag-and-drop, and run only the selection.
- Opens the exact Julia workload script from every check leaf.
- Adds visual-output and worker-log actions at suite, package, feature, check and
  version level. Native test runs also retain streamed Malt worker output.
- Displays BenchmarkTools and Chairmarks sample distributions, version curves,
  comparisons, allocation percentages by file/line, and allocation/CPU/wall-time
  flame graphs. Every small point, slice and flame cell is keyboard-focusable and
  has a detailed hover view; flame colours distinguish dispatch, unstable
  inference and garbage collection.
- Adds named Git targets for branches, tags and exact commits, then compares one
  or several candidates against either an exact reference or an aggregated
  reference group. The target picker scans the package repository for branches,
  tags and recent commits; pasted GitHub/GitLab URLs and `owner/repository@ref`
  shorthand are parsed into the same target model.
- Saves targets, comparison policies, selection order and documentation blocks
  as `perfchecker-ui-config/1`, normally `perf/perfchecker-ui.json`.

The package workspace must contain a `perf/Project.toml` with PerfChecker and a
`perf/suite.jl` whose zero-argument `build_suite()` returns a `SoftwareSuite`.
PerfChecker and all UI packages remain in the controller: measured Malt workers
load only the selected package, workload and measurement backend.

## Local development and installation

```powershell
cd C:\path\to\PerfChecker.jl\editors\vscode
npm ci
npm test
npm run package:pre-release -- --out perfchecker-vscode-0.9.0.vsix
code --install-extension .\perfchecker-vscode-0.9.0.vsix --force
```

Reload VS Code, open a Julia package workspace, then open the PerfChecker icon
in the activity bar. `PerfChecker: Open visual suite editor` is also available
from the command palette.

## Marketplace publication

The Marketplace pre-release channel requires a numeric `major.minor.patch`
version, so this candidate uses extension version `0.9.0`; `--pre-release`
marks the channel. The stable extension can therefore start at `1.0.0`.

1. Create or join the Visual Studio Marketplace publisher for Mirage Interactive
   whose immutable ID is `mirage-interactive-fr` (it must match `package.json`).
2. Run `npm ci`, `npm test`, and `npm run package:pre-release`. Install and
   inspect that exact VSIX once before publishing it.
3. For an initial manual publication, create a short-lived Azure DevOps token
   for all accessible organizations with only `Marketplace: Manage`, run
   `npx vsce login mirage-interactive-fr`, then publish the inspected file with
   `npx vsce publish --packagePath .\perfchecker-vscode-0.9.0.vsix --pre-release`.
4. For durable GitHub Actions publication, configure Marketplace trusted
   publishing for this repository and workflow, grant the job `id-token: write`,
   and use `npx vsce publish --oidc --pre-release --no-dependencies`. This avoids
   storing a publication token.

Global Azure DevOps publication tokens are being retired on 1 December 2026;
OIDC is therefore the preferred automated path.

Do not commit a publication token. A failed release keeps its version reserved,
so increment `package.json` before retrying a version that reached Marketplace.
