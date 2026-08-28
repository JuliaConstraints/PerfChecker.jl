module OxygenExt

using Dates
using HTTP
using JSON
using Oxygen
using PerfChecker

include("studio.jl")

function PerfChecker.register_oxygen_routes!(provider::Function;
        prefix::AbstractString = "/perfchecker/v1")
    api = Oxygen.router(String(prefix); tags = ["PerfChecker"])
    Oxygen.get(api("/capabilities")) do
        Oxygen.json(Dict(
            "schema_version" => "perfchecker-capabilities/1",
            "read_only" => true,
            "resources" => ["suite", "runs"]))
    end
    Oxygen.get(api("/suite")) do
        Oxygen.json(PerfChecker.suite_dict(provider()))
    end
    Oxygen.get(api("/runs")) do
        Oxygen.json(PerfChecker.suite_dict(provider())["runs"])
    end
    return api
end

function PerfChecker.register_oxygen_routes!(result::PerfChecker.SoftwareSuiteResult;
        kwargs...)
    return PerfChecker.register_oxygen_routes!(() -> result; kwargs...)
end

function PerfChecker.register_oxygen_routes!(bundle::PerfChecker.RunBundle;
        prefix::AbstractString = "/perfchecker/v1")
    api = Oxygen.router(String(prefix); tags = ["PerfChecker bundles"])
    Oxygen.get(api("/capabilities")) do
        Oxygen.json(Dict(
            "schema_version" => "perfchecker-capabilities/1",
            "read_only" => true,
            "resources" => ["manifest", "measurement-definitions", "observations",
                "diagnostics", "artifacts", "version-comparison"]))
    end
    Oxygen.get(api("/manifest")) do
        Oxygen.json(bundle.manifest)
    end
    Oxygen.get(api("/measurement-definitions")) do
        Oxygen.json(bundle.measurement_definitions)
    end
    Oxygen.get(api("/observations")) do
        Oxygen.json(bundle.observations)
    end
    Oxygen.get(api("/diagnostics")) do
        Oxygen.json(bundle.diagnostics)
    end
    Oxygen.get(api("/artifacts")) do
        Oxygen.json(bundle.artifacts)
    end
    Oxygen.get(api("/version-comparison")) do
        Oxygen.json(PerfChecker.version_comparison_dict(
            PerfChecker.compare_suite_versions(bundle)))
    end
    return api
end

function _public_manifests(store::String)
    manifests = PerfChecker.list_run_bundles(store; recursive = true)
    return [Dict(key => value for (key, value) in pairs(manifest)
                 if key != "bundle_path") for manifest in manifests], manifests
end

function _bundle_by_id(store::String, id::AbstractString)
    _, manifests = _public_manifests(store)
    index = findfirst(item -> get(item, "run_id", "") == id, manifests)
    index === nothing && return nothing
    return PerfChecker.read_run_bundle(manifests[index]["bundle_path"])
end

function _register_result_routes!(api, store::String)
    handler = function(request)
        id = get(Oxygen.queryparams(request), "id", "")
        public, _ = _public_manifests(store)
        isempty(id) && return Oxygen.json(public)
        bundle = _bundle_by_id(store, id)
        bundle === nothing && return Oxygen.json(Dict("error" => "unknown run"); status = 404)
        return Oxygen.json(PerfChecker.bundle_dict(bundle))
    end
    Oxygen.get(handler, api("/results"))
    Oxygen.get(handler, api("/runs"))
    Oxygen.get(api("/version-comparison")) do request
        id = get(Oxygen.queryparams(request), "id", "")
        bundle = _bundle_by_id(store, id)
        bundle === nothing && return Oxygen.json(Dict("error" => "unknown run"); status = 404)
        return Oxygen.json(PerfChecker.version_comparison_dict(
            PerfChecker.compare_suite_versions(bundle)))
    end
end

function PerfChecker.register_oxygen_routes!(root::AbstractString;
        prefix::AbstractString = "/perfchecker/v1", allow_ingest::Bool = false)
    store = abspath(String(root))
    allow_ingest ? mkpath(store) :
        isdir(store) || throw(ArgumentError("bundle store does not exist: $store"))
    api = Oxygen.router(String(prefix); tags = ["PerfChecker bundle store"])
    _register_studio_assets!(api)
    Oxygen.get(api("/")) do
        _studio_response(String(prefix); writable = false)
    end
    Oxygen.get(api("/capabilities")) do
        Oxygen.json(Dict(
            "schema_version" => "perfchecker-capabilities/1",
            "read_only" => !allow_ingest,
            "resources" => allow_ingest ? ["results", "version-comparison", "ingest"] :
                           ["results", "version-comparison"],
            "protocol" => "perfchecker-run-bundle/1"))
    end
    _register_result_routes!(api, store)
    if allow_ingest
        Oxygen.post(api("/ingest")) do request
            payload = JSON.parse(String(request.body))
            bundle = PerfChecker._provider_result(payload)
            destination = joinpath(store, "run-$(bundle.manifest["run_id"])")
            PerfChecker.write_run_bundle(bundle, destination)
            return Oxygen.json(PerfChecker.bundle_dict(bundle; include_records = false);
                status = 201)
        end
    end
    return api
end

function PerfChecker.register_oxygen_routes!(suite::PerfChecker.SoftwareSuite;
        profile::Symbol = :quick, prefix::AbstractString = "/perfchecker/v1",
        version_provider = PerfChecker.get_pkg_versions,
        overrides::AbstractDict = Dict{Symbol, Any}(),
        executor = PerfChecker._default_suite_executor,
        reports_root::AbstractString = joinpath(pwd(), "perfchecker-results"),
        max_concurrent::Integer = 1, authenticator = nothing,
        authorizer = _default_studio_authorizer)
    return _register_suite_workspace!(suite; profile, prefix = String(prefix),
        version_provider, overrides, executor,
        reports_root = abspath(String(reports_root)), max_concurrent = Int(max_concurrent),
        authenticator, authorizer)
end

function PerfChecker.serve_suite(provider::Function; host::AbstractString = "127.0.0.1",
        port::Integer = 8080, async::Bool = false,
        prefix::AbstractString = "/perfchecker/v1", kwargs...)
    PerfChecker.register_oxygen_routes!(provider; prefix)
    return Oxygen.serve(; host = String(host), port = Int(port), async, kwargs...)
end

function PerfChecker.serve_suite(result::PerfChecker.SoftwareSuiteResult; kwargs...)
    return PerfChecker.serve_suite(() -> result; kwargs...)
end

function PerfChecker.serve_suite(bundle::PerfChecker.RunBundle;
        host::AbstractString = "127.0.0.1", port::Integer = 8080,
        async::Bool = false, prefix::AbstractString = "/perfchecker/v1", kwargs...)
    PerfChecker.register_oxygen_routes!(bundle; prefix)
    return Oxygen.serve(; host = String(host), port = Int(port), async, kwargs...)
end

function PerfChecker.serve_suite(root::AbstractString;
        host::AbstractString = "127.0.0.1", port::Integer = 8080,
        async::Bool = false, prefix::AbstractString = "/perfchecker/v1",
        allow_ingest::Bool = false, kwargs...)
    PerfChecker.register_oxygen_routes!(root; prefix, allow_ingest)
    return Oxygen.serve(; host = String(host), port = Int(port), async, kwargs...)
end

function PerfChecker.serve_suite(suite::PerfChecker.SoftwareSuite;
        host::AbstractString = "127.0.0.1", port::Integer = 8080,
        async::Bool = false, prefix::AbstractString = "/perfchecker/v1",
        allow_remote_control::Bool = false, authenticator = nothing, kwargs...)
    normalized_host = lowercase(String(host))
    loopback = normalized_host in ("127.0.0.1", "localhost", "::1")
    loopback || (allow_remote_control && authenticator !== nothing) || throw(ArgumentError(
        "remote performance control requires allow_remote_control=true and an authenticator"))
    PerfChecker.register_oxygen_routes!(suite; prefix, authenticator, kwargs...)
    return Oxygen.serve(; host = String(host), port = Int(port), async)
end

end
