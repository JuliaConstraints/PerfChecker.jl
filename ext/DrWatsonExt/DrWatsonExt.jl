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

end
