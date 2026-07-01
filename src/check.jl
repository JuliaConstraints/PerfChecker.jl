"""
    initpkgs(::Val{backend}) -> Expr

Backend hook returning code that loads backend-specific packages inside each
worker. Extensions normally define methods such as
`PerfChecker.initpkgs(::Val{:benchmark})`.
"""
initpkgs(x) = quote
    nothing
end

"""
    prep(config::Dict, block::Expr, ::Val{backend}) -> Expr

Backend hook returning code run before the measured block. Its result is stored
as `config[:prep_result]` before `post` is called.
"""
prep(d, b, v) = quote
    nothing
end

"""
    check(config::Dict, block::Expr, ::Val{backend}) -> Expr

Backend hook returning code that performs the measurement. Its result is stored
as `config[:check_result]` before `post` is called.
"""
check(d, b, v) = quote
    nothing
end

"""
    post(config::Dict, ::Val{backend})

Backend hook that selects or transforms the worker result before it is converted
to a `TypedTables.Table` by `to_table`.
"""
post(d, v) = nothing

"""
    default_options(::Val{backend}) -> Dict

Backend hook returning default configuration values. These defaults are merged
with the user dictionary before `normalize_config` validates shared options.
"""
default_options(v) = Dict()

"""
    cleanup(config::Dict, ::Val{backend})

Backend hook run after workers have stopped. Backends that create process-exit
artifacts can use it to remove files that are flushed only when a worker exits.
"""
cleanup(d, v) = nothing

initpkgs(x::Symbol) = initpkgs(Val(x))
prep(d::Dict, b::Expr, v::Symbol) = prep(d, b, Val(v))
check(d::Dict, b::Expr, v::Symbol) = check(d, b, Val(v))
post(d::Dict, v::Symbol) = post(d, Val(v))
cleanup(d::Dict, v::Symbol) = cleanup(d, Val(v))

function default_options(d::Dict, v::Symbol)
    di = default_options(Val(v))
    return merge(di, d)
end

function run_targets(config::CheckConfig)
    pkgs = if config.packages === nothing
        PackageSpec[PackageSpec()]
    else
        [PackageSpec(name = config.packages.name, version = i)
         for i in get_versions(config.packages)[2]]
    end

    targets = [RunTarget(pkg, something(pkg.name, "current"), false) for pkg in pkgs]
    if config.devops !== nothing
        pkg = config.devops isa Tuple ? config.devops[1] : config.devops
        name = pkg isa PackageSpec ? pkg.name : String(pkg)
        push!(targets, RunTarget(PackageSpec(name = name, version = "dev"), name, true))
    end
    return targets
end

function safe_stop(worker)
    try
        stop(worker)
    catch err
        @debug "failed to stop PerfChecker worker" exception = (err, catch_backtrace())
    end
end

function safe_cleanup(options, backend::Symbol)
    try
        cleanup(options, backend)
    catch err
        @debug "failed to run PerfChecker cleanup hook" exception = (err, catch_backtrace())
    end
end

function check_function(x::Symbol, d::Dict, block1, block2)
    config = normalize_config(x, d)
    di = legacy_options(config)
    g = prep(di, block1, x)
    h = check(di, block2, x)
    initpkg = initpkgs(x)
    hwinfo = HwInfo(
        cpu_info(),
        CPU_NAME,
        WORD_SIZE,
        simdbytes(),
        (cpucores(), cputhreads(), cputhreads_per_core())
    )

    results = CheckerResult(
        Table[],
        hwinfo,
        config.tags,
        PackageSpec[]
    )

    targets = run_targets(config)
    len = length(targets)

    t = [tempname() for _ in 1:len]
    cp.(Ref(config.path), t)

    procs = @sync begin
        fetch.([@async(Worker(;
                    exeflags = ["--track-allocation=$(config.track)",
                        "-t $(config.threads)", "--project=$(t[i])"])) for i in 1:len])
    end

    cleanup_options = Dict{Symbol, Any}[]
    try
        for i in 1:len
            target = targets[i]
            run_options = copy(di)
            run_options[:current_spec] = target.spec
            run_options[:current_version] = target.spec.version

            cached_path = if !target.is_dev && !isnothing(target.spec.name)
                cached_output_path(
                    config, target.spec.name, target.spec.version, block1, block2, hwinfo)
            else
                nothing
            end

            if cached_path === nothing
                remote_eval_wait(Main, procs[i], quote
                    import Pkg
                    let
                        i = $i
                        @info "Worker No.: $i"
                    end
                    Pkg.instantiate(; io = stderr)
                end)

                remote_eval_wait(Main, procs[i], initpkg)

                remote_eval_wait(Main, procs[i],
                    quote
                        d = $run_options
                        is_dev = $(target.is_dev)
                        target_spec = $(target.spec)
                        target_label = $(target.label)
                        if is_dev
                            pkg = d[:devops]
                            try
                                Pkg.rm(target_label)
                            catch
                            end
                            pkg isa Tuple ? Pkg.develop(pkg[1]; pkg[2]...) :
                            Pkg.develop(pkg)
                        elseif !isnothing(target_spec.name)
                            try
                                Pkg.rm(target_spec.name)
                            catch
                            end
                            Pkg.add(target_spec)
                        end
                        haskey(d, :extra_pkgs) && Pkg.add(d[:extra_pkgs])
                    end)

                run_options[:prep_result] = remote_eval_fetch(Main, procs[i], g)
                run_options[:check_result] = remote_eval_fetch(Main, procs[i], h)
                push!(cleanup_options, run_options)
                res = post(run_options, x) |> to_table
            else
                res = csv_to_table(cached_path)
            end

            push!(results.tables, res)
            push!(results.pkgs, target.spec)
        end

        for (k, t) in enumerate(results.tables)
            ps = results.pkgs[k]
            pkg = ps.name
            v = ps.version
            (isnothing(pkg) || v == "dev") && continue

            run = run_metadata(config, pkg, v, block1, block2, hwinfo)
            out = output_path(config.path, run.result_uuid)
            metadata = metadata_path(config.path)
            if metadata_has_result(metadata, run.result_uuid)
                continue
            end
            table_to_csv(t, out)
            write_run_metadata(metadata, run)
        end
    finally
        foreach(safe_stop, procs)
        safe_cleanup(di, x)
        foreach(options -> safe_cleanup(options, x), cleanup_options)
    end

    return results
end

function check_function(x::Symbol, config::CheckConfig, block1, block2)
    return check_function(x, legacy_options(config), block1, block2)
end

function check_function(config::PerfConfig, block1, block2)
    return check_function(config.backend, config, block1, block2)
end

function check_function(x::Symbol, config::PerfConfig, block1, block2)
    x == config.backend ||
        throw(ArgumentError(
            "backend mismatch: macro requested $x but PerfConfig uses $(config.backend)"))
    return check_function(x, to_dict(config), block1, block2)
end

function check_function(x::Symbol, d::NamedTuple, block1, block2)
    return check_function(x, Dict{Symbol, Any}(pairs(d)), block1, block2)
end

"""
    @check backend config begin
        # preparation code
    end begin
        # measured code
    end

Run a performance check using `backend` and return a `CheckerResult`.

The public `config` argument is usually a `Dict`. PerfChecker merges it with
backend defaults, validates it with `normalize_config`, copies the environment
at `config[:path]`, launches isolated Julia workers, installs the requested
package versions, runs the two code blocks, and stores result tables plus
metadata.

Example:

```julia
using PerfChecker, BenchmarkTools

config = Dict(:path => @__DIR__, :samples => 10, :evals => 1)

result = @check :benchmark config begin
    using Random
end begin
    sum(rand(Random.MersenneTwister(1), 1_000))
end
```
"""
macro check(x, d, block1, block2)
    block1, block2 = Expr(:quote, block1), Expr(:quote, block2)
    quote
        x = $(esc(x))
        d = $(esc(d))
        check_function(x, d, $block1, $block2)
    end
end

"""
    @check config begin
        # preparation code
    end begin
        # measured code
    end

Run a performance check from a `PerfConfig`.

This is equivalent to `@check config.backend Dict(config) ...`, but keeps the
backend and options bundled in one Julia object for scripts, REPL sessions, and
Pluto notebooks.
"""
macro check(config, block1, block2)
    block1, block2 = Expr(:quote, block1), Expr(:quote, block2)
    quote
        config = $(esc(config))
        check_function(config, $block1, $block2)
    end
end

"""
    perf_table(...)

Reserved extension point for backend-specific tabular summaries.
"""
function perf_table end

"""
    perf_plot(...)

Reserved extension point for backend-specific plots.
"""
function perf_plot end

"""
    table_to_pie(table, ::Val{backend}; kwargs...)

Create a pie chart from a backend table. Currently implemented by the Makie
extension for allocation tables with `Val(:alloc)`.
"""
function table_to_pie end

"""
    checkres_to_scatterlines(result::CheckerResult, ::Val{backend}; kwargs...)

Create an evolution plot from a `CheckerResult`. Plotting dispatch is explicit:
use `Val(:benchmark)`, `Val(:chairmark)`, or `Val(:alloc)`.
"""
function checkres_to_scatterlines end

"""
    checkres_to_pie(result::CheckerResult, ::Val{backend}; kwargs...)

Create pie charts from a `CheckerResult`. For allocation checks this returns
pairs mapping version labels to Makie figures.
"""
function checkres_to_pie end

"""
    saveplot(...)

Reserved extension point for saving backend-specific plots.
"""
function saveplot end

"""
    checkres_to_boxplots(result::CheckerResult, ::Val{backend}; kwarg=:times)

Create boxplots from a `CheckerResult` for the selected metric column.
"""
function checkres_to_boxplots end

"""
    to_table(raw_result) -> TypedTables.Table

Convert a backend-specific raw result into a table stored by PerfChecker.
Backends should extend this method for their raw result types.
"""
function to_table end
