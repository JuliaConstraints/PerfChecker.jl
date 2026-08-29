function _selector_values(value, converter)
    value === nothing && return nothing
    values = value isa AbstractVector || value isa Tuple || value isa Set ? value : [value]
    return Set(converter(item) for item in values)
end

function _selector_version(value)
    value === nothing && return nothing
    value isa VersionNumber && return value
    text = String(value)
    startswith(text, "dev@") && (text = text[5:end])
    return VersionNumber(text)
end

function _suite_run_sort_key(run::PlannedFeatureRun, mode::Symbol)
    package = lowercase(run.package_suite.package)
    feature = lowercase(string(run.feature.id))
    version = run.target.compatibility_version
    backend = lowercase(string(run.feature.backend))
    mode === :package_version && return (package, version, feature, backend)
    mode === :version_package && return (version, package, feature, backend)
    mode === :feature_version && return (feature, version, package, backend)
    mode === :version_desc && return (-version.major, -version.minor, -version.patch,
        package, feature, backend)
    mode === :plan && return (0,)
    throw(ArgumentError("unknown suite sort mode $mode"))
end

"Filter and deterministically order a suite plan without starting workers."
function filter_suite_plan(plan::SuitePlan; packages = nothing, features = nothing,
        backends = nothing, statuses = nothing, from_version = nothing,
        to_version = nothing, search::AbstractString = "",
        sort::Symbol = :package_version, include_unavailable::Bool = true)
    package_filter = _selector_values(packages, value -> lowercase(String(value)))
    feature_filter = _selector_values(features, value -> Symbol(value))
    backend_filter = _selector_values(backends, value -> Symbol(value))
    status_filter = _selector_values(statuses, value -> Symbol(value))
    lower = _selector_version(from_version)
    upper = _selector_version(to_version)
    lower !== nothing && upper !== nothing && lower > upper &&
        throw(ArgumentError("from_version must not exceed to_version"))
    query = lowercase(strip(String(search)))
    selected = PlannedFeatureRun[]
    for run in plan.runs
        package = lowercase(run.package_suite.package)
        package_filter === nothing || package in package_filter || continue
        feature_filter === nothing || run.feature.id in feature_filter || continue
        backend_filter === nothing || run.feature.backend in backend_filter || continue
        status_filter === nothing || run.planned_status in status_filter || continue
        include_unavailable || run.planned_status === :ready || continue
        version = run.target.compatibility_version
        lower === nothing || version >= lower || continue
        upper === nothing || version <= upper || continue
        haystack = lowercase(join(
            (run.package_suite.package, string(run.feature.id),
                string(run.feature.backend), run.target.label, run.comparison_key,
                run.reason),
            " "))
        isempty(query) || occursin(query, haystack) || continue
        push!(selected, run)
    end
    sort === :plan || sort!(selected; by = run -> _suite_run_sort_key(run, sort))
    return SuitePlan(plan.suite, plan.profile, selected)
end

function print_suite_plan(io::IO, plan::SuitePlan; limit::Integer = typemax(Int))
    limit > 0 || throw(ArgumentError("limit must be positive"))
    println(io, "PerfChecker plan ", plan.suite.id, " [", plan.profile, "] — ",
        length(plan.runs), " runs")
    println(io, rpad("#", 5), rpad("package", 17), rpad("version", 16),
        rpad("backend", 16), rpad("feature", 32), "status")
    println(io, repeat("─", 96))
    for (index, run) in enumerate(Iterators.take(plan.runs, limit))
        println(io, rpad(string(index), 5),
            rpad(first(run.package_suite.package, 16), 17),
            rpad(first(run.target.label, 15), 16),
            rpad(first(string(run.feature.backend), 15), 16),
            rpad(first(string(run.feature.id), 31), 32), run.planned_status)
    end
    length(plan.runs) > limit && println(io, "… ", length(plan.runs) - limit,
        " additional runs")
    return plan
end

function _repl_prompt(input::IO, output::IO, label::String; default::String = "")
    print(output, label, isempty(default) ? ": " : " [$default]: ")
    flush(output)
    eof(input) && return default
    answer = strip(readline(input))
    return isempty(answer) ? default : answer
end

function _comma_values(text)
    isempty(strip(text)) ? nothing :
    strip.(filter(!isempty, split(text, ',')))
end

"Interactively build a filtered plan and runner overrides in a Julia REPL."
function configure_suite_repl(suite::SoftwareSuite; profile::Symbol = :historical,
        version_provider = get_pkg_versions, input::IO = stdin, output::IO = stdout)
    full_plan = plan_suite(suite; profile, version_provider)
    packages = sort!(unique(run.package_suite.package for run in full_plan.runs))
    backends = sort!(unique(string(run.feature.backend) for run in full_plan.runs))
    versions = sort!(unique(run.target.compatibility_version for run in full_plan.runs))
    println(output, "Packages: ", join(packages, ", "))
    println(output, "Backends: ", join(backends, ", "))
    println(output, "Version range: ", first(versions), " … ", last(versions))
    package_text = _repl_prompt(input, output, "Packages (comma-separated, blank=all)")
    feature_text = _repl_prompt(input, output, "Features (comma-separated, blank=all)")
    backend_text = _repl_prompt(input, output, "Backends (comma-separated, blank=all)")
    lower = _repl_prompt(input, output, "From version (inclusive)")
    upper = _repl_prompt(input, output, "To version (inclusive)")
    query = _repl_prompt(input, output, "Search")
    sort_text = _repl_prompt(input, output,
        "Sort (package_version/version_package/feature_version/version_desc/plan)";
        default = "package_version")
    plan = filter_suite_plan(full_plan;
        packages = _comma_values(package_text), features = _comma_values(feature_text),
        backends = _comma_values(backend_text),
        from_version = isempty(lower) ? nothing : lower,
        to_version = isempty(upper) ? nothing : upper, search = query,
        sort = Symbol(sort_text))
    print_suite_plan(output, plan; limit = 80)
    isempty(plan.runs) && throw(ArgumentError("the REPL selection contains no runs"))
    samples = parse(Int,
        _repl_prompt(input, output, "Samples"; default = "20"))
    seconds = parse(Float64,
        _repl_prompt(input, output, "Seconds per benchmark"; default = "0.2"))
    threads = parse(Int,
        _repl_prompt(input, output, "Worker threads"; default = "1"))
    confirm = lowercase(_repl_prompt(input, output, "Keep this selection? (yes/no)";
        default = "yes"))
    confirm in ("y", "yes", "o", "oui") || throw(InterruptException())
    return plan,
    Dict{Symbol, Any}(:samples => samples, :seconds => seconds,
        :threads => threads)
end

function _terminal_progress(io::IO; width::Integer = 30,
        interactive::Bool = isinteractive())
    return function (progress)
        total = Int(progress["total"])
        completed = Int(progress["completed"])
        fraction = Float64(progress["fraction"])
        filled = clamp(round(Int, width * fraction), 0, width)
        bar = "[" * repeat("█", filled) * repeat("░", width - filled) * "]"
        current = get(progress, "current_run", nothing)
        label = current === nothing ? String(progress["state"]) :
                "$(current["package"])/$(current["feature"]) $(current["version"])"
        line = "$bar $(lpad(completed, ndigits(max(total, 1))))/$total " * label
        if interactive
            print(io, '\r', rpad(first(line, min(length(line), 120)), 120))
            progress["state"] in ("complete", "failed", "cancelled") && println(io)
        elseif completed == total || current !== nothing
            println(io, line)
        end
        flush(io)
    end
end

"Run a selected plan with a terminal progress bar and optional report output."
function run_suite_repl(plan::SuitePlan; overrides = Dict{Symbol, Any}(),
        reports = nothing, output::IO = stdout, interactive::Bool = isinteractive(),
        strict::Bool = true, kwargs...)
    callback = _terminal_progress(output; interactive)
    result = run_suite(plan; overrides, strict = false,
        progress_callback = callback, kwargs...)
    reports === nothing || write_suite_reports(result, String(reports))
    strict && !suite_passed(result) && throw(SuiteRunError(result))
    return result
end

function run_suite_repl(suite::SoftwareSuite; profile::Symbol = :historical,
        version_provider = get_pkg_versions, input::IO = stdin, output::IO = stdout,
        reports = nothing, interactive::Bool = isinteractive(), strict::Bool = true,
        kwargs...)
    plan, overrides = configure_suite_repl(suite; profile, version_provider, input,
        output)
    return run_suite_repl(plan; overrides, reports, output, interactive, strict,
        kwargs...)
end

@testitem "REPL suite selection and progress" tags=[:unit, :repl] begin
    using PerfChecker

    feature = FeatureSpec(:parse; backend = :network,
        variants = [FeatureVariant(@__FILE__; until = v"1.9",
                comparison_key = "legacy"),
            FeatureVariant(@__FILE__; since = v"2", comparison_key = "current")])
    package = PackageSuite("Example"; source = @__DIR__, environment = @__DIR__,
        versions = [v"1", v"2"], features = [feature], include_dev = false)
    suite = SoftwareSuite(:repl_demo, [package])
    plan = plan_suite(suite; profile = :historical,
        version_provider = _ -> [v"1", v"2"])
    selected = filter_suite_plan(plan; from_version = v"2", backends = :network)
    @test length(selected.runs) == 1
    @test only(selected.runs).target.version == v"2"
    buffer = IOBuffer()
    print_suite_plan(buffer, selected)
    @test occursin("Example", String(take!(buffer)))
    @test_throws ArgumentError filter_suite_plan(plan; from_version = v"2",
        to_version = v"1")
end
