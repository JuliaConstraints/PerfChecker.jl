const DEFAULT_TEMPLATE_KINDS = (:benchmark, :chairmark, :alloc, :pluto)
const TEMPLATE_KINDS = (:benchmark, :chairmark, :alloc, :pluto)

function _template_filename(kind::Symbol)
    kind === :benchmark && return "benchmark.jl"
    kind === :chairmark && return "chairmark.jl"
    kind === :alloc && return "alloc.jl"
    kind === :pluto && return "dashboard.jl"
    throw(ArgumentError("unknown template kind $kind; expected one of $(TEMPLATE_KINDS)"))
end

function _template_body(kind::Symbol)
    kind === :benchmark && return """
using PerfChecker
using BenchmarkTools

config = PerfConfig(:benchmark;
    path = dirname(@__DIR__),
    tags = [:local],
    samples = 10,
    evals = 1,
)

result = @check config begin
    nothing
end begin
    sum(1:1_000)
end

summary_table(result)
"""

    kind === :chairmark && return """
using PerfChecker
using Chairmarks

config = PerfConfig(:chairmark;
    path = dirname(@__DIR__),
    tags = [:local],
)

result = @check config begin
    nothing
end begin
    sum(1:1_000)
end

summary_table(result)
"""

    kind === :alloc && return """
using PerfChecker

config = PerfConfig(:alloc;
    path = dirname(@__DIR__),
    tags = [:local],
    track = "user",
)

result = @check config begin
    nothing
end begin
    sum(1:1_000)
end

summary_table(result)
"""

    kind === :pluto && return """
### A Pluto.jl notebook ###
# v1.0.0

# This dashboard intentionally uses the surrounding Julia project instead of
# embedding a notebook-specific package environment.

# ╔═╡ 2d1f2ad8-b86a-4a14-a4a1-7656b3797f58
begin
    import Pkg
    project_path = dirname(@__DIR__)
    Pkg.activate(project_path)
    Pkg.instantiate()

    using PerfChecker
end

# ╔═╡ 31f575d1-d1f2-4ac3-a492-4e91f22f3385
run_check = false

# ╔═╡ 102521ea-6249-46c4-810d-2f4cb2cbd7f4
config = PerfConfig(:benchmark;
    path = project_path,
    tags = [:pluto],
    samples = 10,
    evals = 1,
)

# ╔═╡ 19898c08-010b-419a-b6aa-00e1e6c1cf51
result = if run_check
    @check config begin
        nothing
    end begin
        sum(1:1_000)
    end
else
    nothing
end

# ╔═╡ fddfef1d-8d73-4e28-a975-405dcf70a293
summary = result === nothing ? nothing : summary_table(result)

# ╔═╡ Cell order:
# ╠═2d1f2ad8-b86a-4a14-a4a1-7656b3797f58
# ╠═31f575d1-d1f2-4ac3-a492-4e91f22f3385
# ╠═102521ea-6249-46c4-810d-2f4cb2cbd7f4
# ╠═19898c08-010b-419a-b6aa-00e1e6c1cf51
# ╠═fddfef1d-8d73-4e28-a975-405dcf70a293
"""

    throw(ArgumentError("unknown template kind $kind; expected one of $(TEMPLATE_KINDS)"))
end

"""
    write_template(kind::Symbol; path=nothing, force=false) -> String

Write a Julia performance-checking template and return its path.

Supported template kinds are `:benchmark`, `:chairmark`, `:alloc`, and
`:pluto`. The generated files use `PerfConfig`; no external configuration file
format is introduced.
"""
function write_template(kind::Symbol; path = nothing, force::Bool = false)
    kind in TEMPLATE_KINDS ||
        throw(ArgumentError("unknown template kind $kind; expected one of $(TEMPLATE_KINDS)"))
    target = path === nothing ? joinpath("perf", _template_filename(kind)) : String(path)
    if isfile(target) && !force
        throw(ArgumentError("$target already exists; pass force=true to overwrite it"))
    end
    dir = dirname(target)
    isempty(dir) || mkpath(dir)
    open(target, "w") do io
        write(io, _template_body(kind))
    end
    return target
end

"""
    perf_setup(; dir="perf", kinds=(:benchmark, :chairmark, :alloc, :pluto), force=false)

Create a small Julia-native performance workspace.

This writes benchmark, chairmark, allocation, and Pluto dashboard starter files
by default. It intentionally does not create a `Perf.toml`; options stay in
Julia code through `PerfConfig`. The Pluto dashboard activates the surrounding
Julia project so it can be used as a controlled project-local view over stored
or newly run checks.
"""
function perf_setup(; dir = "perf", kinds = DEFAULT_TEMPLATE_KINDS, force::Bool = false)
    mkpath(dir)
    return [write_template(kind; path = joinpath(dir, _template_filename(kind)), force)
            for kind in kinds]
end

"""
    write_suite_notebook(path; result_path="results/suite-result.json",
                         suite_path=nothing, factory=:build_suite,
                         profile=:quick, force=false)

Create a Pluto notebook over the common suite grammar. With `suite_path`, the
notebook can start the same asynchronous `SuiteJob` used by Oxygen; otherwise
it is a read-only report viewer. Timed work always remains inside isolated Malt
workers.
"""
function write_suite_notebook(path::AbstractString;
        result_path::AbstractString = "results/suite-result.json", suite_path = nothing,
        factory::Symbol = :build_suite, profile::Symbol = :quick, force::Bool = false)
    target = String(path)
    isfile(target) && !force &&
        throw(ArgumentError("$target already exists; pass force=true to overwrite it"))
    mkpath(dirname(target))
    result_literal = repr(String(result_path))
    suite_literal = suite_path === nothing ? "nothing" : repr(String(suite_path))
    profile_literal = repr(profile)
    factory_literal = repr(factory)
    body = """
### A Pluto.jl notebook ###
# v1.0.0

# ╔═╡ 41dbb952-51ff-4edb-bb60-5b75a58da62d
begin
    import Pkg
    Pkg.activate(@__DIR__)
    using JSON
    using PerfChecker
end

# ╔═╡ 4531fb5a-74fd-45b7-867a-94447193d561
result_path = normpath(joinpath(@__DIR__, $result_literal))

# ╔═╡ 648fe579-9d73-42cd-a738-24e81381ce3c
suite_path = $suite_literal

# ╔═╡ 97a4d99b-afc1-4c64-8d58-0dbe9e02fe25
run_suite_now = false

# ╔═╡ 32a629a1-e320-4025-b47a-f131149ddc1e
job = if run_suite_now && suite_path !== nothing
    definition = normpath(joinpath(@__DIR__, suite_path))
    launch_suite(load_software_suite(definition; factory = $factory_literal);
        profile = $profile_literal)
else
    nothing
end

# ╔═╡ e65d45fb-3452-42b7-919e-f999f0dc3ccc
job_progress = job === nothing ? nothing : suite_job_progress(job)

# ╔═╡ e91b2020-4eb7-40a8-a3f5-165aa7a195ad
progress_bar = if job_progress === nothing
    "No job running"
else
    width = 30
    filled = round(Int, width * job_progress["fraction"])
    "[" * repeat("█", filled) * repeat("░", width - filled) * "] " *
    "\$(job_progress[\"completed\"])/\$(job_progress[\"total\"])"
end

# ╔═╡ 028d8c89-440d-4716-bd43-37590b0be870
job_result = job === nothing || suite_job_status(job) ∉ (:complete, :failed) ?
             nothing : wait_suite(job; strict = false)

# ╔═╡ fa2e2a77-d688-43fd-bc2a-d85732c0318e
report = job_result !== nothing ? suite_dict(job_result) :
         isfile(result_path) ? JSON.parsefile(result_path; use_mmap = false) : Dict(
    "status" => "missing",
    "message" => suite_path === nothing ?
        "Run the suite before opening the dashboard." :
        "Set run_suite_now=true to start isolated workers.")

# ╔═╡ cfdc9952-89e9-40fc-a656-bf0519ef0484
runs = get(report, "runs", Any[])

# ╔═╡ 7700c6fd-0cd1-4829-b0e4-f867ab48b94e
passed = count(run -> get(run, "status", "") == "pass", runs)

# ╔═╡ 9da214fd-b605-4867-969b-57e608ba4285
unavailable = count(run -> get(run, "status", "") == "unavailable", runs)

# ╔═╡ 12574c2d-f627-4a88-8980-1811bf738a5b
failed = count(run -> get(run, "status", "") == "error", runs)

# ╔═╡ 94b9447f-b5cb-46ef-a211-17bb5a091c11
runs

# ╔═╡ Cell order:
# ╠═41dbb952-51ff-4edb-bb60-5b75a58da62d
# ╠═4531fb5a-74fd-45b7-867a-94447193d561
# ╠═648fe579-9d73-42cd-a738-24e81381ce3c
# ╠═97a4d99b-afc1-4c64-8d58-0dbe9e02fe25
# ╠═32a629a1-e320-4025-b47a-f131149ddc1e
# ╠═e65d45fb-3452-42b7-919e-f999f0dc3ccc
# ╠═e91b2020-4eb7-40a8-a3f5-165aa7a195ad
# ╠═028d8c89-440d-4716-bd43-37590b0be870
# ╠═fa2e2a77-d688-43fd-bc2a-d85732c0318e
# ╠═cfdc9952-89e9-40fc-a656-bf0519ef0484
# ╠═7700c6fd-0cd1-4829-b0e4-f867ab48b94e
# ╠═9da214fd-b605-4867-969b-57e608ba4285
# ╠═12574c2d-f627-4a88-8980-1811bf738a5b
# ╠═94b9447f-b5cb-46ef-a211-17bb5a091c11
"""
    open(target, "w") do io
        write(io, body)
    end
    return target
end
