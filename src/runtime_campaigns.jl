const JULIA_RUNTIME_CAMPAIGN_SCHEMA = "perfchecker-julia-runtime-campaign/1"

"A completed suite campaign over an explicit Julia runtime axis."
struct JuliaRuntimeCampaign
    id::String
    suite::String
    profile::Symbol
    baseline_id::Symbol
    started_at::String
    finished_at::String
    runs::Vector{Dict{String, Any}}
    comparisons::Vector{Dict{String, Any}}
end

function _runtime_process(command::Vector{String}, timeout_seconds::Real)
    stdout_buffer = IOBuffer()
    stderr_buffer = IOBuffer()
    process = nothing
    started = time()
    timed_out = false
    try
        process = run(
            pipeline(ignorestatus(Cmd(command)), stdout = stdout_buffer,
                stderr = stderr_buffer);
            wait = false)
        status = timedwait(() -> !process_running(process), timeout_seconds;
            pollint = 0.1)
        if status === :timed_out
            timed_out = true
            _terminate_process_tree(process)
        end
        wait(process)
        return (exit_code = process.exitcode, timed_out,
            elapsed_seconds = time() - started,
            stdout = String(take!(stdout_buffer)),
            stderr = String(take!(stderr_buffer)))
    finally
        close(stdout_buffer)
        close(stderr_buffer)
    end
end

function _runtime_failure_kind(execution)
    execution.timed_out && return "timeout"
    output = lowercase(string(execution.stderr, '\n', execution.stdout))
    if any(marker -> occursin(marker, output),
        ("exception_access_violation", "segmentation fault", "signal (11)",
            "please submit a bug report with steps to reproduce this fault"))
        return "runtime_crash"
    elseif any(marker -> occursin(marker, output),
        ("unsatisfiable requirements", "compatibility requirements", "resolvererror"))
        return "compatibility"
    elseif occursin("error: loaderror", output) || occursin("syntax:", output)
        return "bootstrap_error"
    end
    return "suite_error"
end

function _runtime_failure_summary(execution, status::AbstractString)
    status == "passed" && return ""
    lines = [strip(line)
             for line in split(string(execution.stderr, '\n', execution.stdout), '\n')
             if !isempty(strip(line))]
    preferred = findfirst(
        line -> startswith(line, "ERROR:") ||
                    startswith(line, "Exception:") ||
                    occursin("segmentation fault", lowercase(line)) ||
                    occursin("signal (11)", lowercase(line)),
        lines)
    fallback = findfirst(
        line -> !startswith(line, "[") &&
                    !startswith(line, "┌") &&
                    !startswith(line, "│") &&
                    !startswith(line, "└"),
        lines)
    selected = preferred === nothing ? fallback : preferred
    selected === nothing && return "runtime process exited without a diagnostic"
    return first(lines[selected], 2_048)
end

function _runtime_failure_frames(execution; limit::Integer = 12)
    limit > 0 || throw(ArgumentError("failure frame limit must be positive"))
    frames = Dict{String, Any}[]
    for line in split(string(execution.stderr, '\n', execution.stdout), '\n')
        matched = match(r"^\s*(.+?) at (.+):(\d+):\d+(?:\s+.*)?$", line)
        matched === nothing && continue
        push!(frames,
            Dict{String, Any}("function" => String(matched.captures[1]),
                "source_file" => String(matched.captures[2]),
                "source_line" => Base.parse(Int, matched.captures[3])))
        length(frames) == limit && break
    end
    return frames
end

function runtime_campaign_passed(campaign::JuliaRuntimeCampaign)
    all(run -> run["status"] == "passed", campaign.runs) &&
        all(comparison -> comparison["passed"], campaign.comparisons)
end

function _runtime_bundle(report_directory::String)
    manifests = list_run_bundles(report_directory; recursive = true)
    isempty(manifests) && return nothing
    length(manifests) == 1 || throw(ErrorException(
        "runtime report contains $(length(manifests)) bundles; expected one"))
    return String(only(manifests)["bundle_path"])
end

function _runtime_campaign_run(spec::JuliaRuntimeSpec; suite::String, reports::String,
        profile::Symbol, factory::Symbol, perfchecker_project::String,
        controller_project::String, backend_packages::Vector{String},
        timeout_seconds::Real)
    command = julia_runtime_suite_command(spec; suite, reports, profile, factory,
        perfchecker_project, controller_project, backend_packages)
    probe = try
        probe_julia_runtime(spec; project = perfchecker_project)
    catch error
        return Dict{String, Any}(
            "runtime_id" => string(spec.id), "role" => string(spec.role),
            "spec" => julia_runtime_spec_dict(spec), "status" => "probe_error",
            "command" => command, "reports" => reports,
            "controller_project" => controller_project, "bundle_path" => nothing,
            "exit_code" => nothing, "elapsed_seconds" => 0.0,
            "stdout" => "", "stderr" => "",
            "failure_kind" => "probe_error",
            "failure_summary" => first(sprint(showerror, error), 2_048),
            "failure_frames" => Dict{String, Any}[],
            "error" => first(sprint(showerror, error), 8_192))
    end
    execution = try
        _runtime_process(command, timeout_seconds)
    catch error
        return Dict{String, Any}(
            "runtime_id" => string(spec.id), "role" => string(spec.role),
            "spec" => julia_runtime_spec_dict(spec), "probe" => probe,
            "status" => "launch_error", "command" => command,
            "reports" => reports, "controller_project" => controller_project,
            "bundle_path" => nothing,
            "exit_code" => nothing, "elapsed_seconds" => 0.0,
            "stdout" => "", "stderr" => "",
            "failure_kind" => "launch_error",
            "failure_summary" => first(sprint(showerror, error), 2_048),
            "failure_frames" => Dict{String, Any}[],
            "error" => first(sprint(showerror, error), 8_192))
    end
    bundle_path = try
        _runtime_bundle(reports)
    catch error
        nothing
    end
    status = execution.timed_out ? "timeout" :
             execution.exit_code != 0 ? "failed" :
             bundle_path === nothing ? "missing_bundle" : "passed"
    failure_kind = status == "passed" ? "" :
                   status == "missing_bundle" ? "missing_bundle" :
                   _runtime_failure_kind(execution)
    failure_summary = status == "missing_bundle" ?
                      "suite emitted no run bundle" :
                      _runtime_failure_summary(execution, status)
    return Dict{String, Any}(
        "runtime_id" => string(spec.id), "role" => string(spec.role),
        "spec" => julia_runtime_spec_dict(spec), "probe" => probe,
        "status" => status, "command" => command, "reports" => reports,
        "controller_project" => controller_project,
        "bundle_path" => bundle_path, "exit_code" => execution.exit_code,
        "elapsed_seconds" => execution.elapsed_seconds,
        "stdout" => first(execution.stdout, 16_384),
        "stderr" => first(execution.stderr, 16_384),
        "failure_kind" => failure_kind,
        "failure_summary" => failure_summary,
        "failure_frames" => status == "passed" ? Dict{String, Any}[] :
                            _runtime_failure_frames(execution),
        "error" => status == "passed" ? "" :
                   status == "missing_bundle" ? "suite emitted no run bundle" :
                   status == "timeout" ? "suite exceeded $(timeout_seconds) seconds" :
                   "suite command failed")
end

const _RUNTIME_BACKEND_PACKAGES = Dict{Symbol, Pair{String, String}}(
    :benchmark => "BenchmarkTools" => "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf",
    :chairmark => "Chairmarks" => "0ca39b1e-fe0b-4e98-acfc-b1656634c4de")

function _runtime_backend_packages(suite::SoftwareSuite, profile::Symbol)
    backends = Set(run.feature.backend
    for run in plan_suite(suite; profile).runs if run.planned_status === :ready)
    return sort!([first(_RUNTIME_BACKEND_PACKAGES[backend])
                  for backend in backends if haskey(_RUNTIME_BACKEND_PACKAGES, backend)])
end

function _runtime_controller_project(root::String, spec::JuliaRuntimeSpec,
        backend_packages::Vector{String})
    directory = joinpath(root, "runtime-$(spec.id)", "controller")
    mkpath(directory)
    dependencies = Dict(first(pair) => last(pair)
    for pair in values(_RUNTIME_BACKEND_PACKAGES)
    if first(pair) in backend_packages)
    open(joinpath(directory, "Project.toml"), "w") do io
        println(io, "[deps]")
        for name in sort!(collect(keys(dependencies)))
            println(io, name, " = \"", dependencies[name], "\"")
        end
        println(io, "\n[compat]")
        for name in sort!(collect(keys(dependencies)))
            println(io, name, " = \"1\"")
        end
        println(io, "julia = \"1.10\"")
    end
    return directory
end

function _resumable_runtime_run(previous, spec::JuliaRuntimeSpec;
        suite::String, profile::Symbol, perfchecker_project::String)
    previous isa AbstractDict || return nothing
    String(get(previous, "suite", "")) == suite || return nothing
    String(get(previous, "profile", "")) == string(profile) || return nothing
    candidates = [run
                  for run in get(previous, "runs", Any[])
                  if String(get(run, "runtime_id", "")) == string(spec.id) &&
                     String(get(run, "role", "")) == string(spec.role) &&
                     String(get(get(run, "spec", Dict()), "selector", "")) ==
                     spec.selector && String(get(run, "status", "")) == "passed"]
    length(candidates) == 1 || return nothing
    record = only(candidates)
    bundle_path = get(record, "bundle_path", nothing)
    bundle_path isa AbstractString && isdir(bundle_path) || return nothing
    verified = try
        Bool(verify_run_bundle(bundle_path; require_integrity = true)["verified"])
    catch
        false
    end
    verified || return nothing
    old_probe = get(record, "probe", nothing)
    old_probe isa AbstractDict || return nothing
    current_probe = try
        probe_julia_runtime(spec; project = perfchecker_project)
    catch
        return nothing
    end
    all(key -> String(get(old_probe, key, "")) == String(get(current_probe, key, "")),
        ("version", "commit")) || return nothing
    resumed = Dict{String, Any}(String(key) => value for (key, value) in pairs(record))
    resumed["probe"] = current_probe
    resumed["reused"] = true
    resumed["reused_from_campaign_id"] = String(get(previous, "id", ""))
    resumed["stdout"] = ""
    resumed["stderr"] = ""
    return resumed
end

function _runtime_comparison(baseline::Dict{String, Any},
        candidate::Dict{String, Any}; relative_limits::AbstractDict,
        min_samples::Integer)
    base_path = get(baseline, "bundle_path", nothing)
    candidate_path = get(candidate, "bundle_path", nothing)
    if base_path === nothing || candidate_path === nothing
        failed = candidate_path === nothing ? candidate : baseline
        failure = String(get(failed, "failure_summary", "runtime bundle is unavailable"))
        return Dict{String, Any}(
            "schema_version" => "perfchecker-runtime-comparison/1",
            "baseline_runtime_id" => baseline["runtime_id"],
            "candidate_runtime_id" => candidate["runtime_id"],
            "status" => "unavailable", "passed" => false,
            "reason" => "runtime $(failed["runtime_id"]) did not emit a comparable bundle: $failure",
            "comparison" => nothing)
    end
    comparison = compare_bundles(read_run_bundle(base_path),
        read_run_bundle(candidate_path); relative_limits, min_samples)
    return Dict{String, Any}(
        "schema_version" => "perfchecker-runtime-comparison/1",
        "baseline_runtime_id" => baseline["runtime_id"],
        "candidate_runtime_id" => candidate["runtime_id"],
        "status" => comparison_passed(comparison) ? "passed" : "failed",
        "passed" => comparison_passed(comparison), "reason" => "",
        "comparison" => comparison_dict(comparison))
end

"Run one package suite under baseline and candidate Julia runtimes."
function run_julia_runtime_campaign(specs::AbstractVector{JuliaRuntimeSpec};
        suite::AbstractString, reports::AbstractString, profile::Symbol = :ci,
        factory::Symbol = :build_suite,
        perfchecker_project::AbstractString = dirname(@__DIR__),
        timeout_seconds::Real = 3_600,
        relative_limits::AbstractDict = Dict{String, Float64}(),
        min_samples::Integer = 1, strict::Bool = false,
        progress_callback = _ -> nothing, resume::Bool = false)
    length(specs) >= 2 || throw(ArgumentError(
        "a Julia runtime campaign requires at least two runtimes"))
    allunique(getfield.(specs, :id)) || throw(ArgumentError(
        "Julia runtime IDs must be unique"))
    baselines = findall(spec -> spec.role === :baseline, specs)
    length(baselines) == 1 || throw(ArgumentError(
        "a Julia runtime campaign requires exactly one baseline"))
    timeout_seconds > 0 || throw(ArgumentError("runtime timeout must be positive"))
    min_samples > 0 || throw(ArgumentError("min_samples must be positive"))
    suite_path = abspath(String(suite))
    isfile(suite_path) || throw(ArgumentError("suite file does not exist: $suite_path"))
    root = abspath(String(reports))
    mkpath(root)
    previous_path = joinpath(root, "julia-runtime-campaign.json")
    previous = if resume && isfile(previous_path)
        try
            JSON.parsefile(previous_path; use_mmap = false)
        catch
            nothing
        end
    else
        nothing
    end
    suite_definition = load_software_suite(suite_path; factory)
    backend_packages = _runtime_backend_packages(suite_definition, profile)
    started_at = string(Dates.now(Dates.UTC))
    id = string(uuid4())
    runs = Dict{String, Any}[]
    total = length(specs)
    _notify_suite_progress(progress_callback,
        Dict{String, Any}("schema_version" => "perfchecker-progress/1",
            "stage" => "runtime_campaign", "state" => "running",
            "completed" => 0, "total" => total, "fraction" => 0.0,
            "percent" => 0.0, "current_run" => nothing))
    for spec in specs
        report_directory = joinpath(root, "runtime-$(spec.id)")
        mkpath(report_directory)
        controller_project = _runtime_controller_project(root, spec, backend_packages)
        _notify_suite_progress(progress_callback,
            Dict{String, Any}("schema_version" => "perfchecker-progress/1",
                "stage" => "runtime_campaign", "state" => "running",
                "completed" => length(runs), "total" => total,
                "fraction" => length(runs) / total,
                "percent" => 100 * length(runs) / total,
                "current_run" => Dict("id" => string(spec.id),
                    "selector" => spec.selector, "role" => string(spec.role))))
        project = abspath(String(perfchecker_project))
        resumed = resume ?
                  _resumable_runtime_run(previous, spec;
            suite = suite_path, profile, perfchecker_project = project) : nothing
        push!(runs,
            resumed === nothing ?
            _runtime_campaign_run(spec; suite = suite_path,
                reports = report_directory, profile, factory,
                perfchecker_project = project,
                controller_project, backend_packages,
                timeout_seconds) : resumed)
        _notify_suite_progress(progress_callback,
            Dict{String, Any}("schema_version" => "perfchecker-progress/1",
                "stage" => "runtime_campaign", "state" => "running",
                "completed" => length(runs), "total" => total,
                "fraction" => length(runs) / total,
                "percent" => 100 * length(runs) / total,
                "current_run" => nothing))
    end
    baseline = runs[only(baselines)]
    comparisons = [_runtime_comparison(baseline, run;
                       relative_limits, min_samples) for run in runs if run !== baseline]
    campaign = JuliaRuntimeCampaign(id, suite_path, profile,
        specs[only(baselines)].id, started_at, string(Dates.now(Dates.UTC)),
        runs, comparisons)
    write_julia_runtime_campaign(campaign, root)
    write_julia_investigation(investigate_julia_regressions(campaign), root)
    passed = runtime_campaign_passed(campaign)
    _notify_suite_progress(progress_callback,
        Dict{String, Any}("schema_version" => "perfchecker-progress/1",
            "stage" => "runtime_campaign",
            "state" => (passed ? "complete" : "failed"),
            "completed" => total, "total" => total, "fraction" => 1.0,
            "percent" => 100.0, "current_run" => nothing))
    strict && !passed && error("Julia runtime campaign failed")
    return campaign
end

function julia_runtime_campaign_dict(campaign::JuliaRuntimeCampaign;
        include_output::Bool = false)
    runs = [begin
                record = copy(run)
                include_output || begin
                    record["stdout"] = ""
                    record["stderr"] = ""
                end
                record
            end
            for run in campaign.runs]
    passed = runtime_campaign_passed(campaign)
    return Dict{String, Any}(
        "schema_version" => JULIA_RUNTIME_CAMPAIGN_SCHEMA,
        "id" => campaign.id, "suite" => campaign.suite,
        "profile" => string(campaign.profile),
        "baseline_runtime_id" => string(campaign.baseline_id),
        "started_at" => campaign.started_at, "finished_at" => campaign.finished_at,
        "passed" => passed, "runs" => runs, "comparisons" => campaign.comparisons)
end

function write_julia_runtime_campaign(campaign::JuliaRuntimeCampaign,
        directory::AbstractString; include_output::Bool = false)
    root = abspath(String(directory))
    mkpath(root)
    json_path = joinpath(root, "julia-runtime-campaign.json")
    markdown_path = joinpath(root, "julia-runtime-campaign.md")
    _write_json(json_path,
        julia_runtime_campaign_dict(campaign; include_output); canonical = true)
    open(markdown_path, "w") do io
        payload = julia_runtime_campaign_dict(campaign)
        println(io, "# Julia runtime campaign\n")
        println(io, "Status: **$(payload["passed"] ? "PASS" : "FAIL")**  ")
        println(io, "Baseline: `$(campaign.baseline_id)`  ")
        println(io, "Suite: `$(campaign.suite)`\n")
        println(io, "| Runtime | Role | Julia | Status | Duration | Diagnostic |")
        println(io, "| --- | --- | --- | --- | ---: | --- |")
        for run in campaign.runs
            version = haskey(run, "probe") ? run["probe"]["version"] : "—"
            diagnostic = replace(String(get(run, "failure_summary", "")), '|' => "\\|")
            println(io,
                "| $(run["runtime_id"]) | $(run["role"]) | $version | " *
                "$(run["status"]) | $(round(run["elapsed_seconds"]; digits = 2)) s | " *
                "$diagnostic |")
        end
        println(io, "\n## Baseline comparisons\n")
        for comparison in campaign.comparisons
            println(io,
                "- `$(comparison["baseline_runtime_id"])` → " *
                "`$(comparison["candidate_runtime_id"])`: **$(comparison["status"])**")
        end
    end
    return [json_path, markdown_path]
end

@testitem "Julia runtime campaign contract" tags=[:unit, :runtime, :protocol] begin
    using JSON
    using PerfChecker

    campaign = JuliaRuntimeCampaign("campaign-1", "suite.jl", :ci, :stable,
        "start", "finish",
        [Dict{String, Any}("runtime_id" => "stable", "role" => "baseline",
            "status" => "passed", "stdout" => "secret", "stderr" => "",
            "elapsed_seconds" => 1.0)], Dict{String, Any}[])
    payload = julia_runtime_campaign_dict(campaign)
    @test payload["schema_version"] == "perfchecker-julia-runtime-campaign/1"
    @test payload["passed"]
    @test runtime_campaign_passed(campaign)
    @test only(payload["runs"])["stdout"] == ""
    @test julia_runtime_campaign_dict(campaign; include_output = true)["runs"][1]["stdout"] ==
          "secret"
    @test JSON.parsefile(
        joinpath(pkgdir(PerfChecker), "schemas",
            "perfchecker-julia-runtime-campaign-v1.schema.json");
        use_mmap = false)["type"] == "object"
    crash = (timed_out = false, exit_code = 1,
        stderr = "Exception: EXCEPTION_ACCESS_VIOLATION at 0x1\n" *
                 "build_suite at C:\\suite.jl:53:0", stdout = "")
    @test PerfChecker._runtime_failure_kind(crash) == "runtime_crash"
    @test startswith(PerfChecker._runtime_failure_summary(crash, "failed"), "Exception:")
    @test only(PerfChecker._runtime_failure_frames(crash))["source_line"] == 53
    @test PerfChecker._resumable_runtime_run(nothing,
        JuliaRuntimeSpec(:stable, "release"; role = :baseline);
        suite = "suite.jl", profile = :quick,
        perfchecker_project = pkgdir(PerfChecker)) === nothing
    mktempdir() do root
        paths = write_julia_runtime_campaign(campaign, root)
        @test all(isfile, paths)
        @test occursin("Julia runtime campaign", read(paths[2], String))
    end
end
