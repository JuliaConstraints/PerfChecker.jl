# Installation

PerfChecker `1.0.0-rc2` is currently distributed from its Mirage Interactive
Git repository. Keep the controller in a dedicated `perf` environment rather
than adding every UI package to the package being measured.

## Controller environment

From the target package:

```julia
import Pkg
Pkg.activate("perf")
Pkg.add(url = "https://github.com/Mirage-Interactive-Fr/PerfChecker.jl")
```

Add only the optional interfaces and collectors that the controller or workloads
need:

```julia
Pkg.add([
    "BenchmarkTools",
    "Chairmarks",
    "CairoMakie",
    "WGLMakie",
    "Oxygen",
    "Pluto",
    "UnicodePlots",
])
```

These packages are controller dependencies. A feature run still receives a
fresh Malt worker with a separately prepared measurement environment.

## Local PerfChecker development

To test changes to PerfChecker itself:

```julia
import Pkg
Pkg.activate("perf")
Pkg.develop(path = raw"C:\path\to\PerfChecker")
```

Use `Pkg.status()` in the `perf` environment to verify which checkout is active.

## Generate the suite skeleton

Run the CLI entry point with the package root:

```sh
julia --project=/path/to/PerfChecker.jl \
  /path/to/PerfChecker.jl/bin/perfchecker.jl init --root=/path/to/MyPackage
```

It creates:

```text
perf/
├─ suite.jl
├─ features/
│  └─ smoke.jl
└─ runner/
   └─ Project.toml
```

Existing files are protected. `--force=true` is required to replace a generated
suite.

## Optional interface activation

PerfChecker uses Julia package extensions. Loading an optional package activates
its integration:

```julia
using PerfChecker, BenchmarkTools   # BenchmarkTools collector
using PerfChecker, Chairmarks       # Chairmarks collector
using PerfChecker, Makie            # performance_figure
using PerfChecker, WGLMakie         # interactive HTML/WebGL output
using PerfChecker, Oxygen           # Performance Studio and API routes
using PerfChecker, Pluto            # notebook preparation and launch
using PerfChecker, UnicodePlots      # terminal_plot
```

## VS Code extension

Until the extension moves to its own Mirage Interactive repository, build it
from `editors/vscode`:

```powershell
cd editors\vscode
npm ci
npm test
npm run package:pre-release -- --out perfchecker-vscode-0.9.0.vsix
code --install-extension .\perfchecker-vscode-0.9.0.vsix --force
```

Reload VS Code and open the package workspace. The PerfChecker activity icon,
native Test Explorer integration and `PerfChecker: Open visual suite editor`
command use the same `perf/suite.jl` as CI.

## Verify the installation

```sh
julia --project=perf /path/to/PerfChecker.jl/bin/perfchecker.jl version
julia --project=perf /path/to/PerfChecker.jl/bin/perfchecker.jl capabilities
julia --project=perf /path/to/PerfChecker.jl/bin/perfchecker.jl plan \
  --suite=perf/suite.jl --profile=quick
```

`capabilities` reports optional collectors and platform-dependent features. A
capability being present does not mean a particular package version resolves;
run `preflight` before a large historical campaign.
