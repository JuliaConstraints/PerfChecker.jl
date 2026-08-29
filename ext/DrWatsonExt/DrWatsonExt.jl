module DrWatsonExt

using DrWatson
using PerfChecker

function PerfChecker.drwatson_parameters(plan::PerfChecker.SuitePlan)
    return [Dict{String, Any}(
                "suite" => string(run.suite),
                "package" => run.package_suite.package,
                "feature" => string(run.feature.id),
                "version" => run.target.label,
                "comparison_key" => run.comparison_key,
                "status" => string(run.planned_status)) for run in plan.runs]
end

function PerfChecker.drwatson_parameters(suite::PerfChecker.SoftwareSuite;
        profile::Symbol = :quick, kwargs...)
    return PerfChecker.drwatson_parameters(
        PerfChecker.plan_suite(suite; profile, kwargs...))
end

function PerfChecker.drwatson_savename(run::PerfChecker.PlannedFeatureRun;
        suffix::AbstractString = "jld2")
    parameters = Dict(
        "suite" => string(run.suite),
        "package" => run.package_suite.package,
        "feature" => string(run.feature.id),
        "version" => run.target.label)
    return DrWatson.savename(parameters, String(suffix))
end

function PerfChecker.drwatson_produce_or_load(producer::Function,
        parameters::AbstractDict; directory::AbstractString = "",
        force::Bool = false, tag::Bool = true, kwargs...)
    return DrWatson.produce_or_load(parameters, String(directory);
        force, tag, kwargs...) do config
        produced = producer(config)
        return produced isa AbstractDict ? produced : Dict("result" => produced)
    end
end

function PerfChecker.drwatson_run_suite(suite::PerfChecker.SoftwareSuite;
        profile::Symbol = :quick, directory::AbstractString = "",
        force::Bool = false, tag::Bool = true, version_provider = PerfChecker.get_pkg_versions,
        executor = PerfChecker._default_suite_executor, overrides = Dict{Symbol, Any}(),
        relative_limits = Dict{String, Float64}(), min_samples::Integer = 1)
    plan = PerfChecker.plan_suite(suite; profile, version_provider)
    revision = PerfChecker.suite_plan_dict(plan)["plan_revision"]
    root = isempty(directory) ? DrWatson.datadir("perfchecker", string(suite.id)) :
           abspath(String(directory))
    parameters = Dict("suite" => string(suite.id), "profile" => string(profile),
        "plan_revision" => revision)
    return PerfChecker.drwatson_produce_or_load(parameters; directory = root,
        force, tag) do _
        result = PerfChecker.run_suite(plan; executor, overrides, strict = false)
        reports = joinpath(root, "reports-$revision")
        paths = PerfChecker.write_suite_reports(result, reports;
            relative_limits, min_samples)
        Dict("passed" => PerfChecker.suite_passed(result),
            "reports" => reports, "artifacts" => paths,
            "finished_at" => result.finished_at)
    end
end

end
