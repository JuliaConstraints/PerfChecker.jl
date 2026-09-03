const COMPATIBILITY_REPORT_SCHEMA = "perfchecker-compatibility-report/1"

"Structured dependency-resolution evidence produced before measurement."
struct CompatibilityReport
    suite::Symbol
    profile::Symbol
    checked_at::String
    diagnostics::Vector{Dict{String, Any}}
end

function _compatibility_blockers(message::AbstractString)
    names = Set{String}()
    for pattern in (r"(?i)package\s+([A-Za-z][A-Za-z0-9_]*)",
        r"(?i)compatibility requirements with ([A-Za-z][A-Za-z0-9_]*)",
        r"[└├]─([A-Za-z][A-Za-z0-9_]*)")
        for matched in eachmatch(pattern, String(message))
            push!(names, matched.captures[1])
        end
    end
    return sort!(collect(names))
end

function _default_preflight_resolver(planned::PlannedFeatureRun,
        overrides::AbstractDict)
    config = _run_config(planned, overrides)
    root, _ = _prepare_check_environment(config)
    rm(root; recursive = true, force = true)
    return nothing
end

"Resolve every ready feature/version environment without running a workload."
function preflight_suite(plan::SuitePlan;
        overrides::AbstractDict = Dict{Symbol, Any}(),
        resolver = _default_preflight_resolver, progress_callback = _ -> nothing)
    diagnostics = Dict{String, Any}[]
    resolved = Dict{String, Dict{String, Any}}()
    total = length(plan.runs)
    _notify_suite_progress(progress_callback,
        Dict{String, Any}("schema_version" => "perfchecker-progress/1",
            "stage" => "preflight", "state" => "running", "completed" => 0,
            "total" => total, "fraction" => 0.0, "percent" => 0.0,
            "current_run" => nothing))
    for planned in plan.runs
        run_id = planned_run_id(planned)
        common = Dict{String, Any}(
            "run_id" => run_id,
            "package" => planned.package_suite.package,
            "package_suite" => string(planned.package_suite.id),
            "feature" => string(planned.feature.id),
            "target" => planned.target.label)
        completed = length(diagnostics)
        _notify_suite_progress(progress_callback,
            Dict{String, Any}("schema_version" => "perfchecker-progress/1",
                "stage" => "preflight", "state" => "running",
                "completed" => completed, "total" => total,
                "fraction" => total == 0 ? 1.0 : completed / total,
                "percent" => total == 0 ? 100.0 : 100 * completed / total,
                "current_run" => Dict("id" => run_id,
                    "package" => planned.package_suite.package,
                    "feature" => string(planned.feature.id),
                    "version" => planned.target.label)))
        if planned.planned_status !== :ready
            push!(diagnostics,
                merge(common,
                    Dict{String, Any}(
                        "status" => "feature_unavailable",
                        "blocking" => false,
                        "blocking_packages" => String[],
                        "message" => planned.reason)))
            completed = length(diagnostics)
            _notify_suite_progress(progress_callback,
                Dict{String, Any}("schema_version" => "perfchecker-progress/1",
                    "stage" => "preflight", "state" => "running",
                    "completed" => completed, "total" => total,
                    "fraction" => total == 0 ? 1.0 : completed / total,
                    "percent" => total == 0 ? 100.0 : 100 * completed / total,
                    "current_run" => Dict("id" => run_id,
                        "package" => planned.package_suite.package,
                        "feature" => string(planned.feature.id),
                        "version" => planned.target.label)))
            continue
        end
        config = _run_config(planned, overrides)
        key = _suite_environment_key(planned, config)
        evidence = get!(resolved, key) do
            try
                Base.invokelatest(resolver, planned, overrides)
                Dict{String, Any}(
                    "status" => "supported",
                    "blocking" => false,
                    "blocking_packages" => String[],
                    "message" => "dependency graph resolved inside declared constraints")
            catch error
                message = sprint(showerror, error)
                status = _unavailable_exception(error) ? "unsatisfiable" : "unknown"
                Dict{String, Any}(
                    "status" => status,
                    "blocking" => true,
                    "blocking_packages" => _compatibility_blockers(message),
                    "message" => first(message, 16_384))
            end
        end
        push!(diagnostics, merge(common, copy(evidence)))
        completed = length(diagnostics)
        _notify_suite_progress(progress_callback,
            Dict{String, Any}("schema_version" => "perfchecker-progress/1",
                "stage" => "preflight", "state" => "running",
                "completed" => completed, "total" => total,
                "fraction" => total == 0 ? 1.0 : completed / total,
                "percent" => total == 0 ? 100.0 : 100 * completed / total,
                "current_run" => Dict("id" => run_id,
                    "package" => planned.package_suite.package,
                    "feature" => string(planned.feature.id),
                    "version" => planned.target.label)))
    end
    _notify_suite_progress(progress_callback,
        Dict{String, Any}("schema_version" => "perfchecker-progress/1",
            "stage" => "preflight", "state" => "complete", "completed" => total,
            "total" => total, "fraction" => 1.0, "percent" => 100.0,
            "current_run" => nothing))
    return CompatibilityReport(plan.suite.id, plan.profile,
        string(Dates.now(Dates.UTC)), diagnostics)
end

function preflight_suite(suite::SoftwareSuite; profile::Symbol = :quick,
        version_provider = get_pkg_versions, kwargs...)
    preflight_suite(
        plan_suite(suite; profile, version_provider); kwargs...)
end

function preflight_passed(report::CompatibilityReport)
    !any(Bool(get(item, "blocking", true)) for item in report.diagnostics)
end

function compatibility_report_dict(report::CompatibilityReport)
    counts = Dict(status => count(item -> item["status"] == status,
                      report.diagnostics)
    for status in ("supported", "feature_unavailable", "unsatisfiable", "unknown"))
    return Dict{String, Any}(
        "schema_version" => COMPATIBILITY_REPORT_SCHEMA,
        "suite" => string(report.suite),
        "profile" => string(report.profile),
        "checked_at" => report.checked_at,
        "passed" => preflight_passed(report),
        "counts" => counts,
        "diagnostics" => report.diagnostics)
end

function write_compatibility_report(report::CompatibilityReport,
        path::AbstractString)
    target = abspath(String(path))
    mkpath(dirname(target))
    return _write_json(target, compatibility_report_dict(report); canonical = true)
end

@testitem "Suite compatibility preflight" tags=[:unit, :compatibility] begin
    using PerfChecker
    import Pkg

    feature = FeatureSpec(:parse; entrypoint = @__FILE__)
    package = PackageSuite("Example"; environment = @__DIR__, source = @__DIR__,
        versions = [v"1"], include_dev = false, features = [feature])
    plan = plan_suite(SoftwareSuite(:compat, [package]); profile = :release,
        version_provider = _ -> [v"1"])
    supported = preflight_suite(plan; resolver = (_, _) -> nothing)
    @test preflight_passed(supported)
    @test compatibility_report_dict(supported)["counts"]["supported"] == 1

    failed = preflight_suite(plan;
        resolver = (_,
            _) -> throw(Pkg.Types.PkgError("Unsatisfiable requirements detected for package Demo")))
    @test !preflight_passed(failed)
    diagnostic = only(failed.diagnostics)
    @test diagnostic["status"] == "unsatisfiable"
    @test "Demo" in diagnostic["blocking_packages"]

    second_feature = FeatureSpec(:format; entrypoint = @__FILE__)
    repeated_package = PackageSuite("Example"; environment = @__DIR__,
        source = @__DIR__, versions = [v"1"], include_dev = false,
        features = [feature, second_feature])
    repeated_plan = plan_suite(SoftwareSuite(:cached_compat, [repeated_package]);
        profile = :release, version_provider = _ -> [v"1"])
    calls = Ref(0)
    cached = preflight_suite(repeated_plan; resolver = (_, _) -> (calls[] += 1))
    @test preflight_passed(cached)
    @test calls[] == 1
    @test length(cached.diagnostics) == 2
end
