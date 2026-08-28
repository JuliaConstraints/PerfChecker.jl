const _STUDIO_ASSET_ROOT = joinpath(@__DIR__, "assets")
const _STUDIO_PROFILES = Set([:quick, :ci, :historical, :release])
const _STUDIO_OVERRIDE_RULES = Dict{String, Tuple{DataType, Float64, Float64}}(
    "samples" => (Int, 1, 1_000_000),
    "evals" => (Int, 1, 1_000_000),
    "threads" => (Int, 1, max(Sys.CPU_THREADS, 1)),
    "seconds" => (Float64, 0.001, 3_600.0),
)

function _studio_asset_version()
    payload = read(joinpath(_STUDIO_ASSET_ROOT, "perfchecker-studio.css"), String) *
              read(joinpath(_STUDIO_ASSET_ROOT, "perfchecker-studio.js"), String)
    return bytes2hex(PerfChecker.SHA.sha1(payload))[1:12]
end

function _html_escape(value)
    return replace(string(value), '&' => "&amp;", '<' => "&lt;", '>' => "&gt;",
        '"' => "&quot;", '\'' => "&#39;")
end

function _studio_html(prefix::String; writable::Bool, auth_required::Bool = false)
    base = _html_escape(rstrip(prefix, '/'))
    mode = writable ? "workspace" : "results"
    configure_hidden = writable ? "" : " hidden"
    asset_version = _studio_asset_version()
    return """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>PerfChecker Studio</title><link rel="stylesheet" href="$base/assets/perfchecker-studio.css?v=$asset_version"></head>
<body data-api-base="$base" data-mode="$mode" data-auth-required="$(auth_required)">
<header class="product-header"><a class="brand" href="$base/" aria-label="PerfChecker home"><span aria-hidden="true">◆</span><strong>PerfChecker</strong></a><div><strong>Performance Studio</strong><small>Isolated, versioned evidence</small></div><span id="current-user" class="worker-badge">Malt workers</span></header>
<nav class="workspace-nav" aria-label="Studio views"><button type="button" data-view-target="configure"$configure_hidden>Configure</button><button type="button" data-view-target="jobs"$configure_hidden>Jobs</button><button type="button" data-view-target="results">Results</button></nav>
<main>
<section class="view" data-view="configure"$configure_hidden><header class="section-heading"><div><p class="eyebrow">Run plan</p><h1>Build a comparison matrix</h1><p>Select versions and features, reorder them, then launch isolated workers.</p></div><label>Profile<select id="profile"><option value="quick">Quick · dev</option><option value="ci">CI · representative history</option><option value="historical">Historical · every release</option><option value="release">Releases only</option></select></label></header>
<div class="config-grid"><aside class="panel settings"><h2>Execution</h2><label>Worker<select id="execution-target"><option value="local">This server</option><option value="agent:any">Any remote agent</option></select></label><h2>Measurement</h2><label>Samples<input id="samples" type="number" min="1" value="20"></label><label>Seconds<input id="seconds" type="number" min="0.001" step="0.05" value="0.2"></label><label>Evaluations<input id="evals" type="number" min="1" value="1"></label><label>Threads<input id="threads" type="number" min="1" value="1"></label><h2>Regression limits</h2><label>Wall time %<input id="limit-time" type="number" min="0" step="1" value="10"></label><label>Allocation bytes %<input id="limit-bytes" type="number" min="0" step="1" value="5"></label></aside>
<div class="matrix"><div class="matrix-toolbar"><label>Filter<input id="plan-filter" type="search" placeholder="Package, feature or version"></label><button type="button" id="select-all">Select all</button><button type="button" id="clear-selection">Clear</button><span id="plan-summary" class="muted"></span></div><div class="drop-grid"><section class="panel drop-zone" data-zone="available" aria-labelledby="available-title"><h2 id="available-title">Available</h2><div id="available-runs" class="run-list"></div></section><section class="panel drop-zone selected-zone" data-zone="selected" aria-labelledby="selected-title"><h2 id="selected-title">Execution order</h2><p class="muted">Drag cards here or use their buttons. Every case starts a fresh worker.</p><ol id="selected-runs" class="run-list sortable"></ol></section></div><footer class="launch-bar"><p id="plan-revision" class="muted"></p><button type="button" id="launch-job" class="primary">Launch selected runs</button></footer></div></div></section>
<section class="view" data-view="jobs" hidden><header class="section-heading"><div><p class="eyebrow">Controller</p><h1>Jobs</h1><p>Queued, running and persisted runs.</p></div></header><div id="jobs" class="card-grid"></div></section>
<section class="view" data-view="results" hidden><header class="section-heading"><div><p class="eyebrow">Evidence</p><h1>Version comparisons</h1><p>Adjacent releases and development versus the latest release.</p></div><button type="button" id="refresh-results">Refresh</button></header><div class="results-layout"><aside class="panel"><h2>Runs</h2><div id="results" class="result-list"></div></aside><section class="panel result-detail"><div id="result-summary" class="empty-state">Select a completed run.</div><label id="series-picker-label" hidden>Series<select id="series-picker"></select></label><div id="series-chart" class="chart" role="img" aria-label="Version performance chart"></div><div id="comparison-table"></div></section></div></section>
</main><dialog id="login-dialog"><form method="dialog" id="login-form"><p class="eyebrow">Hosted Studio</p><h2>Sign in</h2><p>Enter a personal access token issued by the PerfChecker service or its identity provider.</p><label>Access token<input id="access-token" type="password" autocomplete="current-password" required></label><div class="dialog-actions"><button type="submit" class="primary">Sign in</button></div><p id="login-error" class="error" role="alert"></p></form></dialog><div id="announcer" class="visually-hidden" aria-live="polite"></div><div id="toast" role="status" hidden></div>
<script src="$base/assets/perfchecker-studio.js?v=$asset_version" defer></script></body></html>"""
end

function _studio_response(prefix::String; writable::Bool, auth_required::Bool = false)
    policy = "default-src 'self'; script-src 'self'; style-src 'self'; " *
             "img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'"
    return Oxygen.html(_studio_html(prefix; writable, auth_required);
        headers = ["Content-Security-Policy" => policy,
            "X-Content-Type-Options" => "nosniff"])
end

"Build a bearer-token authenticator from SHA-256 token digests."
function PerfChecker.studio_token_authenticator(users::AbstractDict)
    normalized = Dict{String, Any}(lowercase(String(digest)) => identity
        for (digest, identity) in pairs(users))
    return function(token::AbstractString)
        candidate = bytes2hex(PerfChecker.SHA.sha256(String(token)))
        return get(normalized, candidate, nothing)
    end
end

function _studio_auth_middleware(authenticator)
    return function(handler)
        return function(request)
            header = HTTP.header(request, "Authorization", "")
            prefix = "Bearer "
            startswith(header, prefix) || return Oxygen.json(
                Dict("error" => "authentication required"); status = 401,
                headers = ["WWW-Authenticate" => "Bearer"])
            token = strip(chop(header; head = length(prefix), tail = 0))
            identity = try
                authenticator(token)
            catch
                nothing
            end
            identity === nothing && return Oxygen.json(
                Dict("error" => "invalid access token"); status = 401,
                headers = ["WWW-Authenticate" => "Bearer"])
            request.context[:perfchecker_identity] = identity
            return handler(request)
        end
    end
end

function _default_studio_authorizer(identity, action::Symbol)
    identity isa AbstractDict || return false
    roles = Set(String.(get(identity, "roles", get(identity, :roles, String[]))))
    "admin" in roles && return true
    action in (:view, :launch) && "runner" in roles && return true
    action in (:view, :agent) && "agent" in roles && return true
    return action === :view && !isempty(roles)
end

function _authorize(workspace, request, action::Symbol)
    identity = get(request.context, :perfchecker_identity,
        Dict("id" => "local", "roles" => ["admin"]))
    workspace.authorizer(identity, action) && return nothing
    return Oxygen.json(Dict("error" => "permission denied", "action" => string(action));
        status = 403)
end

function _register_studio_assets!(api)
    Oxygen.get(api("/assets/perfchecker-studio.css")) do
        Oxygen.css(read(joinpath(_STUDIO_ASSET_ROOT, "perfchecker-studio.css"), String);
            headers = ["Cache-Control" => "public, max-age=300"])
    end
    Oxygen.get(api("/assets/perfchecker-studio.js")) do
        Oxygen.js(read(joinpath(_STUDIO_ASSET_ROOT, "perfchecker-studio.js"), String);
            headers = ["Cache-Control" => "public, max-age=300"])
    end
end

mutable struct StudioJobEntry
    id::String
    plan::PerfChecker.SuitePlan
    plan_revision::String
    overrides::Dict{Symbol, Any}
    relative_limits::Dict{String, Float64}
    min_samples::Int
    execution_target::String
    claimed_by::String
    state::Symbol
    created_at::String
    started_at::String
    finished_at::String
    report_directory::String
    message::String
    suite_job::Union{Nothing, PerfChecker.SuiteJob}
end

mutable struct StudioWorkspace
    suite::PerfChecker.SoftwareSuite
    default_profile::Symbol
    version_provider::Any
    base_overrides::Dict{Symbol, Any}
    executor::Any
    reports_root::String
    max_concurrent::Int
    authorizer::Any
    jobs::Dict{String, StudioJobEntry}
    agents::Dict{String, Dict{String, Any}}
    pending::Vector{String}
    running::Set{String}
    lock::ReentrantLock
end

function _job_dict(entry::StudioJobEntry)
    progress = entry.suite_job === nothing ? nothing :
               PerfChecker.suite_job_status(entry.suite_job)
    return Dict{String, Any}(
        "schema_version" => "perfchecker-studio-job/1", "job_id" => entry.id,
        "state" => string(entry.state),
        "worker_state" => progress === nothing ? nothing : string(progress),
        "profile" => string(entry.plan.profile), "plan_revision" => entry.plan_revision,
        "execution_target" => entry.execution_target,
        "claimed_by" => isempty(entry.claimed_by) ? nothing : entry.claimed_by,
        "selected_run_ids" => PerfChecker.planned_run_id.(entry.plan.runs),
        "run_count" => length(entry.plan.runs), "created_at" => entry.created_at,
        "started_at" => entry.started_at, "finished_at" => entry.finished_at,
        "reports_ready" => !isempty(entry.report_directory),
        "message" => entry.message)
end

function _finish_job!(workspace::StudioWorkspace, entry::StudioJobEntry)
    try
        result = PerfChecker.wait_suite(entry.suite_job; strict = false)
        entry.state = :writing
        reports = joinpath(workspace.reports_root, "jobs", entry.id)
        PerfChecker.write_suite_reports(result, reports;
            relative_limits = entry.relative_limits, min_samples = entry.min_samples)
        entry.report_directory = reports
        entry.state = PerfChecker.suite_passed(result) ? :complete : :failed
        entry.message = PerfChecker.suite_passed(result) ? "" : "one or more feature runs failed"
    catch error
        entry.state = :failed
        entry.message = first(sprint(showerror, error), 1_000)
    finally
        entry.finished_at = string(Dates.now(Dates.UTC))
        lock(workspace.lock) do
            delete!(workspace.running, entry.id)
            _drain_workspace!(workspace)
        end
    end
end

function _drain_workspace!(workspace::StudioWorkspace)
    while length(workspace.running) < workspace.max_concurrent && !isempty(workspace.pending)
        id = popfirst!(workspace.pending)
        entry = workspace.jobs[id]
        entry.state = :running
        entry.started_at = string(Dates.now(Dates.UTC))
        push!(workspace.running, id)
        entry.suite_job = PerfChecker.launch_suite(entry.plan;
            overrides = entry.overrides, executor = workspace.executor)
        @async _finish_job!(workspace, entry)
    end
    return workspace
end

function _request_payload(request)
    isempty(request.body) && throw(ArgumentError("JSON request body is required"))
    payload = JSON.parse(String(request.body))
    payload isa AbstractDict || throw(ArgumentError("request body must be an object"))
    return payload
end

function _profile(value)
    profile = Symbol(String(value))
    profile in _STUDIO_PROFILES || throw(ArgumentError("unknown suite profile $profile"))
    return profile
end

function _validated_overrides(payload)
    payload isa AbstractDict || throw(ArgumentError("overrides must be an object"))
    result = Dict{Symbol, Any}()
    for (key, value) in pairs(payload)
        name = String(key)
        haskey(_STUDIO_OVERRIDE_RULES, name) || throw(ArgumentError("override $name is not allowed"))
        type, minimum, maximum = _STUDIO_OVERRIDE_RULES[name]
        value isa Real || throw(ArgumentError("override $name must be numeric"))
        normalized = type === Int ? Int(value) : Float64(value)
        minimum <= normalized <= maximum || throw(ArgumentError("override $name is outside its allowed range"))
        result[Symbol(name)] = normalized
    end
    return result
end

function _validated_limits(payload)
    payload isa AbstractDict || throw(ArgumentError("relative_limits must be an object"))
    result = Dict{String, Float64}()
    for (metric, value) in pairs(payload)
        value isa Real && 0 <= value <= 10 || throw(ArgumentError("relative limit for $metric must be between 0 and 10"))
        result[String(metric)] = Float64(value)
    end
    return result
end

function _bundle_payload(payload)
    payload isa AbstractDict || throw(ArgumentError("bundle must be an object"))
    manifest = Dict{String, Any}(String(key) => value
        for (key, value) in pairs(get(payload, "manifest", Dict())))
    get(manifest, "schema_version", nothing) == PerfChecker.RUN_BUNDLE_SCHEMA ||
        throw(ArgumentError("unsupported or missing run bundle schema"))
    records(name) = Dict{String, Any}[Dict{String, Any}(
        String(key) => value for (key, value) in pairs(item))
        for item in get(payload, name, Any[])]
    return PerfChecker.RunBundle(manifest, records("measurement_definitions"),
        records("observations"), records("diagnostics"), records("artifacts"))
end

function _persist_agent_bundle!(workspace, entry, bundle)
    reports = joinpath(workspace.reports_root, "jobs", entry.id)
    bundle_dir = joinpath(reports, "bundles", "run-$(bundle.manifest["run_id"])")
    PerfChecker.write_run_bundle(bundle, bundle_dir)
    comparison = PerfChecker.compare_suite_versions(bundle;
        relative_limits = entry.relative_limits, min_samples = entry.min_samples)
    PerfChecker.write_version_series_json(comparison,
        joinpath(reports, "version-series.json"))
    PerfChecker.write_version_comparison_json(comparison,
        joinpath(reports, "version-comparison.json"))
    PerfChecker.write_version_comparison_markdown(comparison,
        joinpath(reports, "version-comparison.md"))
    entry.report_directory = reports
    entry.state = PerfChecker.bundle_passed(bundle) ? :complete : :failed
    entry.message = PerfChecker.bundle_passed(bundle) ? "" : "remote bundle reports failure"
    entry.finished_at = string(Dates.now(Dates.UTC))
    return entry
end

function _agent_id(payload)
    id = strip(String(get(payload, "agent_id", "")))
    isempty(id) && throw(ArgumentError("agent_id is required"))
    occursin(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$", id) ||
        throw(ArgumentError("agent_id has an invalid format"))
    return id
end

function _register_suite_workspace!(suite::PerfChecker.SoftwareSuite;
        profile::Symbol, prefix::String, version_provider, overrides,
        executor, reports_root::String, max_concurrent::Int, authenticator, authorizer)
    profile in _STUDIO_PROFILES || throw(ArgumentError("unknown suite profile $profile"))
    max_concurrent > 0 || throw(ArgumentError("max_concurrent must be positive"))
    mkpath(reports_root)
    workspace = StudioWorkspace(suite, profile, version_provider,
        Dict{Symbol, Any}(Symbol(key) => value for (key, value) in pairs(overrides)),
        executor, reports_root, max_concurrent, authorizer,
        Dict{String, StudioJobEntry}(), Dict{String, Dict{String, Any}}(),
        String[], Set{String}(), ReentrantLock())
    api = Oxygen.router(prefix; tags = ["PerfChecker Studio"])
    protected = authenticator === nothing ? api : Oxygen.router(prefix;
        tags = ["PerfChecker Studio"],
        middleware = [_studio_auth_middleware(authenticator)])
    _register_studio_assets!(api)
    Oxygen.get(api("/")) do
        _studio_response(prefix; writable = true,
            auth_required = authenticator !== nothing)
    end
    Oxygen.get(protected("/capabilities")) do
        Oxygen.json(Dict("schema_version" => "perfchecker-capabilities/1",
            "read_only" => false, "runner" => "Malt", "max_concurrent" => max_concurrent,
            "profiles" => string.(sort!(collect(_STUDIO_PROFILES))),
            "resources" => ["suite-plan", "jobs", "agents", "results", "version-comparison"]))
    end
    Oxygen.get(protected("/me")) do request
        identity = get(request.context, :perfchecker_identity,
            Dict("id" => "local", "name" => "Local user", "roles" => ["admin"]))
        Oxygen.json(Dict("schema_version" => "perfchecker-identity/1",
            "identity" => identity))
    end
    Oxygen.get(protected("/suite-plan")) do request
        denied = _authorize(workspace, request, :view)
        denied === nothing || return denied
        requested = get(Oxygen.queryparams(request), "profile", string(profile))
        selected_profile = try _profile(requested) catch error
            return Oxygen.json(Dict("error" => sprint(showerror, error)); status = 400)
        end
        plan = PerfChecker.plan_suite(suite; profile = selected_profile, version_provider)
        Oxygen.json(PerfChecker.suite_plan_dict(plan))
    end
    Oxygen.post(protected("/jobs")) do request
        denied = _authorize(workspace, request, :launch)
        denied === nothing || return denied
        try
            payload = _request_payload(request)
            selected_profile = _profile(get(payload, "profile", string(profile)))
            full_plan = PerfChecker.plan_suite(suite; profile = selected_profile, version_provider)
            plan_payload = PerfChecker.suite_plan_dict(full_plan)
            revision = String(get(payload, "plan_revision", ""))
            revision == plan_payload["plan_revision"] || return Oxygen.json(
                Dict("error" => "suite plan is stale", "plan_revision" => plan_payload["plan_revision"]); status = 409)
            selected_ids = get(payload, "selected_run_ids", Any[])
            selected_ids isa AbstractVector && !isempty(selected_ids) || throw(ArgumentError("selected_run_ids must be a non-empty array"))
            plan = PerfChecker.select_suite_plan(full_plan, String.(selected_ids))
            selected_revision = PerfChecker.suite_plan_dict(plan)["plan_revision"]
            request_overrides = _validated_overrides(get(payload, "overrides", Dict()))
            merged_overrides = merge(copy(workspace.base_overrides), request_overrides)
            limits = _validated_limits(get(payload, "relative_limits", Dict()))
            minimum = Int(get(payload, "min_samples", 1))
            minimum > 0 || throw(ArgumentError("min_samples must be positive"))
            execution_target = String(get(payload, "execution_target", "local"))
            (execution_target == "local" || startswith(execution_target, "agent:")) ||
                throw(ArgumentError("execution_target must be local or agent:<id>"))
            id = string(PerfChecker.uuid4())
            entry = StudioJobEntry(id, plan, selected_revision, merged_overrides, limits,
                minimum, execution_target, "",
                execution_target == "local" ? :queued : :waiting_agent,
                string(Dates.now(Dates.UTC)), "", "", "", "", nothing)
            lock(workspace.lock) do
                workspace.jobs[id] = entry
                if execution_target == "local"
                    push!(workspace.pending, id)
                    _drain_workspace!(workspace)
                end
            end
            return Oxygen.json(_job_dict(entry); status = 202)
        catch error
            return Oxygen.json(Dict("error" => first(sprint(showerror, error), 1_000)); status = 400)
        end
    end
    Oxygen.get(protected("/jobs")) do request
        denied = _authorize(workspace, request, :view)
        denied === nothing || return denied
        id = get(Oxygen.queryparams(request), "id", "")
        if isempty(id)
            entries = sort!(collect(values(workspace.jobs)); by = item -> item.created_at, rev = true)
            return Oxygen.json(_job_dict.(entries))
        end
        entry = get(workspace.jobs, id, nothing)
        entry === nothing && return Oxygen.json(Dict("error" => "unknown job"); status = 404)
        return Oxygen.json(_job_dict(entry))
    end
    Oxygen.get(protected("/agents")) do request
        denied = _authorize(workspace, request, :view)
        denied === nothing || return denied
        return Oxygen.json(sort!(collect(values(workspace.agents));
            by = item -> String(item["agent_id"])))
    end
    Oxygen.post(protected("/agents/claim")) do request
        denied = _authorize(workspace, request, :agent)
        denied === nothing || return denied
        try
            payload = _request_payload(request)
            id = _agent_id(payload)
            capabilities = get(payload, "capabilities", Dict{String, Any}())
            claimed = lock(workspace.lock) do
                workspace.agents[id] = Dict{String, Any}(
                    "agent_id" => id, "state" => "online",
                    "last_seen_at" => string(Dates.now(Dates.UTC)),
                    "capabilities" => capabilities)
                candidates = sort!([entry for entry in values(workspace.jobs)
                    if entry.state === :waiting_agent &&
                       entry.execution_target in ("agent:any", "agent:$id")];
                    by = entry -> entry.created_at)
                isempty(candidates) && return nothing
                entry = first(candidates)
                entry.state = :leased
                entry.claimed_by = id
                entry.started_at = string(Dates.now(Dates.UTC))
                return entry
            end
            claimed === nothing && return HTTP.Response(204)
            return Oxygen.json(Dict(
                "schema_version" => "perfchecker-agent-job/1",
                "job_id" => claimed.id, "plan" => PerfChecker.suite_plan_dict(claimed.plan),
                "overrides" => Dict(string(key) => value for
                    (key, value) in claimed.overrides),
                "relative_limits" => claimed.relative_limits,
                "min_samples" => claimed.min_samples))
        catch error
            return Oxygen.json(Dict("error" => first(sprint(showerror, error), 1_000));
                status = 400)
        end
    end
    Oxygen.post(protected("/agents/heartbeat")) do request
        denied = _authorize(workspace, request, :agent)
        denied === nothing || return denied
        try
            payload = _request_payload(request)
            id = _agent_id(payload)
            lock(workspace.lock) do
                agent = get!(workspace.agents, id, Dict{String, Any}("agent_id" => id))
                agent["state"] = "online"
                agent["last_seen_at"] = string(Dates.now(Dates.UTC))
            end
            return Oxygen.json(Dict("agent_id" => id, "accepted" => true))
        catch error
            return Oxygen.json(Dict("error" => first(sprint(showerror, error), 1_000));
                status = 400)
        end
    end
    Oxygen.post(protected("/agents/complete")) do request
        denied = _authorize(workspace, request, :agent)
        denied === nothing || return denied
        try
            payload = _request_payload(request)
            id = _agent_id(payload)
            job_id = String(get(payload, "job_id", ""))
            entry = get(workspace.jobs, job_id, nothing)
            entry === nothing && return Oxygen.json(Dict("error" => "unknown job"); status = 404)
            entry.state === :leased && entry.claimed_by == id || return Oxygen.json(
                Dict("error" => "job is not leased to this agent"); status = 409)
            bundle = _bundle_payload(get(payload, "bundle", Dict()))
            get(bundle.manifest, "suite", "") == string(workspace.suite.id) ||
                throw(ArgumentError("bundle suite does not match the job"))
            bundle_plan = get(bundle.manifest, "plan", Dict{String, Any}())
            get(bundle_plan, "plan_revision", "") == entry.plan_revision ||
                throw(ArgumentError("bundle plan revision does not match the job"))
            _persist_agent_bundle!(workspace, entry, bundle)
            return Oxygen.json(_job_dict(entry))
        catch error
            return Oxygen.json(Dict("error" => first(sprint(showerror, error), 1_000));
                status = 400)
        end
    end
    _register_result_routes!(protected, reports_root)
    return api
end

function _agent_request(server::String, path::String, token::String;
        method::String = "GET", payload = nothing, timeout::Real = 30)
    output = IOBuffer()
    headers = Pair{String, String}["Authorization" => "Bearer $token",
        "Accept" => "application/json"]
    input = nothing
    if payload !== nothing
        push!(headers, "Content-Type" => "application/json")
        input = IOBuffer(JSON.json(payload))
    end
    response = PerfChecker.Downloads.request("$(rstrip(server, '/'))/$path";
        method, headers, input, output, timeout, throw = false)
    response isa PerfChecker.Downloads.RequestError && throw(response)
    body = String(take!(output))
    response.status == 204 && return response.status, nothing
    parsed = isempty(body) ? Dict{String, Any}() : JSON.parse(body)
    200 <= response.status < 300 || throw(ErrorException(
        String(get(parsed, "error", "agent request failed with status $(response.status)"))))
    return response.status, parsed
end

"Poll a hosted Studio and execute leased jobs with this machine's isolated runner."
function PerfChecker.run_studio_agent(suite::PerfChecker.SoftwareSuite;
        server::AbstractString, token::AbstractString, agent_id::AbstractString,
        version_provider = PerfChecker.get_pkg_versions,
        executor = PerfChecker._default_suite_executor,
        poll_seconds::Real = 2, max_jobs::Integer = typemax(Int), once::Bool = false)
    poll_seconds >= 0 || throw(ArgumentError("poll_seconds must be non-negative"))
    max_jobs > 0 || throw(ArgumentError("max_jobs must be positive"))
    completed = 0
    capabilities = Dict("runtime" => "julia", "julia_version" => string(VERSION),
        "os" => string(Sys.KERNEL), "architecture" => string(Sys.ARCH),
        "threads" => Threads.nthreads(), "runner" => "Malt")
    while completed < max_jobs
        _, claim = _agent_request(String(server), "agents/claim", String(token);
            method = "POST", payload = Dict("agent_id" => String(agent_id),
                "capabilities" => capabilities))
        if claim === nothing
            once && return completed
            sleep(poll_seconds)
            continue
        end
        remote_plan = claim["plan"]
        profile = _profile(remote_plan["profile"])
        full_plan = PerfChecker.plan_suite(suite; profile, version_provider)
        selected_ids = String[String(item["id"])
            for item in get(remote_plan, "runs", Any[])]
        selected = PerfChecker.select_suite_plan(full_plan, selected_ids)
        local_revision = PerfChecker.suite_plan_dict(selected)["plan_revision"]
        local_revision == remote_plan["plan_revision"] || throw(ArgumentError(
            "agent suite plan does not match server revision"))
        overrides = Dict{Symbol, Any}(Symbol(key) => value
            for (key, value) in pairs(get(claim, "overrides", Dict())))
        result = PerfChecker.run_suite(selected; overrides, executor, strict = false)
        bundle = PerfChecker._suite_run_bundle(result)
        _agent_request(String(server), "agents/complete", String(token);
            method = "POST", payload = Dict("agent_id" => String(agent_id),
                "job_id" => claim["job_id"],
                "bundle" => PerfChecker.bundle_dict(bundle)))
        completed += 1
        once && return completed
    end
    return completed
end
