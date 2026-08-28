module OxygenExt

using Oxygen
using PerfChecker

function PerfChecker.register_oxygen_routes!(provider::Function;
        prefix::AbstractString = "/perfchecker/v1")
    api = Oxygen.router(String(prefix); tags = ["PerfChecker"])

    Oxygen.get(api("/capabilities")) do
        return Oxygen.json(Dict(
            "schema_version" => "perfchecker-capabilities/1",
            "read_only" => true,
            "resources" => ["suite", "runs"]))
    end

    Oxygen.get(api("/suite")) do
        result = provider()
        return Oxygen.json(PerfChecker.suite_dict(result))
    end

    Oxygen.get(api("/runs")) do
        result = provider()
        return Oxygen.json(PerfChecker.suite_dict(result)["runs"])
    end

    return api
end

function PerfChecker.register_oxygen_routes!(result::PerfChecker.SoftwareSuiteResult;
        kwargs...)
    return PerfChecker.register_oxygen_routes!(() -> result; kwargs...)
end

function PerfChecker.register_oxygen_routes!(suite::PerfChecker.SoftwareSuite;
        profile::Symbol = :quick, prefix::AbstractString = "/perfchecker/v1",
        version_provider = PerfChecker.get_pkg_versions,
        overrides::AbstractDict = Dict{Symbol, Any}(),
        executor = PerfChecker._default_suite_executor)
    api = Oxygen.router(String(prefix); tags = ["PerfChecker"])
    jobs = Dict{String, PerfChecker.SuiteJob}()

    Oxygen.get(api("/capabilities")) do
        return Oxygen.json(Dict(
            "schema_version" => "perfchecker-capabilities/1",
            "read_only" => false,
            "resources" => ["suite-plan", "jobs"],
            "runner" => "Malt"))
    end

    Oxygen.get(api("/suite-plan")) do
        plan = PerfChecker.plan_suite(suite; profile, version_provider)
        return Oxygen.json(PerfChecker.suite_plan_dict(plan))
    end

    Oxygen.post(api("/jobs")) do
        plan = PerfChecker.plan_suite(suite; profile, version_provider)
        job = PerfChecker.launch_suite(plan; overrides, executor)
        jobs[string(job.id)] = job
        return Oxygen.json(PerfChecker.suite_job_dict(job))
    end

    Oxygen.get(api("/jobs")) do request
        id = get(Oxygen.queryparams(request), "id", "")
        job = get(jobs, id, nothing)
        job === nothing && return Oxygen.json(Dict("error" => "unknown suite job"))
        return Oxygen.json(PerfChecker.suite_job_dict(job))
    end

    return api
end

function PerfChecker.serve_suite(provider::Function; host::AbstractString = "127.0.0.1",
        port::Integer = 8080, async::Bool = false, prefix::AbstractString = "/perfchecker/v1",
        kwargs...)
    PerfChecker.register_oxygen_routes!(provider; prefix)
    return Oxygen.serve(; host = String(host), port = Int(port), async, kwargs...)
end

function PerfChecker.serve_suite(result::PerfChecker.SoftwareSuiteResult; kwargs...)
    return PerfChecker.serve_suite(() -> result; kwargs...)
end

function PerfChecker.serve_suite(suite::PerfChecker.SoftwareSuite;
        host::AbstractString = "127.0.0.1", port::Integer = 8080,
        async::Bool = false, prefix::AbstractString = "/perfchecker/v1", kwargs...)
    PerfChecker.register_oxygen_routes!(suite; prefix, kwargs...)
    return Oxygen.serve(; host = String(host), port = Int(port), async)
end

end
