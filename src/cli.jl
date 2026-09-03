const _CLI_PROFILES = Set((:quick, :ci, :historical, :release))

function _cli_split(args)
    separator = findfirst(==("--"), args)
    head = separator === nothing ? args : args[1:(separator - 1)]
    tail = separator === nothing ? String[] : String.(args[(separator + 1):end])
    options = Dict{String, Vector{String}}()
    positional = String[]
    for argument in head
        if startswith(argument, "--")
            token = argument[3:end]
            name, value = occursin('=', token) ? split(token, '='; limit = 2) :
                          (token, "true")
            push!(get!(options, name, String[]), value)
        else
            push!(positional, String(argument))
        end
    end
    return positional, options, tail
end

function _cli_value(options, name, default = nothing)
    haskey(options, name) ? last(options[name]) : default
end
_cli_values(options, name) = get(options, name, String[])
function _cli_bool(options, name, default = false)
    lowercase(String(
        _cli_value(options, name, string(default)))) in ("true", "1", "yes", "on")
end

function _cli_profile(options)
    profile = Symbol(_cli_value(options, "profile", "ci"))
    profile in _CLI_PROFILES || throw(ArgumentError("unknown profile $profile"))
    return profile
end

function _cli_limits(options)
    limits = Dict{String, Float64}()
    for item in _cli_values(options, "limit")
        metric, threshold = split(item, '='; limit = 2)
        limits[metric] = Base.parse(Float64, threshold)
    end
    return limits
end

function _candidate_from_payload(payload, context::AbstractString)
    payload isa AbstractDict || throw(ArgumentError(
        "$context must be a JSON object"))
    package = String(get(payload, "package", ""))
    isempty(package) && throw(ArgumentError("candidate package is required"))
    label = String(get(payload, "label", ""))
    revision = String(get(payload, "revision", ""))
    source = get(payload, "source", nothing)
    source = source === nothing || isempty(String(source)) ? nothing : String(source)
    compatibility = get(payload, "compatibility_version", nothing)
    compatibility = compatibility === nothing || isempty(String(compatibility)) ?
                    nothing : VersionNumber(String(compatibility))
    return package => SuiteCandidate(label, revision; source,
        compatibility_version = compatibility)
end

function _candidates_from_payloads(items, context::AbstractString)
    candidates = Dict{String, Vector{SuiteCandidate}}()
    for payload in items
        package, candidate = _candidate_from_payload(payload, context)
        push!(get!(candidates, package, SuiteCandidate[]), candidate)
    end
    return candidates
end

_cli_candidates(options) = _candidates_from_payloads(
    (JSON.parse(item) for item in _cli_values(options, "candidate")), "--candidate")

function _comparison_from_payload(payload, context::AbstractString)
    payload isa AbstractDict || throw(ArgumentError(
        "$context must be a JSON object"))
    return ComparisonPolicy(String(get(payload, "id", ""));
        package = String(get(payload, "package", "")),
        feature = String(get(payload, "feature", "")),
        comparison_key = String(get(payload, "comparison_key", "")),
        baselines = String.(get(payload, "baselines", String[])),
        candidates = String.(get(payload, "candidates", String[])),
        aggregation = Symbol(get(payload, "aggregation", "median")))
end

_cli_comparisons(options) = ComparisonPolicy[
    _comparison_from_payload(JSON.parse(item), "--comparison")
    for item in _cli_values(options, "comparison")]

function _cli_ui_configuration(options)
    path = _cli_value(options, "config")
    return path === nothing ? nothing : read_ui_configuration(String(path))
end

function _requested_candidates(options, configuration)
    result = configuration === nothing ? Dict{String, Vector{SuiteCandidate}}() :
             _candidates_from_payloads(get(configuration, "targets", Any[]),
                 "UI configuration target")
    for (package, candidates) in _cli_candidates(options)
        append!(get!(result, package, SuiteCandidate[]), candidates)
    end
    return result
end

function _requested_comparisons(options, configuration)
    result = configuration === nothing ? ComparisonPolicy[] :
             ComparisonPolicy[_comparison_from_payload(payload,
                 "UI configuration comparison")
                              for payload in get(configuration, "comparisons", Any[])]
    append!(result, _cli_comparisons(options))
    return result
end

function _cli_required(options, name)
    value = _cli_value(options, name)
    value === nothing && throw(ArgumentError("--$name=<value> is required"))
    return String(value)
end

function _cli_help(io::IO)
    print(io, """PerfChecker command line

Usage: perfchecker <command> [--option=value]

Commands:
  init             Generate a runnable feature suite
  plan             Resolve and print a suite plan
  preflight        Resolve dependency graphs without measuring
  run              Run a suite and write all reports
  compare          Compare two bundles and write reports
  check            Compare two bundles and gate on regressions
  report           Export portable JSON and Markdown from one bundle
  verify           Verify bundle SHA-256 integrity
  migrate          Rewrite a legacy bundle with current integrity metadata
  julia-campaign   Compare one suite across Julia stable/RC/nightly
  network          Measure a command tree; command follows --
  capabilities     Print controller capabilities as JSON
  version          Print the PerfChecker package version
""")
end

function _cli_progress_callback(options, output::IO)
    return _cli_value(options, "progress", "") == "jsonl" ?
           payload -> begin
        print(output, "PERFCHECKER_PROGRESS ")
        _canonical_json(output, payload)
        println(output)
    end : _ -> nothing
end

function _write_bundle_reports(bundle::RunBundle, root::AbstractString)
    directory = abspath(String(root))
    mkpath(directory)
    json_path = joinpath(directory, "bundle.json")
    markdown_path = joinpath(directory, "bundle.md")
    _write_json(json_path, bundle_dict(bundle); canonical = true)
    run_id = bundle.manifest["run_id"]
    suite = get(bundle.manifest, "suite", "unknown")
    state = get(bundle.manifest, "state", "unknown")
    runtime = get(get(bundle.manifest, "runtime", Dict()), "version", "unknown")
    open(markdown_path, "w") do io
        println(io, "# PerfChecker run $run_id\n")
        println(io, "- Suite: `$suite`")
        println(io, "- State: `$state`")
        println(io, "- Runtime: `$runtime`")
        println(io, "- Observations: $(length(bundle.observations))")
        println(io, "- Diagnostics: $(length(bundle.diagnostics))")
        println(io, "- Artifacts: $(length(bundle.artifacts))")
    end
    return [json_path, markdown_path]
end

"Implementation of the unified `perfchecker` CLI. Returns a process exit code."
function perfchecker_main(args = ARGS; stdout::IO = Base.stdout,
        stderr::IO = Base.stderr)
    isempty(args) && (_cli_help(stdout); return 0)
    command = String(first(args))
    positional, options, passthrough = _cli_split(String.(args[2:end]))
    try
        if command in ("help", "--help", "-h")
            _cli_help(stdout)
            return 0
        elseif command == "version"
            project = TOML.parsefile(joinpath(dirname(@__DIR__), "Project.toml"))
            println(stdout, project["version"])
            return 0
        elseif command == "init"
            root = abspath(_cli_value(options, "root", isempty(positional) ? pwd() :
                                                       first(positional)))
            paths = write_software_suite_template(root;
                force = _cli_bool(options, "force"))
            foreach(path -> println(stdout, path), paths)
            return 0
        elseif command == "plan"
            suite_path = abspath(_cli_value(options, "suite", joinpath("perf", "suite.jl")))
            factory = Symbol(_cli_value(options, "factory", "build_suite"))
            configuration = _cli_ui_configuration(options)
            plan = plan_suite(load_software_suite(suite_path; factory);
                profile = _cli_profile(options),
                candidates = _requested_candidates(options, configuration),
                comparisons = _requested_comparisons(options, configuration))
            output = _cli_value(options, "output")
            output === nothing ? print_suite_plan(stdout, plan) :
            _write_json(abspath(output), suite_plan_dict(plan); canonical = true)
            return 0
        elseif command == "preflight"
            suite_path = abspath(_cli_value(options, "suite", joinpath("perf", "suite.jl")))
            factory = Symbol(_cli_value(options, "factory", "build_suite"))
            configuration = _cli_ui_configuration(options)
            plan = plan_suite(load_software_suite(suite_path; factory);
                profile = _cli_profile(options),
                candidates = _requested_candidates(options, configuration),
                comparisons = _requested_comparisons(options, configuration))
            configuration === nothing ||
                (plan = select_suite_plan(plan, configuration))
            report = preflight_suite(plan;
                progress_callback = _cli_progress_callback(options, stdout))
            output = abspath(_cli_value(options, "output",
                joinpath("perf", "results", "compatibility.json")))
            write_compatibility_report(report, output)
            println(stdout, output)
            return preflight_passed(report) ? 0 : 1
        elseif command == "run"
            suite_path = abspath(_cli_value(options, "suite", joinpath("perf", "suite.jl")))
            reports = abspath(_cli_value(options, "reports", joinpath("perf", "results")))
            factory = Symbol(_cli_value(options, "factory", "build_suite"))
            configuration = _cli_ui_configuration(options)
            plan = plan_suite(load_software_suite(suite_path; factory);
                profile = _cli_profile(options),
                candidates = _requested_candidates(options, configuration),
                comparisons = _requested_comparisons(options, configuration))
            progress_callback = _cli_progress_callback(options, stdout)
            selected_ids = _cli_values(options, "run-id")
            !isempty(selected_ids) && configuration !== nothing &&
                throw(ArgumentError(
                    "--run-id and --config cannot be combined"))
            if configuration !== nothing
                plan = select_suite_plan(plan, configuration)
            elseif !isempty(selected_ids)
                plan = select_suite_plan(plan, selected_ids)
            end
            if _cli_bool(options, "preflight", true)
                report = preflight_suite(plan; progress_callback)
                write_compatibility_report(report,
                    joinpath(reports, "compatibility.json"))
                if !preflight_passed(report)
                    println(stderr, "PerfChecker: compatibility preflight failed")
                    return 1
                end
            end
            result = run_suite(plan; strict = false, progress_callback)
            write_suite_reports(result, reports)
            println(stdout, suite_passed(result) ? "PASS" : "FAIL")
            return suite_passed(result) ? 0 : 1
        elseif command in ("compare", "check")
            baseline = read_run_bundle(_cli_required(options, "baseline"))
            candidate = read_run_bundle(_cli_required(options, "candidate"))
            comparison = compare_bundles(baseline, candidate;
                relative_limits = _cli_limits(options),
                min_samples = Base.parse(Int, _cli_value(options, "min-samples", "1")))
            reports = abspath(_cli_value(options, "reports", joinpath("perf", "comparison")))
            mkpath(reports)
            write_comparison_json(comparison, joinpath(reports, "comparison.json"))
            write_comparison_markdown(comparison, joinpath(reports, "comparison.md"))
            passed = comparison_passed(comparison)
            println(stdout, passed ? "PASS" : "FAIL")
            return command == "check" && !passed ? 1 : 0
        elseif command == "report"
            bundle = read_run_bundle(_cli_required(options, "bundle"))
            paths = _write_bundle_reports(bundle,
                _cli_value(options, "reports", joinpath("perf", "report")))
            foreach(path -> println(stdout, path), paths)
            return 0
        elseif command == "verify"
            result = verify_run_bundle(_cli_required(options, "bundle");
                require_integrity = _cli_bool(options, "require-integrity", true))
            _canonical_json(stdout, result)
            println(stdout)
            return result["verified"] ? 0 : 1
        elseif command == "migrate"
            println(stdout,
                migrate_run_bundle(_cli_required(options, "source"),
                    _cli_required(options, "destination")))
            return 0
        elseif command == "julia-campaign"
            candidates = _cli_values(options, "candidate")
            isempty(candidates) && append!(candidates, ["rc", "nightly"])
            specs = julia_runtime_matrix(
                baseline = _cli_value(options, "baseline", "release"); candidates)
            campaign = run_julia_runtime_campaign(specs;
                suite = _cli_required(options, "suite"),
                reports = _cli_value(options, "reports", joinpath("perf", "julia-campaign")),
                profile = _cli_profile(options),
                factory = Symbol(_cli_value(options, "factory", "build_suite")),
                relative_limits = _cli_limits(options),
                min_samples = Base.parse(Int, _cli_value(options, "min-samples", "1")),
                timeout_seconds = Base.parse(Float64, _cli_value(options, "timeout", "3600")),
                progress_callback = _cli_progress_callback(options, stdout),
                resume = _cli_bool(options, "resume", false),
                strict = false)
            passed = runtime_campaign_passed(campaign)
            println(stdout, passed ? "PASS" : "FAIL")
            return passed ? 0 : 1
        elseif command == "network"
            isempty(passthrough) &&
                throw(ArgumentError("network command requires -- command"))
            external = _cli_bool(options, "external")
            interface_value = _cli_value(options, "interface")
            dns_value = _cli_value(options, "dns")
            spec = NetworkIsolationSpec(
                provider = Symbol(_cli_value(options, "provider", "auto")),
                distribution = _cli_value(options, "distribution"),
                interface = interface_value,
                external_connectivity = external,
                dns_servers = dns_value === nothing ? nothing : split(dns_value, ','))
            result = measure_isolated_network_command(passthrough; spec,
                directory = _cli_value(options, "directory", pwd()),
                timeout_seconds = Base.parse(Float64, _cli_value(options, "timeout", "300")),
                strict = false)
            output = abspath(_cli_value(options, "output", "perfchecker-network-result.json"))
            mkpath(dirname(output))
            _write_json(output,
                isolated_network_result_dict(result;
                    include_output = _cli_bool(options, "include-output"));
                canonical = true)
            println(stdout, output)
            return result.exit_code
        elseif command == "capabilities"
            payload = Dict{String, Any}(
                "schema_version" => "perfchecker-capabilities/1",
                "julia" => string(VERSION),
                "network_interface" => network_interface_capabilities(),
                "network_isolation" => network_isolation_capabilities(; probe = true),
                "commands" => ["init", "plan", "run", "compare", "check", "report",
                    "preflight", "verify", "migrate", "julia-campaign", "network"])
            _canonical_json(stdout, payload)
            println(stdout)
            return 0
        end
        throw(ArgumentError("unknown command: $command"))
    catch error
        println(stderr, "PerfChecker: ", sprint(showerror, error))
        return 2
    end
end

@testitem "Unified CLI" tags=[:unit, :cli] begin
    using JSON
    using PerfChecker

    output = IOBuffer()
    errors = IOBuffer()
    @test perfchecker_main(["help"]; stdout = output, stderr = errors) == 0
    @test occursin("julia-campaign", String(take!(output)))
    @test perfchecker_main(["unknown"]; stdout = output, stderr = errors) == 2
    @test occursin("unknown command", String(take!(errors)))

    mktempdir() do root
        write(joinpath(root, "Project.toml"), """
name = "CLIFixture"
uuid = "11111111-2222-3333-4444-555555555555"
version = "0.1.0"
""")
        @test perfchecker_main(["init", "--root=$root"];
            stdout = output, stderr = errors) == 0
        suite = load_software_suite(joinpath(root, "perf", "suite.jl"))
        @test suite.id == :clifixture
        @test first(suite.packages).package == "CLIFixture"
    end
end
