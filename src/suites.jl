const SuiteVersion = Union{VersionNumber, Symbol, String}

"A named Git branch, tag, or commit evaluated beside releases and the working tree."
struct SuiteCandidate
    label::String
    revision::String
    source::Union{Nothing, String}
    compatibility_version::Union{Nothing, VersionNumber}
    dependencies::Vector{Any}
end

function SuiteCandidate(label::AbstractString, revision::AbstractString;
        source = nothing, compatibility_version = nothing,
        dependencies::AbstractVector = Any[])
    isempty(strip(String(label))) && throw(ArgumentError("candidate label cannot be empty"))
    isempty(strip(String(revision))) &&
        throw(ArgumentError("candidate revision cannot be empty"))
    normalized_source = source === nothing ? nothing : String(source)
    compatibility = compatibility_version === nothing ? nothing :
                    VersionNumber(compatibility_version)
    return SuiteCandidate(String(label), String(revision), normalized_source,
        compatibility, Any[item for item in dependencies])
end

"An exact or grouped reference used to compare several candidate targets."
struct ComparisonPolicy
    id::String
    package::String
    feature::String
    comparison_key::String
    baselines::Vector{String}
    candidates::Vector{String}
    aggregation::Symbol
end

function ComparisonPolicy(id::AbstractString; package::AbstractString = "",
        feature::AbstractString = "", comparison_key::AbstractString = "",
        baselines::AbstractVector{<:AbstractString},
        candidates::AbstractVector{<:AbstractString}, aggregation::Symbol = :median)
    isempty(strip(String(id))) &&
        throw(ArgumentError("comparison policy id cannot be empty"))
    isempty(feature) && isempty(comparison_key) &&
        throw(ArgumentError(
            "comparison policy requires a feature or comparison_key"))
    isempty(baselines) && throw(ArgumentError("comparison policy requires a baseline"))
    isempty(candidates) && throw(ArgumentError("comparison policy requires a candidate"))
    aggregation in (:median, :mean, :minimum, :maximum) || throw(ArgumentError(
        "comparison aggregation must be :median, :mean, :minimum, or :maximum"))
    return ComparisonPolicy(String(id), String(package), String(feature),
        String(comparison_key), unique!(String.(baselines)),
        unique!(String.(candidates)), aggregation)
end

function comparison_policy_dict(policy::ComparisonPolicy)
    return Dict{String, Any}("id" => policy.id, "package" => policy.package,
        "feature" => policy.feature, "comparison_key" => policy.comparison_key,
        "baselines" => policy.baselines, "candidates" => policy.candidates,
        "aggregation" => string(policy.aggregation))
end

"A closed package-version interval with explicit exclusions."
struct VersionWindow
    since::Union{Nothing, VersionNumber}
    until::Union{Nothing, VersionNumber}
    excluded::Set{VersionNumber}
end

function VersionWindow(; since = nothing, until = nothing,
        excluded::AbstractVector{VersionNumber} = VersionNumber[])
    lo = since === nothing ? nothing : VersionNumber(since)
    hi = until === nothing ? nothing : VersionNumber(until)
    lo !== nothing && hi !== nothing && lo > hi &&
        throw(ArgumentError("version window starts after it ends"))
    return VersionWindow(lo, hi, Set(excluded))
end

function supports(window::VersionWindow, version::VersionNumber)
    window.since !== nothing && version < window.since && return false
    window.until !== nothing && version > window.until && return false
    return version ∉ window.excluded
end

"One workload implementation over a package-version interval."
struct FeatureVariant
    window::VersionWindow
    entrypoint::String
    comparison_key::String
    options::Dict{Symbol, Any}
end

function FeatureVariant(entrypoint::AbstractString; since = nothing, until = nothing,
        excluded::AbstractVector{VersionNumber} = VersionNumber[],
        comparison_key::AbstractString = "", options = Dict{Symbol, Any}())
    path = abspath(String(entrypoint))
    isfile(path) || throw(ArgumentError("feature entrypoint does not exist: $path"))
    normalized = Dict{Symbol, Any}()
    for (key, value) in pairs(options)
        key isa Symbol || throw(ArgumentError("variant option keys must be symbols"))
        normalized[key] = value
    end
    return FeatureVariant(VersionWindow(; since, until, excluded), path,
        String(comparison_key), normalized)
end

"A feature-level performance contract."
struct FeatureSpec
    id::Symbol
    workload::Symbol
    description::String
    backend::Symbol
    variants::Vector{FeatureVariant}
    julia_window::VersionWindow
    options::Dict{Symbol, Any}
end

function FeatureSpec(id::Symbol; description::AbstractString = "",
        backend::Symbol = :benchmark, variants = nothing, entrypoint = nothing,
        workload = nothing,
        since = nothing, until = nothing,
        excluded::AbstractVector{VersionNumber} = VersionNumber[],
        julia_since = nothing, julia_until = nothing,
        julia_excluded::AbstractVector{VersionNumber} = VersionNumber[],
        comparison_key::AbstractString = string(id), options = Dict{Symbol, Any}())
    implementations = if variants === nothing
        entrypoint isa AbstractString ||
            throw(ArgumentError("feature $id requires an entrypoint"))
        [FeatureVariant(entrypoint; since, until, excluded, comparison_key)]
    else
        FeatureVariant[variant for variant in variants]
    end
    isempty(implementations) && throw(ArgumentError("feature $id has no variants"))
    normalized = Dict{Symbol, Any}()
    for (key, value) in pairs(options)
        key isa Symbol || throw(ArgumentError("feature option keys must be symbols"))
        normalized[key] = value
    end
    business_feature = workload === nothing ? id : Symbol(workload)
    return FeatureSpec(id, business_feature, String(description), backend, implementations,
        VersionWindow(; since = julia_since, until = julia_until,
            excluded = julia_excluded), normalized)
end

"Stable business-feature identifier shared by plans, reports, and user interfaces."
workload_id(feature::FeatureSpec) = feature.workload

"All feature measurements owned by one package."
struct PackageSuite
    id::Symbol
    package::String
    environment::String
    source::Union{Nothing, String}
    dev_sources::Vector{String}
    release_pins::Dict{VersionNumber, Vector{Any}}
    versions::Union{Symbol, Vector{VersionNumber}}
    features::Vector{FeatureSpec}
    include_dev::Bool
    candidates::Vector{SuiteCandidate}
end

function PackageSuite(package::AbstractString; id::Symbol = Symbol(package),
        environment::AbstractString = pwd(), source = nothing, versions = :all,
        dev_sources::AbstractVector{<:AbstractString} = String[],
        release_pins::AbstractDict = Dict{VersionNumber, Vector{Any}}(),
        features::AbstractVector{FeatureSpec}, include_dev::Bool = true,
        candidates::AbstractVector{SuiteCandidate} = SuiteCandidate[])
    selection = if versions isa Symbol
        versions in (:all, :latest) ||
            throw(ArgumentError("package versions must be :all, :latest, or a vector"))
        versions
    elseif versions isa AbstractVector{VersionNumber}
        sort!(unique!(collect(versions)))
    else
        throw(ArgumentError("package versions must be :all, :latest, or a vector"))
    end
    env = abspath(String(environment))
    isdir(env) || throw(ArgumentError("suite environment does not exist: $env"))
    src = source === nothing ? nothing : abspath(String(source))
    src === nothing || isdir(src) ||
        throw(ArgumentError("package source does not exist: $src"))
    local_sources = abspath.(String.(dev_sources))
    all(isdir, local_sources) ||
        throw(ArgumentError("every development dependency must be a directory"))
    pins = Dict{VersionNumber, Vector{Any}}(
        VersionNumber(version) => Any[spec for spec in specs]
    for (version, specs) in pairs(release_pins))
    allunique(candidate.label for candidate in candidates) ||
        throw(ArgumentError("candidate labels must be unique within a package suite"))
    return PackageSuite(id, String(package), env, src, local_sources, pins,
        selection, collect(features), include_dev, collect(candidates))
end

"The measurable surface of one software, composed from package suites."
struct SoftwareSuite
    id::Symbol
    description::String
    packages::Vector{PackageSuite}
    comparisons::Vector{ComparisonPolicy}
end

function SoftwareSuite(id::Symbol, packages::AbstractVector{PackageSuite};
        description::AbstractString = "",
        comparisons::AbstractVector{ComparisonPolicy} = ComparisonPolicy[])
    isempty(packages) && throw(ArgumentError("software suite $id has no packages"))
    allunique(getfield.(packages, :id)) ||
        throw(ArgumentError("package-suite IDs must be unique"))
    allunique(policy.id for policy in comparisons) || throw(ArgumentError(
        "comparison policy ids must be unique within a software suite"))
    return SoftwareSuite(id, String(description), collect(packages), collect(comparisons))
end

struct SuiteTarget
    label::String
    version::SuiteVersion
    compatibility_version::VersionNumber
    kind::Symbol
    source::Union{Nothing, String}
    revision::Union{Nothing, String}
    dependencies::Vector{Any}
end

struct PlannedFeatureRun
    suite::Symbol
    package_suite::PackageSuite
    feature::FeatureSpec
    target::SuiteTarget
    variant::Union{Nothing, FeatureVariant}
    comparison_key::String
    planned_status::Symbol
    reason::String
end

workload_id(run::PlannedFeatureRun) = workload_id(run.feature)

struct SuitePlan
    suite::SoftwareSuite
    profile::Symbol
    runs::Vector{PlannedFeatureRun}
    comparisons::Vector{ComparisonPolicy}
end

function planned_run_id(run::PlannedFeatureRun)
    identity = (run.suite, run.package_suite.id, run.feature.id,
        run.target.label, run.comparison_key)
    return _content_digest(identity)[1:20]
end

function _project_version(package::PackageSuite)
    candidates = String[]
    package.source === nothing ||
        push!(candidates, joinpath(package.source, "Project.toml"))
    push!(candidates, joinpath(package.environment, "Project.toml"))
    for project in candidates
        isfile(project) || continue
        data = parse(read(project, String))
        haskey(data, "version") && return VersionNumber(data["version"])
    end
    throw(ArgumentError("cannot determine current version for $(package.package)"))
end

function _declared_versions(package::PackageSuite, version_provider)
    versions = if package.versions === :all || package.versions === :latest
        sort!(unique!(VersionNumber.(version_provider(package.package))))
    else
        copy(package.versions)
    end
    package.versions === :latest && !isempty(versions) && return [last(versions)]
    return versions
end

function _representative_versions(versions::Vector{VersionNumber})
    groups = Dict{Tuple{Int, Int}, Vector{VersionNumber}}()
    for version in versions
        key = version.major == 0 ? (version.major, version.minor) : (version.major, -1)
        push!(get!(groups, key, VersionNumber[]), version)
    end
    selected = VersionNumber[]
    for group in values(groups)
        sort!(group)
        push!(selected, first(group))
        last(group) == first(group) || push!(selected, last(group))
    end
    return sort!(unique!(selected))
end

function suite_targets(package::PackageSuite, profile::Symbol;
        version_provider = get_pkg_versions,
        candidates::AbstractVector{SuiteCandidate} = SuiteCandidate[])
    profile in (:quick, :ci, :historical, :release) ||
        throw(ArgumentError("unknown suite profile $profile"))
    declared = profile === :quick && package.include_dev ? VersionNumber[] :
               _declared_versions(package, version_provider)
    releases = if profile === :quick
        package.include_dev ? VersionNumber[] :
        (isempty(declared) ? declared : [last(declared)])
    elseif profile === :ci
        _representative_versions(declared)
    else
        declared
    end
    targets = SuiteTarget[SuiteTarget(string(version), version, version, :release,
                              nothing, nothing, Any[])
                          for version in releases]
    if package.include_dev && profile !== :release
        current = _project_version(package)
        push!(targets,
            SuiteTarget("dev@$(current)", :dev, current, :dev,
                package.source, nothing, Any[]))
    end
    all_candidates = vcat(package.candidates, collect(candidates))
    if profile !== :release
        current = isempty(all_candidates) ? nothing : _project_version(package)
        for candidate in all_candidates
            source = something(candidate.source, package.source)
            source === nothing && throw(ArgumentError(
                "candidate $(candidate.label) for $(package.package) requires a source or URL"))
            compatibility = something(candidate.compatibility_version, current)
            push!(targets,
                SuiteTarget(candidate.label, candidate.revision,
                    compatibility, :candidate, source, candidate.revision,
                    copy(candidate.dependencies)))
        end
    end
    allunique(target.label for target in targets) || throw(ArgumentError(
        "release, development, and candidate target labels must be unique"))
    return targets
end

function _variant_for(feature::FeatureSpec, version::VersionNumber)
    supports(feature.julia_window, VERSION) || return nothing
    matches = [variant for variant in feature.variants if supports(variant.window, version)]
    length(matches) <= 1 || throw(ArgumentError(
        "feature $(feature.id) has overlapping variants for version $version"))
    return isempty(matches) ? nothing : only(matches)
end

function _feature_unavailable_reason(feature::FeatureSpec, target::SuiteTarget)
    window = feature.julia_window
    if !supports(window, VERSION)
        bounds = String[]
        window.since === nothing || push!(bounds, ">=$(window.since)")
        window.until === nothing || push!(bounds, "<=$(window.until)")
        VERSION in window.excluded && push!(bounds, "excluding $(VERSION)")
        requirement = isempty(bounds) ? "declared Julia compatibility" : join(bounds, ", ")
        return "feature requires Julia $requirement; controller uses $(VERSION)"
    end
    return "feature is not defined for package version $(target.label)"
end

"""
    plan_suite(suite; profile=:quick, candidates=Dict(), comparisons=[])

Resolve package releases, development sources, Git candidates, feature variants,
and comparison policies into an immutable `SuitePlan` without running workloads.
"""
function plan_suite(suite::SoftwareSuite; profile::Symbol = :quick,
        version_provider = get_pkg_versions,
        candidates::AbstractDict = Dict{String, Vector{SuiteCandidate}}(),
        comparisons::AbstractVector{ComparisonPolicy} = ComparisonPolicy[])
    planned = PlannedFeatureRun[]
    for package in suite.packages
        requested = get(candidates, package.package,
            get(candidates, string(package.id), SuiteCandidate[]))
        for target in suite_targets(package, profile; version_provider,
            candidates = SuiteCandidate[item for item in requested])
            for feature in package.features
                variant = _variant_for(feature, target.compatibility_version)
                if variant === nothing
                    push!(planned,
                        PlannedFeatureRun(suite.id, package, feature, target,
                            nothing, "", :unavailable,
                            _feature_unavailable_reason(feature, target)))
                else
                    key = isempty(variant.comparison_key) ? string(feature.id) :
                          variant.comparison_key
                    push!(planned,
                        PlannedFeatureRun(suite.id, package, feature, target,
                            variant, key, :ready, ""))
                end
            end
        end
    end
    policies = isempty(comparisons) ? suite.comparisons :
               vcat(suite.comparisons, collect(comparisons))
    allunique(policy.id for policy in policies) || throw(ArgumentError(
        "comparison policy ids must be unique after applying overrides"))
    return SuitePlan(suite, profile, planned, policies)
end

function suite_plan_dict(plan::SuitePlan)
    payload = Dict{String, Any}(
        "schema_version" => "perfchecker-suite-plan/1",
        "suite" => string(plan.suite.id),
        "description" => plan.suite.description,
        "profile" => string(plan.profile),
        "comparisons" => comparison_policy_dict.(plan.comparisons),
        "runs" => [Dict{String, Any}(
                       "id" => planned_run_id(run),
                       "package" => run.package_suite.package,
                       "package_id" => string(run.package_suite.id),
                       "feature" => string(run.feature.id),
                       "workload" => string(workload_id(run)),
                       "description" => run.feature.description,
                       "backend" => string(run.feature.backend),
                       "julia_compatibility" => Dict{String, Any}(
                           "since" => run.feature.julia_window.since === nothing ? nothing :
                                      string(run.feature.julia_window.since),
                           "until" => run.feature.julia_window.until === nothing ? nothing :
                                      string(run.feature.julia_window.until),
                           "excluded" => sort!(string.(collect(run.feature.julia_window.excluded)))),
                       "entrypoint" => run.variant === nothing ?
                                       first(run.feature.variants).entrypoint :
                                       (run.variant::FeatureVariant).entrypoint,
                       "version" => run.target.label,
                       "target_kind" => string(run.target.kind),
                       "target_source" => run.target.source,
                       "target_revision" => run.target.revision,
                       "comparison_key" => run.comparison_key,
                       "status" => string(run.planned_status),
                       "reason" => run.reason) for run in plan.runs])
    payload["plan_revision"] = _content_digest(payload)
    return payload
end

"Return a validated, explicitly ordered subset of a server-produced plan."
function select_suite_plan(plan::SuitePlan, run_ids::AbstractVector{<:AbstractString})
    requested = String.(run_ids)
    length(unique(requested)) == length(requested) ||
        throw(ArgumentError("selected run identifiers must be unique"))
    available = Dict(planned_run_id(run) => run for run in plan.runs)
    unknown = setdiff(requested, collect(keys(available)))
    isempty(unknown) || throw(ArgumentError(
        "unknown selected run identifiers: $(join(unknown, ", "))"))
    selected = PlannedFeatureRun[available[id] for id in requested]
    return SuitePlan(plan.suite, plan.profile, selected, plan.comparisons)
end

"Apply the ordered selection from a shared UI configuration."
function select_suite_plan(plan::SuitePlan, configuration::AbstractDict)
    get(configuration, "schema_version", nothing) == "perfchecker-ui-config/1" ||
        throw(ArgumentError("unsupported UI configuration schema"))
    selection = get(configuration, "selection", nothing)
    selection isa AbstractDict || throw(ArgumentError(
        "UI configuration requires a selection object"))
    run_ids = get(selection, "run_ids", nothing)
    run_ids isa AbstractVector && all(id -> id isa AbstractString, run_ids) ||
        throw(ArgumentError("UI configuration selection requires string run_ids"))
    return select_suite_plan(plan, String.(run_ids))
end

struct FeatureRun
    planned::PlannedFeatureRun
    status::Symbol
    elapsed_seconds::Float64
    result::Any
    message::String
end

struct SoftwareSuiteResult
    plan::SuitePlan
    started_at::String
    finished_at::String
    runs::Vector{FeatureRun}
end

struct SuiteRunError <: Exception
    result::SoftwareSuiteResult
end

function Base.showerror(io::IO, error::SuiteRunError)
    failures = count(run -> run.status === :error, error.result.runs)
    print(io, "software suite $(error.result.plan.suite.id) had $failures failed run(s)")
end

mutable struct SuiteJob
    id::UUID
    plan::SuitePlan
    task::Task
    status::Base.RefValue{Symbol}
    result::Base.RefValue{Any}
    error::Base.RefValue{Any}
    progress::Base.RefValue{Dict{String, Any}}
    cancelled::Base.RefValue{Bool}
end

function _suite_progress(plan::SuitePlan, runs::Vector{FeatureRun};
        state::Symbol = :running, current = nothing)
    total = length(plan.runs)
    completed = length(runs)
    counts = Dict(status => count(run -> run.status === status, runs)
    for status in (:pass, :unavailable, :error))
    current_payload = current === nothing ? nothing :
                      Dict{String, Any}(
        "id" => planned_run_id(current),
        "package" => current.package_suite.package,
        "feature" => string(current.feature.id),
        "workload" => string(workload_id(current)),
        "backend" => string(current.feature.backend),
        "version" => current.target.label)
    return Dict{String, Any}(
        "schema_version" => "perfchecker-progress/1", "stage" => "measurement",
        "state" => string(state), "total" => total, "completed" => completed,
        "remaining" => max(total - completed, 0),
        "fraction" => total == 0 ? 1.0 : completed / total,
        "percent" => total == 0 ? 100.0 : 100 * completed / total,
        "passed" => counts[:pass], "unavailable" => counts[:unavailable],
        "failed" => counts[:error], "current_run" => current_payload)
end

function _notify_suite_progress(callback, payload)
    try
        callback(payload)
    catch error
        @warn "PerfChecker progress callback failed" exception=(error,
            catch_backtrace())
    end
    return payload
end

function _feature_blocks(planned::PlannedFeatureRun)
    entrypoint = (planned.variant::FeatureVariant).entrypoint
    state_name = Symbol("_perfchecker_feature_state_", planned_run_id(planned))
    setup = quote
        include($entrypoint)
        isdefined(Main, :perf_workload) ||
            error("feature entrypoint must define perf_workload(state)")
        const $state_name = isdefined(Main, :perf_setup) ? perf_setup() : nothing
    end
    workload = Expr(:call, :perf_workload, state_name)
    return setup, workload
end

function _run_config(planned::PlannedFeatureRun, overrides::AbstractDict)
    options = copy(planned.feature.options)
    merge!(options, (planned.variant::FeatureVariant).options)
    get!(options, :quiet, true)
    for (key, value) in pairs(overrides)
        key isa Symbol || throw(ArgumentError("suite override keys must be symbols"))
        options[key] = value
    end
    options[:path] = planned.package_suite.environment
    options[:tags] = unique!(vcat(
        normalize_symbols(get(options, :tags, Symbol[]), :tags),
        [planned.suite, planned.package_suite.id, planned.feature.id]))
    if planned.target.kind === :release
        version = planned.target.version::VersionNumber
        options[:pkgs] = (planned.package_suite.package, :custom, [version], true)
        pins = get(planned.package_suite.release_pins, version, Any[])
        if !isempty(pins)
            existing = get(options, :extra_pkgs, Any[])
            existing = existing isa AbstractVector ? collect(existing) : Any[existing]
            options[:extra_pkgs] = vcat(existing, pins)
        end
    elseif planned.target.kind === :dev
        source = planned.package_suite.source
        source === nothing && throw(ArgumentError(
            "dev target for $(planned.package_suite.package) requires a source path"))
        options[:devops] = PackageSpec(
            name = planned.package_suite.package, path = source)
        isempty(planned.package_suite.dev_sources) ||
            (options[:extra_devops] = [PackageSpec(path = path)
                                       for path in planned.package_suite.dev_sources])
        options[:include_current] = false
    elseif planned.target.kind === :candidate
        source = something(planned.target.source, planned.package_suite.source)
        source === nothing && throw(ArgumentError(
            "candidate target $(planned.target.label) requires a Git source"))
        options[:devops] = PackageSpec(name = planned.package_suite.package,
            url = source, rev = something(planned.target.revision, planned.target.label))
        options[:target_install] = :add
        isempty(planned.target.dependencies) || begin
            existing = get(options, :extra_pkgs, Any[])
            existing = existing isa AbstractVector ? collect(existing) : Any[existing]
            options[:extra_pkgs] = vcat(existing, planned.target.dependencies)
        end
        options[:include_current] = false
    else
        throw(ArgumentError("unsupported suite target kind $(planned.target.kind)"))
    end
    return PerfConfig(planned.feature.backend, options)
end

"Identity of the package graph prepared for one feature worker."
function _suite_environment_key(planned::PlannedFeatureRun, config::PerfConfig)
    options = config.options
    requirements = Dict{String, Any}(
        "package_suite" => string(planned.package_suite.id),
        "target" => planned.target.label,
        "path" => abspath(String(options[:path])),
        "packages" => repr(get(options, :pkgs, nothing)),
        "devops" => repr(get(options, :devops, nothing)),
        "extra_packages" => repr(get(options, :extra_pkgs, nothing)),
        "extra_devops" => repr(get(options, :extra_devops, nothing)),
        "target_install" => repr(get(options, :target_install, :develop)),
        "include_current" => Bool(get(options, :include_current, true)))
    return _content_digest(requirements)
end

function _unavailable_exception(error)
    error isa Pkg.Resolve.ResolverError && return true
    error isa Pkg.Types.PkgError || return false
    message = lowercase(sprint(showerror, error))
    return occursin("unsatisfiable requirements", message) ||
           occursin("not found", message) || occursin("expected package", message)
end

function _default_suite_executor(planned::PlannedFeatureRun, config, setup, workload)
    return check_function(config, setup, workload)
end

function _ensure_suite_backends(plan::SuitePlan)
    backends = Set(run.feature.backend
    for run in plan.runs
    if run.planned_status === :ready)
    for backend in backends
        try
            backend === :benchmark && Core.eval(Main, :(import BenchmarkTools))
            backend === :chairmark && Core.eval(Main, :(import Chairmarks))
        catch error
            throw(ArgumentError(
                "suite backend $backend must be installed in the controller environment: " *
                sprint(showerror, error)))
        end
    end
    return nothing
end

function _execute_suite_plan(plan::SuitePlan; executor = _default_suite_executor,
        overrides::AbstractDict = Dict{Symbol, Any}(),
        progress_callback = _ -> nothing)
    executor === _default_suite_executor && _ensure_suite_backends(plan)
    started = string(Dates.now(Dates.UTC))
    runs = FeatureRun[]
    prepared = Dict{String, String}()
    preparation_errors = Dict{String, Any}()
    preparation_roots = String[]
    _notify_suite_progress(progress_callback,
        _suite_progress(plan, runs; state = :running))
    try
        for planned in plan.runs
            _notify_suite_progress(progress_callback,
                _suite_progress(plan, runs; state = :running, current = planned))
            if planned.planned_status === :unavailable
                push!(runs,
                    FeatureRun(planned, :unavailable, 0.0, nothing, planned.reason))
                _notify_suite_progress(progress_callback,
                    _suite_progress(plan, runs; state = :running))
                continue
            end
            before = time()
            try
                config = _run_config(planned, overrides)
                if executor === _default_suite_executor
                    key = _suite_environment_key(planned, config)
                    haskey(preparation_errors, key) && throw(preparation_errors[key])
                    environment = get(prepared, key, nothing)
                    if environment === nothing
                        root, environment = try
                            _prepare_check_environment(config)
                        catch error
                            preparation_errors[key] = error
                            rethrow()
                        end
                        push!(preparation_roots, root)
                        prepared[key] = environment
                    end
                    config.options[:prepared_environment] = environment
                end
                setup, workload = _feature_blocks(planned)
                result = Base.invokelatest(executor, planned, config, setup, workload)
                push!(runs, FeatureRun(planned, :pass, time() - before, result, ""))
            catch error
                status = _unavailable_exception(error) ? :unavailable : :error
                message = sprint(showerror, error, catch_backtrace())
                push!(runs, FeatureRun(planned, status, time() - before, nothing, message))
            end
            _notify_suite_progress(progress_callback,
                _suite_progress(plan, runs; state = :running))
        end
    finally
        foreach(root -> rm(root; recursive = true, force = true), preparation_roots)
    end
    result = SoftwareSuiteResult(plan, started, string(Dates.now(Dates.UTC)), runs)
    final_state = suite_passed(result) ? :complete : :failed
    _notify_suite_progress(progress_callback,
        _suite_progress(plan, runs; state = final_state))
    return result
end

function launch_suite(plan::SuitePlan;
        overrides::AbstractDict = Dict{Symbol, Any}(), executor = _default_suite_executor,
        progress_callback = _ -> nothing)
    status = Ref(:queued)
    result = Ref{Any}(nothing)
    captured_error = Ref{Any}(nothing)
    progress = Ref(_suite_progress(plan, FeatureRun[]; state = :queued))
    cancelled = Ref(false)
    update_progress = payload -> begin
        progress[] = payload
        _notify_suite_progress(progress_callback, payload)
    end
    task = @async begin
        status[] = :running
        try
            result[] = _execute_suite_plan(plan; overrides, executor,
                progress_callback = update_progress)
            status[] = :complete
        catch error
            if cancelled[] || error isa InterruptException
                status[] = :cancelled
                progress[]["state"] = "cancelled"
            else
                captured_error[] = (error, catch_backtrace())
                status[] = :failed
                progress[]["state"] = "failed"
            end
        end
    end
    return SuiteJob(uuid4(), plan, task, status, result, captured_error, progress,
        cancelled)
end

function launch_suite(suite::SoftwareSuite; profile::Symbol = :quick,
        version_provider = get_pkg_versions, kwargs...)
    return launch_suite(plan_suite(suite; profile, version_provider); kwargs...)
end

suite_job_status(job::SuiteJob) = job.status[]
suite_job_progress(job::SuiteJob) = copy(job.progress[])

function cancel_suite!(job::SuiteJob)
    istaskdone(job.task) && return false
    job.cancelled[] = true
    job.status[] = :cancelling
    job.progress[]["state"] = "cancelling"
    schedule(job.task, InterruptException(); error = true)
    return true
end

function suite_job_dict(job::SuiteJob)
    payload = Dict{String, Any}(
        "schema_version" => "perfchecker-suite-job/1",
        "job_id" => string(job.id),
        "suite" => string(job.plan.suite.id),
        "profile" => string(job.plan.profile),
        "status" => string(suite_job_status(job)),
        "progress" => suite_job_progress(job))
    job.status[] === :complete && (payload["result"] = suite_dict(job.result[]))
    if job.status[] === :failed && job.error[] !== nothing
        error, _ = job.error[]
        payload["message"] = sprint(showerror, error)
    end
    return payload
end

function wait_suite(job::SuiteJob; strict::Bool = true)
    wait(job.task)
    if job.error[] !== nothing
        error, trace = job.error[]
        @debug "suite orchestration failure" exception=(error, trace)
        throw(error)
    end
    job.status[] === :cancelled && throw(InterruptException())
    result = job.result[]::SoftwareSuiteResult
    strict && !suite_passed(result) && throw(SuiteRunError(result))
    return result
end

"""
    run_suite(plan; executor=_default_suite_executor, strict=true,
              progress_callback=identity)

Execute the runnable leaves of a resolved suite plan and return their isolated
worker results. When `strict` is false, individual failures are retained in the
result instead of aborting the complete suite.
"""
function run_suite(plan::SuitePlan; executor = _default_suite_executor,
        overrides::AbstractDict = Dict{Symbol, Any}(), strict::Bool = true,
        progress_callback = _ -> nothing)
    result = _execute_suite_plan(plan; executor, overrides, progress_callback)
    strict && !suite_passed(result) && throw(SuiteRunError(result))
    return result
end

function run_suite(suite::SoftwareSuite; profile::Symbol = :quick,
        version_provider = get_pkg_versions, kwargs...)
    return run_suite(plan_suite(suite; profile, version_provider); kwargs...)
end

"""
    load_software_suite(path; factory=:build_suite) -> SoftwareSuite

Load an ordinary Julia suite definition in an isolated controller module. The
file must define the selected zero-argument factory or bind `suite` to a
`SoftwareSuite`.
Only the controller evaluates this file; measured Malt workers still load just
their backend, package, and feature entrypoint.
"""
function load_software_suite(path::AbstractString; factory::Symbol = :build_suite)
    definition = abspath(String(path))
    isfile(definition) ||
        throw(ArgumentError("suite definition does not exist: $definition"))
    owner = Module(gensym(:PerfCheckerSuiteDefinition), true, true)
    Core.eval(owner, :(eval(expression) = Core.eval($owner, expression)))
    Core.eval(owner, :(include(source) = Base.include($owner, source)))
    Base.include(owner, definition)
    value = if isdefined(owner, factory)
        factory_function = Base.invokelatest(getfield, owner, factory)
        Base.invokelatest(factory_function)
    elseif isdefined(owner, :suite)
        Base.invokelatest(getfield, owner, :suite)
    else
        throw(ArgumentError(
            "suite definition must define $(factory)() or a suite binding: $definition"))
    end
    value isa SoftwareSuite || throw(ArgumentError(
        "suite definition returned $(typeof(value)); expected SoftwareSuite"))
    return value
end

"""
    run_suite_file(path; profile=:quick, reports=nothing,
                   factory=:build_suite, kwargs...)

Load and execute a suite definition. When `reports` is a path, write the JSON,
Markdown, and JUnit representations consumed by CI and user interfaces.
"""
function run_suite_file(path::AbstractString; profile::Symbol = :quick,
        reports = nothing, factory::Symbol = :build_suite, kwargs...)
    result = run_suite(load_software_suite(path; factory); profile, kwargs...)
    reports === nothing || write_suite_reports(result, String(reports))
    return result
end

suite_passed(result::SoftwareSuiteResult) = !any(run -> run.status === :error, result.runs)

function suite_summary(result::SoftwareSuiteResult)
    return Table(
        suite = fill(string(result.plan.suite.id), length(result.runs)),
        package = [run.planned.package_suite.package for run in result.runs],
        feature = [string(run.planned.feature.id) for run in result.runs],
        version = [run.planned.target.label for run in result.runs],
        comparison_key = [run.planned.comparison_key for run in result.runs],
        status = [string(run.status) for run in result.runs],
        elapsed_seconds = [run.elapsed_seconds for run in result.runs],
        message = [run.message for run in result.runs])
end

function _first_summary_row(run::FeatureRun)
    run.result isa CheckerResult || return Dict{String, Any}()
    table = summary_table(run.result)
    isempty(table) && return Dict{String, Any}()
    return Dict{String, Any}(string(name) => (ismissing(getproperty(table, name)[1]) ?
                                              nothing :
                                              getproperty(table, name)[1])
    for name in propertynames(table))
end

function suite_dict(result::SoftwareSuiteResult)
    return Dict{String, Any}(
        "schema_version" => "perfchecker-suite-result/1",
        "suite" => string(result.plan.suite.id),
        "description" => result.plan.suite.description,
        "profile" => string(result.plan.profile),
        "started_at" => result.started_at,
        "finished_at" => result.finished_at,
        "passed" => suite_passed(result),
        "runs" => [Dict{String, Any}(
                       "package" => run.planned.package_suite.package,
                       "feature" => string(run.planned.feature.id),
                       "workload" => string(workload_id(run.planned)),
                       "version" => run.planned.target.label,
                       "target_kind" => string(run.planned.target.kind),
                       "comparison_key" => run.planned.comparison_key,
                       "status" => string(run.status),
                       "elapsed_seconds" => run.elapsed_seconds,
                       "message" => run.message,
                       "summary" => _first_summary_row(run)) for run in result.runs])
end

function write_suite_json(result::SoftwareSuiteResult, path::AbstractString)
    mkpath(dirname(path))
    open(path, "w") do io
        JSON.print(io, suite_dict(result), 2)
    end
    return String(path)
end

function write_suite_markdown(result::SoftwareSuiteResult, path::AbstractString)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "# PerfChecker suite: `$(result.plan.suite.id)`\n")
        println(io, "Profile: `$(result.plan.profile)`  ")
        println(io, "Status: **$(suite_passed(result) ? "PASS" : "FAIL")**\n")
        println(io, "| Package | Feature | Version | Comparable as | Status | Seconds |")
        println(io, "| --- | --- | --- | --- | --- | ---: |")
        for run in result.runs
            message = isempty(run.message) ? "" :
                      " — " * replace(first(split(run.message, '\n')), '|' => '/')
            println(io,
                "| $(run.planned.package_suite.package) | $(run.planned.feature.id) | " *
                "$(run.planned.target.label) | $(run.planned.comparison_key) | " *
                "$(run.status)$(message) | $(round(run.elapsed_seconds; digits = 3)) |")
        end
    end
    return String(path)
end

function _xml_escape(value)
    replace(string(value), '&' => "&amp;", '<' => "&lt;",
        '>' => "&gt;", '"' => "&quot;", '\'' => "&apos;")
end

function write_suite_junit(result::SoftwareSuiteResult, path::AbstractString)
    mkpath(dirname(path))
    failures = count(run -> run.status === :error, result.runs)
    skipped = count(run -> run.status === :unavailable, result.runs)
    total_time = sum(run.elapsed_seconds for run in result.runs)
    open(path, "w") do io
        println(io, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        println(io,
            "<testsuite name=\"$(_xml_escape(result.plan.suite.id))\" " *
            "tests=\"$(length(result.runs))\" failures=\"$failures\" " *
            "skipped=\"$skipped\" time=\"$total_time\">")
        for run in result.runs
            name = "$(run.planned.feature.id)[$(run.planned.target.label)]"
            println(io,
                "  <testcase classname=\"$(_xml_escape(run.planned.package_suite.package))\" " *
                "name=\"$(_xml_escape(name))\" time=\"$(run.elapsed_seconds)\">")
            run.status === :error && println(io,
                "    <failure message=\"performance check failed\">" *
                "$(_xml_escape(run.message))</failure>")
            run.status === :unavailable && println(io,
                "    <skipped message=\"$(_xml_escape(run.message))\" />")
            println(io, "  </testcase>")
        end
        println(io, "</testsuite>")
    end
    return String(path)
end

function write_suite_reports(result::SoftwareSuiteResult, directory::AbstractString;
        formats = (:json, :markdown, :junit, :bundle, :version_series,
            :version_comparison_json, :version_comparison_markdown),
        relative_limits::AbstractDict = Dict{String, Float64}(),
        min_samples::Integer = 1)
    mkpath(directory)
    paths = String[]
    :json in formats && push!(paths,
        write_suite_json(result, joinpath(directory, "suite-result.json")))
    :markdown in formats && push!(paths,
        write_suite_markdown(result, joinpath(directory, "suite-report.md")))
    :junit in formats && push!(paths,
        write_suite_junit(result, joinpath(directory, "suite-junit.xml")))
    protocol_formats = (:bundle, :version_series, :version_comparison_json,
        :version_comparison_markdown)
    bundle = any(format -> format in formats, protocol_formats) ?
             _suite_run_bundle(result) : nothing
    if :bundle in formats
        bundle_path = joinpath(abspath(String(directory)), "bundles",
            "run-$(bundle.manifest["run_id"])")
        push!(paths, write_run_bundle(bundle, bundle_path))
    end
    if any(format -> format in formats,
        (:version_series, :version_comparison_json,
            :version_comparison_markdown))
        comparison = compare_suite_versions(bundle; relative_limits, min_samples)
        :version_series in formats && push!(paths,
            write_version_series_json(comparison,
                joinpath(directory, "version-series.json")))
        :version_comparison_json in formats && push!(paths,
            write_version_comparison_json(comparison,
                joinpath(directory, "version-comparison.json")))
        :version_comparison_markdown in formats && push!(paths,
            write_version_comparison_markdown(comparison,
                joinpath(directory, "version-comparison.md")))
    end
    return paths
end

function drwatson_parameters end
function drwatson_savename end
function drwatson_produce_or_load end
function register_oxygen_routes! end
function serve_suite end
function studio_token_authenticator end
function run_studio_agent end
function launch_pluto_dashboard end
function suite_dashboard end
