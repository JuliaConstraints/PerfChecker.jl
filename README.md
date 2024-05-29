# PerfChecker

<!--[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://JuliaConstraints.github.io/PerfChecker.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaConstraints.github.io/PerfChecker.jl/dev)-->
[![Build Status](https://github.com/JuliaConstraints/PerfChecker.jl/workflows/CI/badge.svg)](https://github.com/JuliaConstraints/PerfChecker.jl/actions)
[![codecov](https://codecov.io/gh/JuliaConstraints/PerfChecker.jl/branch/main/graph/badge.svg?token=YVJhN4dpBp)](https://codecov.io/gh/JuliaConstraints/PerfChecker.jl)
[![SciML Code Style](https://img.shields.io/static/v1?label=code%20style&message=SciML&color=9558b2&labelColor=389826)](https://github.com/SciML/SciMLStyle)
[![Chat: Mattermost](https://img.shields.io/badge/chat-mattermost-blueviolet.svg)](https://nohost.iijlab.net/chat/signup_user_complete/?id=nnuc1g14gtrqtnas6thu193xmr)
[![Website: JuliaConstraints](https://img.shields.io/badge/website-JuliaConstraints-informational.svg)](https://juliaconstraints.github.io/)

`PerfChecker` is a set of performance checking tools for Julia packages. The ultimate aim is to create an environment where the tool can run similarly to a test environment. By doing so, it would be possible to test the performance of a package `P` in separate Julia instances. This would allow for each version of `P`:

- The use of the latest compatible versions of Julia and other dependencies of P
- Independence of compatibility requirements of `PerfChecker.jl` from the environment used during performance checks.

## Google Summer of Code (2023)

`JuliaConstraints`, including `PerfChecker.jl`, is participating in Google Summer of Code (GSoC) through the Julia language umbrella and is looking for contributors. Complete lists of projects:

- [JuliaConstraints](https://julialang.org/jsoc/gsoc/juliaconstraints/)
- Other [Julia language projects](https://julialang.org/jsoc/projects/)

### Project Ideas

This package consists of a set of tools designed to check the performance of packages over time and versions. The targeted audience is the whole community of packages' developers in Julia (not only JuliaConstraints).

This README provides a short demo on how PerfChecker can be used.

**Basic features to implement (length ≈ 175 hours)**

- PerfCheck environment similar to Test.jl and Pkg.jl
- Sugar syntax `@bench`, `@alloc`, `@profile` similar to Test.jl and Pkg.jl
- Interactive REPL interface
- Interactive GUI interface (using for instance Makie)
- Automatic Profiling ? (not sure how, there already is a bunch of super cool packages)
- Automatic plotting of previous features

**Advanced features (length +≈ 175 hours)**

- *Smart* semi-automatic analysis of performances
- Performances bottlenecks
- Regressions
- Allocations vs speed trade-off
- Descriptive plot captions
- Handle Julia and other packages versions
- Integrates with juliaup
- Automatically generate versions parametric space for both packages and Julia

Note that some features are interchangeable depending on the interest of the candidate. For candidates with a special interest in the JuliaConstraints ecosystem, checking the performances of some packages is an option.

**Length**

175 hours – 350 hours (depending on features)

**Recommended Skills (||)**

- Familiarity with package development
- REPL and/or GUI interfaces
- Coverage, Benchmarks, and Profiling tools

**Difficulty**

Easy to Medium, depending on the features implemented

### Getting Started

Although it is part of JuliaConstraints, `PerfChecker` is a standalone project. As such a good start is to understand fully its features and workflow. For instance, one way is to write a small use case in the vein of the small tutorial below. Possible packages could be

- A JuliaConstraints package or dependency
- A package written by the GSoC candidate
- Another package from the Julia community

Please bear in mind that, ideally, writing performance checks for such a package should be simple.

Also, allocation checks generate memory files in the package local folder. Ideally the package should be `dev`ed in a local environment.

To contribute, please fork the repo, create a new branch, make your changes, and submit a pull request. If you are unsure about anything or need any help, please don't hesitate to ask through issues, [JuliaConstraints chat](https://nohost.iijlab.net/chat/signup_user_complete/?id=nnuc1g14gtrqtnas6thu193xmr), or the `#juliaconstraints` channel on Humans-of-Julia's [Discord](https://discord.gg/7KC28q98nP).


We encourage students and other possible GSoC contributors to participate in `PerfChecker`'s development as it would bring a tools for the Julia community as a whole. It would bring them experience and deep understanding of Julia packages development and, more generally, open source development along with performance testing.
We're looking forward for proposals submissions.

## Small tutorial

This tutorial is based on a beta version and is prone to change frequently. Please use it as a workflow example.

Let's write two small scripts to check allocations (`allocs.jl`) and benchmarks (`bench.jl`) for [CompositionalNetworks.jl](https://github.com/JuliaConstraints/CompositionalNetworks.jl) using `PerfChecker.jl`.
In the current state, we write and execute the scripts (and stores a local environment) in the `/perf` folder of `CompositionalNetworks.jl`. You can use `julia --project` to activate that environment when running the script. For instance, I run the check for `CompositionalNetworks.jl` with the following command,

```shell
julia -t 10 --project
```

To generate results from different versions of the targeted package, be sure to change the version in the local environment.

We will generate plots from the allocations check and the benchmark check from the `REPL`.

Please add to the environment the following packages (adapt to your use case):

- `PerfChecker.jl`
- `Test.jl`: for allocations
- `BenchmarkTools`: for benchmarks
- `CompositionalNetworks.jl`: target
- `ConstraintDomains.jl`: dependency

**Remark on code compilation and `PerfChecker.jl`**

Depending on the nature of your code, it is important to be sure to trigger all compilation previous to the allocation check. This role is annotated in both scripts.

Note that in the case of `CompositionalNetworks.jl`, it stochastically generates a great deal of methods to compile.

For deterministic code, `pre-alloc()` can be minimal, and `@benchmark` will handle triggering the necessary compilation before the checks.

### Allocation checks

The current state of `PerfChecker.jl` requires the use of `Test.jl`, but this requirement will disappear soon.

```julia
# Required to run the script
using PerfChecker
using Test

# Target(s)
using CompositionalNetworks # latest release: 0.3.1

# Direct dependencies of this script
using ConstraintDomains

@testset "PerfChecker.jl" begin
    # Title of the alloc check (for logging purpose)
    title = "Explore, Learn, and Compose"

    # Dependencies needed to execute pre_alloc and alloc
    dependencies = [CompositionalNetworks, ConstraintDomains]

    # Target of the alloc check
    targets = [CompositionalNetworks]

    # Code specific to the package being checked
    domains = fill(domain([1, 2, 3]), 3)

    # Code to trigger precompilation before the alloc check
    pre_alloc() = foreach(_ -> explore_learn_compose(domains, allunique), 1:10)

    # Code being allocations check
    alloc() = explore_learn_compose(domains, allunique)

    # Actual call to PerfChecker
    alloc_check(title, dependencies, targets, pre_alloc, alloc; path=@__DIR__, threads=10)
end
```

This script will output the table below (and store it as `mallocs/mallocs-0.3.1.csv`). Note that the allocations are provided in decreasing order. The `.mem` files generated by tracking allocations are automatically deleted (unless your code run into an error).

![Malloc-check](/images/PerfChecker-alloc_check.png)

### Benchmark checks

As `BenchmarkTools.jl` provides already a great set of functionalities, we use it directly. In the future, it is likely that `PerfChecker.jl` will provide synthetic sugar to wrap `@benchmark` with similar behavior to make using `BenchmarkTools.jl` invisible.

```julia
# Required to run the script
using PerfChecker
using BenchmarkTools

# Target(s)
using CompositionalNetworks # latest release: 0.3.1

# Direct dependencies of this script
using ConstraintDomains

# Target of the benchmark
target = CompositionalNetworks

# Code specific to the package being checked
domains = fill(domain([1, 2, 3, 4]), 4)

# Code to trigger precompilation before the bench (optional)
foreach(_ -> explore_learn_compose(domains, allunique), 1:10)

# Code being benchmarked (be sure to enforce specific amounts of evals and samples for each version benchmarked)
bench = @benchmark explore_learn_compose(domains, allunique) evals=1 samples=10 seconds=3600

# Store the bench results
store_benchmark(bench, target; path=@__DIR__)
```

This script will output the results of `@benchmark` as a table (and store it as `benchmarks/benchmark-0.3.1.csv`). Note that it is recommended (but not necessary) to ensure that for each version of the package benchmarked, the output is of similar length.

### Visualization

We will generate some plots, in `perf/mallocs` and `perf/benchmarks`. In the REPL (or a notebook), please run:

```julia
using PerfChecker
using CompositionalNetworks

alloc_plot([CompositionalNetworks])
bench_plot([COmpositionalNetworks])

```

**Allocs (Pie Chart)**

For each version checked with the previous scripts, we get a pie plot showing the distribution of the allocations (per line). Obviously, improving the allocations at the 5th line of `metrics.jl` would improve allocations (and likely overall performances) in `CompositionalNetworks.jl`. Let's try to spot issues through the evolution of allocations over time.

![Malloc-pie](images/mallocs-0.3.1.png)

**Allocs over time**

Luckily, an overview of the evolution of the allocations within each file is also plotted. The allocations in `CompositionalNetworks.jl` improve a lot from `v0.3.x`. Interestingly, the changes also introduced an increase in allocations in the `metrics.jl` file. Maybe there really is an issue (answer in future releases of `CompositionalNetworks.jl`).

![Malloc-evolution](/images/mallocs-evolutions.png)

First, we should check how the performances are impacted by the changes in memory allocations.

**Benchmarks (allocs and memory)**

To confirm the improvement of allocations above, let's have a look at the evolution of allocations and memory use over time.

![Benchmark-allocs](/images/benchmark-allocs.png)
![Benchmark-memory](/images/benchmark-memory.png)

Both distribution of allocations and memory is very stable. This meet the improvement of the design of `CompositionalNetworks.jl` that ensure allocations of one data structure at the start of each `explore_learn_compose` call evaluated by both scripts.

**Benchmarks (times and garbage collection times)**

Garbage collection brings a lot of comfort for programmers, and it participates in the attractiveness of the Julia language. However, careless allocations can be a performance pitfall. Such was the case of `CompositionalNetworks.jl` prior to `v0.3`.

![Benchmark-gctimes](/images/benchmark-gctimes.png)

The changes introduce from that version clearly improved our GC issues. Does it reflect on the global time performance? (spoiler: yes, it does, cf next plot)

![Benchmark-times](/images/benchmark-times.png)

We can remark important deviations (beware the logarithmic scale ...) from the mean. As mentioned above, `CompositionalNetworks.jl` uses a stochastic process, so it is not surprising. At least, memory (allocations) are stable.

**Benchmarks (evolutions overview)**

Well, we probably could get the gist of the previous 4 plots from the wrap-up plot below.

![Benchmark-evolutions](/images/benchmark-evolutions.png)

Note that the analysis on memory stability despite a stochastic process that reflect on the `times` and `gctimes` is not possible here. But it looks much better if you only can show off one performance plot.

## Contributing

We appreciate contributions from users including reporting bugs, fixing issues, improving performance and adding new features.

To contribute, please fork the repo, create a new branch, make your changes, and submit a pull request. If you are unsure about anything or need any help, please don't hesitate to ask.

## Acknowledgments

This package is part of the [JuliaConstraints](https://juliaconstraints.github.io/) project. We thank the entire community for their contributions.
