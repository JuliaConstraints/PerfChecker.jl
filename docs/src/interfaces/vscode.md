# VS Code

The VS Code extension is PerfChecker's central graphical workspace. It reads the
same plan and UI configuration as the CLI, Oxygen, Pluto, and documentation
adapters; it does not invent a second suite format.

## Workspace model

The Explorer and Testing views present:

```text
package → business feature → check type → target
```

From any relevant node you can run the selection, open its visual output, view
worker logs, or jump to the exact workload script. Check types remain selectable
options of a business feature, so `import_bibtex` is not duplicated into fake
features such as `import_bibtex_profile`.

## Visual suite editor

Open **PerfChecker: Open visual suite editor** from the command palette. The
editor supports:

- global and per-feature check-type selection;
- version ranges, search, sorting, colour labels, and drag-and-drop ordering;
- named comparison targets for a branch, tag, commit, working tree, or release;
- exact or grouped baselines with median, mean, minimum, or maximum aggregation;
- direct execution and progress updates;
- persistent selection and documentation blocks in
  `perf/perfchecker-ui.json` (`perfchecker-ui-config/1`).

The comparison-target picker scans the selected package repository for local and
remote branches, tags, and recent commits. It also parses a plain ref, a full
SHA, GitHub/GitLab tree/tag/commit URLs, and `owner/repository@ref` shorthand.
Set a compatibility version when an older or experimental target needs a
specific workload variant.

## Results

The output action discovers the latest result matching the selected suite,
package, feature, check, or target. Available views include BenchmarkTools and
Chairmarks distributions, version trajectories, deltas, allocation pie/file/
line/heatmap views, and allocation/CPU/wall-time flame graphs.

Interactive HTML views provide hover and keyboard focus for small points,
slices, and flame cells. Flame tooltips expose the full call path and source
location; colour semantics identify allocation, garbage collection, runtime
dispatch, and unstable inference evidence when the collector supplied it.

## Install a local VSIX

```powershell
code --install-extension C:\path\to\perfchecker-vscode-0.9.0.vsix --force
```

Reload VS Code, open the package root, and select the PerfChecker icon in the
activity bar. The package currently keeps the extension source under
`editors/vscode`. A later move to a dedicated Mirage Interactive repository must
preserve the extension identity `mirage-interactive-fr.perfchecker-vscode`, its
commands, settings, and shared configuration schema.

## Develop the extension

```powershell
cd editors\vscode
npm ci
npm test
npm run package:pre-release -- --out perfchecker-vscode-0.9.0.vsix
```

Install and inspect the exact generated VSIX before any Marketplace release.
Publishing is deliberately separate from packaging and requires the Mirage
Interactive Marketplace publisher credentials.
