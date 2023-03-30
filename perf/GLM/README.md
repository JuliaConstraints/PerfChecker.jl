# GLM.jl

`GLM.jl` is a Julia library for Generalized Linear Model.

### Getting Started with `PerfChecker.jl`
Before getting started with any checks, we must ensure that we are evaluating the correct version. Because `PerfChecker.jl` lacks a few features at the time of writing this, this has to be done manually.

To switch the version of `GLM.jl`:

- Change directory to *../PerfChecker.jl/perf/GLM*
- Access the REPL using `julia -t 10 --project=.`
- Press the `]` key to access the `pkg` REPL
- Run `add GLM@x.y.z`, where x.y.z is the respective major, minor and patch version
- Close the REPL either by coming out of the pkg REPL mode, and executing the `exit()` command, or by using **Ctrl + D**

This should be repeated after every allocation and benchmark checks have run.

#### Allocation checks

To run allocation checks for `GLM.jl`:

- Ensure that you're on the same directory as *../PerfChecker.jl/perf/GLM*
- Run `julia -t 10 --project=. allocs.jl`
- Wait for a few minutes, till the prompt is visible again
- Check if `mallocs-x.y.z.csv` has been generated inside the `mallocs` directory

#### Benchmark checks

To run benchmark checks for `GLM.jl`:

- Ensure that you're on the same directory as *../PerfChecker.jl/perf/GLM*
- Run `julia -t 10 --project=. bench.jl`
- Wait for a few minutes, till the prompt is visible again
- Check if `benchmark-x.y.z.csv` has been generated inside the `benchmarks` directory

#### Visualization

As mentioned before, due to some of the missing features in `PerfChecker.jl`, running checks might be finicky, and the CSV files may produce messed up visualization. To fix the same:
- Make sure that filenames inside `mallocs-x.y.z.csv` do not point to a hash directory, for example, if you see *$HOME/.julia/packages/GLM/<some-hash-value>/src/linpred.jl*, make sure to rewrite it to *$HOME/.julia/packages/GLM/src/linpred.jl*.
- Clone `GLM.jl` on your local machine
- Create `perf` directory inside the `GLM.jl` project
- Copy contents of *../PerfChecker.jl/perf/GLM* to the `perf` directory

To start generating visualizations, we can run the following commands in the REPL:
```julia
using PerfChecker
# switch to pkg REPL using ]
develop <point-to-GLM.jl-directory>
# exit out of pkg REPL by pressing the backspace key
using GLM

alloc_plot([GLM])
bench_plot([GLM])
```
