const _STUDIO_ASSET_ROOT = joinpath(@__DIR__, "assets")
const _STUDIO_PROFILES = Set([:quick, :ci, :historical, :release])
const _STUDIO_OVERRIDE_RULES = Dict{String, Tuple{DataType, Float64, Float64}}(
    "samples" => (Int, 1, 1_000_000),
    "evals" => (Int, 1, 1_000_000),
    "threads" => (Int, 1, max(Sys.CPU_THREADS, 1)),
    "seconds" => (Float64, 0.001, 3_600.0)
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
<section class="view" data-view="configure"$configure_hidden><header class="section-heading"><div><p class="eyebrow">Run plan</p><h1>Build a comparison matrix</h1><p>Choose whole version ranges and feature groups, then launch isolated workers. Dragging is optional.</p></div><label>Profile<select id="profile"><option value="quick">Quick · dev</option><option value="ci">CI · representative history</option><option value="historical">Historical · every release</option><option value="release">Releases only</option></select></label></header>
<div class="config-grid"><aside class="panel settings"><h2>Execution</h2><label>Worker<select id="execution-target"><option value="local">This server</option><option value="agent:any">Any remote agent</option></select></label><h2>Measurement</h2><label>Samples<input id="samples" type="number" min="1" value="20"></label><label>Seconds<input id="seconds" type="number" min="0.001" step="0.05" value="0.2"></label><label>Evaluations<input id="evals" type="number" min="1" value="1"></label><label>Threads<input id="threads" type="number" min="1" value="1"></label><h2>Regression limits</h2><label>Wall time %<input id="limit-time" type="number" min="0" step="1" value="10"></label><label>Allocation bytes %<input id="limit-bytes" type="number" min="0" step="1" value="5"></label></aside>
<div class="matrix"><div class="selection-panel panel"><div class="range-grid"><label>Package<select id="package-filter"><option value="">All packages</option></select></label><label>Feature<select id="feature-filter"><option value="">All features</option></select></label><label>Backend<select id="backend-filter"><option value="">All backends</option></select></label><label>From version<select id="version-min"><option value="">First</option></select></label><label>To version<select id="version-max"><option value="">Last</option></select></label><label>Sort<select id="plan-sort"><option value="package-version">Package → version → feature</option><option value="version-package">Version → package → feature</option><option value="feature-version">Feature → version → package</option><option value="version-desc">Newest versions first</option><option value="custom">Manual order</option></select></label></div><div class="matrix-toolbar"><label>Search<input id="plan-filter" type="search" placeholder="Package, feature, backend or version"></label><label class="compact-toggle"><input id="show-unavailable" type="checkbox" checked>Unavailable</label><button type="button" id="add-visible">Add visible</button><button type="button" id="remove-visible">Remove visible</button><button type="button" id="invert-visible">Invert visible</button><button type="button" id="select-all">Add all</button><button type="button" id="clear-selection">Clear</button><span id="plan-summary" class="muted"></span></div><div id="active-filters" class="filter-chips" aria-live="polite"></div></div><div class="drop-grid"><section class="panel drop-zone" data-zone="available" aria-labelledby="available-title"><h2 id="available-title">Available in this range</h2><div id="available-runs" class="run-list"></div></section><section class="panel drop-zone selected-zone" data-zone="selected" aria-labelledby="selected-title"><h2 id="selected-title">Selected runs</h2><p class="muted">Use checkboxes or range actions. Dragging and Alt+arrow remain available for manual ordering. Every case starts a fresh worker.</p><ol id="selected-runs" class="run-list sortable"></ol></section></div><footer class="launch-bar"><p id="plan-revision" class="muted"></p><button type="button" id="launch-job" class="primary">Launch selected runs</button></footer></div></div></section>
<section class="view" data-view="jobs" hidden><header class="section-heading"><div><p class="eyebrow">Controller</p><h1>Jobs</h1><p>Queued, running and persisted runs.</p></div></header><div id="jobs" class="card-grid"></div></section>
<section class="view" data-view="results" hidden><header class="section-heading"><div><p class="eyebrow">Evidence</p><h1>Makie performance explorer</h1><p>Interactive trajectories, distributions, regressions and allocation profiles.</p></div><button type="button" id="refresh-results">Refresh</button></header><div class="results-layout"><aside class="panel result-browser"><h2>Runs</h2><div class="result-filters"><label>Search<input id="result-filter" type="search" placeholder="Suite, package, feature, version or run ID"></label><div class="result-filter-grid"><label>Suite<select id="result-suite-filter"><option value="">All suites</option></select></label><label>Profile<select id="result-profile-filter"><option value="">All profiles</option></select></label><label>State<select id="result-state-filter"><option value="">All states</option></select></label><label>Sort<select id="result-sort"><option value="newest">Newest first</option><option value="oldest">Oldest first</option><option value="suite">Suite</option><option value="profile">Profile</option><option value="state">State</option></select></label></div><div class="result-filter-footer"><span id="result-count" class="muted" aria-live="polite"></span><button type="button" id="clear-result-filters">Clear filters</button></div></div><div id="results" class="result-list"></div></aside><section class="panel result-detail"><div id="result-summary" class="empty-state">Select a completed run.</div><div class="plot-controls"><label>Plot search<input id="plot-filter" type="search" placeholder="Package, feature, metric or plot"></label><label>Package<select id="plot-package-filter"><option value="">All packages</option></select></label><label>Feature<select id="plot-feature-filter"><option value="">All features</option></select></label><label>Metric<select id="plot-metric-filter"><option value="">All metrics</option></select></label><label>View<select id="plot-kind-filter"><option value="">All views</option></select></label><label id="plot-picker-label" hidden>Plot<select id="plot-picker"></select></label><label id="plot-version-label" hidden>Version<select id="plot-version"></select></label><button type="button" id="clear-plot-filters">Clear plot filters</button><span id="plot-count" class="muted" aria-live="polite"></span></div><iframe id="makie-frame" class="makie-frame" title="Interactive Makie performance plot" loading="lazy" sandbox="allow-scripts" hidden></iframe><div id="series-chart" class="chart" role="img" aria-label="Version performance chart" hidden></div><div id="comparison-table"></div></section></div></section>
</main><dialog id="login-dialog"><form method="dialog" id="login-form"><p class="eyebrow">Hosted Studio</p><h2>Sign in</h2><p>Enter a personal access token issued by the PerfChecker service or its identity provider.</p><label>Access token<input id="access-token" type="password" autocomplete="current-password" required></label><div class="dialog-actions"><button type="submit" class="primary">Sign in</button></div><p id="login-error" class="error" role="alert"></p></form></dialog><div id="announcer" class="visually-hidden" aria-live="polite"></div><div id="toast" role="status" hidden></div>
<script src="$base/assets/perfchecker-studio.js?v=$asset_version" defer></script></body></html>"""
end

function _studio_response(prefix::String; writable::Bool, auth_required::Bool = false)
    policy = "default-src 'self'; script-src 'self'; style-src 'self'; " *
             "img-src 'self' data:; connect-src 'self'; frame-src 'self'; " *
             "object-src 'none'; base-uri 'none'"
    return Oxygen.html(_studio_html(prefix; writable, auth_required);
        headers = ["Content-Security-Policy" => policy,
            "X-Content-Type-Options" => "nosniff"])
end

"Build a bearer-token authenticator from SHA-256 token digests."
function PerfChecker.studio_token_authenticator(users::AbstractDict)
    normalized = Dict{String, Any}(lowercase(String(digest)) => identity
    for (digest, identity) in pairs(users))
    return function (token::AbstractString)
        candidate = bytes2hex(PerfChecker.SHA.sha256(String(token)))
        return get(normalized, candidate, nothing)
    end
end

function PerfChecker.studio_token_authenticator(path::AbstractString)
    source = abspath(String(path))
    isfile(source) || throw(ArgumentError("Studio user store does not exist: $source"))
    payload = TOML.parsefile(source)
    users = get(payload, "users", Any[])
    users isa AbstractVector ||
        throw(ArgumentError("Studio user store requires [[users]] entries"))
    identities = Dict{String, Any}()
    for user in users
        id = strip(String(get(user, "id", "")))
        digest = lowercase(strip(String(get(user, "token_sha256", ""))))
        isempty(id) && throw(ArgumentError("every Studio user requires an id"))
        occursin(r"^[0-9a-f]{64}$", digest) || throw(ArgumentError(
            "Studio user $id requires a 64-character token_sha256 digest"))
        roles = String.(get(user, "roles", String[]))
        isempty(roles) && throw(ArgumentError("Studio user $id requires at least one role"))
        identity = Dict{String, Any}("id" => id,
            "name" => String(get(user, "name", id)), "roles" => roles)
        haskey(user, "agent_ids") &&
            (identity["agent_ids"] = String.(user["agent_ids"]))
        identities[digest] = identity
    end
    isempty(identities) && throw(ArgumentError("Studio user store is empty"))
    return PerfChecker.studio_token_authenticator(identities)
end

function _cookie_value(request, name::AbstractString)
    header = HTTP.header(request, "Cookie", "")
    for part in split(header, ';')
        fields = split(strip(part), '='; limit = 2)
        length(fields) == 2 && fields[1] == name && return fields[2]
    end
    return ""
end

function _studio_auth_middleware(authenticator, sessions, session_lock)
    return function (handler)
        return function (request)
            header = HTTP.header(request, "Authorization", "")
            prefix = "Bearer "
            session_id = ""
            csrf = ""
            identity = if startswith(header, prefix)
                token = strip(chop(header; head = length(prefix), tail = 0))
                try
                    authenticator(token)
                catch
                    nothing
                end
            else
                session_id = _cookie_value(request, "perfchecker_session")
                lock(session_lock) do
                    session = get(sessions, session_id, nothing)
                    session === nothing && return nothing
                    expires = get(session, "expires_at", Dates.DateTime(0))
                    if expires <= Dates.now(Dates.UTC)
                        delete!(sessions, session_id)
                        return nothing
                    end
                    csrf = String(get(session, "csrf", ""))
                    return get(session, "identity", nothing)
                end
            end
            identity === nothing && return Oxygen.json(
                Dict("error" => "authentication required"); status = 401,
                headers = ["WWW-Authenticate" => "Bearer"])
            if !isempty(session_id) && String(request.method) ∉ ("GET", "HEAD", "OPTIONS")
                supplied = HTTP.header(request, "X-CSRF-Token", "")
                isempty(csrf) || supplied == csrf ||
                    return Oxygen.json(
                        Dict("error" => "invalid CSRF token"); status = 403)
            end
            request.context[:perfchecker_identity] = identity
            request.context[:perfchecker_session_id] = session_id
            request.context[:perfchecker_csrf] = csrf
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
    lease_token_digest::String
    lease_until::String
    attempts::Int
    created_by::String
    state::Symbol
    created_at::String
    started_at::String
    finished_at::String
    report_directory::String
    message::String
    progress::Dict{String, Any}
    suite_job::Union{Nothing, PerfChecker.SuiteJob}
end

mutable struct StudioWorkspace
    suite::PerfChecker.SoftwareSuite
    default_profile::Symbol
    version_provider::Any
    base_overrides::Dict{Symbol, Any}
    executor::Any
    reports_root::String
    state_path::String
    max_concurrent::Int
    lease_seconds::Int
    max_agent_attempts::Int
    session_hours::Int
    secure_cookies::Bool
    authorizer::Any
    jobs::Dict{String, StudioJobEntry}
    agents::Dict{String, Dict{String, Any}}
    sessions::Dict{String, Dict{String, Any}}
    pending::Vector{String}
    running::Set{String}
    lock::ReentrantLock
end

function _identity_id(identity)
    identity isa AbstractDict || return "anonymous"
    return String(get(identity, "id", get(identity, :id, "anonymous")))
end

function _atomic_json(path::String, payload)
    temporary = "$path.tmp-$(PerfChecker.uuid4())"
    open(temporary, "w") do io
        JSON.print(io, payload, 2)
    end
    mv(temporary, path; force = true)
    return path
end

function _job_state_dict(entry::StudioJobEntry)
    return Dict{String, Any}(
        "job_id" => entry.id, "profile" => string(entry.plan.profile),
        "selected_run_ids" => PerfChecker.planned_run_id.(entry.plan.runs),
        "plan_revision" => entry.plan_revision,
        "overrides" => Dict(string(key) => value for (key, value) in entry.overrides),
        "relative_limits" => entry.relative_limits, "min_samples" => entry.min_samples,
        "execution_target" => entry.execution_target, "claimed_by" => entry.claimed_by,
        "lease_token_digest" => entry.lease_token_digest,
        "lease_until" => entry.lease_until, "attempts" => entry.attempts,
        "created_by" => entry.created_by, "state" => string(entry.state),
        "created_at" => entry.created_at, "started_at" => entry.started_at,
        "finished_at" => entry.finished_at,
        "report_directory" => entry.report_directory, "message" => entry.message,
        "progress" => entry.progress)
end

function _persist_workspace!(workspace::StudioWorkspace)
    sessions = Dict{String, Any}()
    for (id, session) in workspace.sessions
        sessions[id] = Dict("identity" => session["identity"],
            "expires_at" => string(session["expires_at"]),
            "csrf" => get(session, "csrf", ""))
    end
    payload = Dict("schema_version" => "perfchecker-studio-state/1",
        "saved_at" => string(Dates.now(Dates.UTC)),
        "jobs" => [_job_state_dict(entry) for entry in values(workspace.jobs)],
        "agents" => workspace.agents, "sessions" => sessions)
    return _atomic_json(workspace.state_path, payload)
end

function _restore_workspace!(workspace::StudioWorkspace)
    isfile(workspace.state_path) || return workspace
    payload = JSON.parsefile(workspace.state_path; use_mmap = false)
    get(payload, "schema_version", "") == "perfchecker-studio-state/1" ||
        throw(ArgumentError("unsupported PerfChecker Studio state file"))
    now = Dates.now(Dates.UTC)
    for (id, session) in pairs(get(payload, "sessions", Dict()))
        expires = try
            Dates.DateTime(String(session["expires_at"]))
        catch
            now
        end
        expires > now || continue
        workspace.sessions[String(id)] = Dict{String, Any}(
            "identity" => session["identity"], "expires_at" => expires,
            "csrf" => String(get(session, "csrf", "")))
    end
    for (id, agent) in pairs(get(payload, "agents", Dict()))
        workspace.agents[String(id)] = Dict{String, Any}(
            String(key) => value for (key, value) in pairs(agent))
        workspace.agents[String(id)]["state"] = "offline"
    end
    for record in get(payload, "jobs", Any[])
        try
            profile = _profile(record["profile"])
            full_plan = PerfChecker.plan_suite(workspace.suite; profile,
                version_provider = workspace.version_provider)
            plan = PerfChecker.select_suite_plan(full_plan,
                String.(record["selected_run_ids"]))
            revision = PerfChecker.suite_plan_dict(plan)["plan_revision"]
            revision == String(record["plan_revision"]) || continue
            state = Symbol(record["state"])
            if state in (:running, :writing, :queued)
                state = :queued
            elseif state === :leased
                state = :waiting_agent
            end
            entry = StudioJobEntry(String(record["job_id"]), plan, revision,
                Dict{Symbol, Any}(Symbol(key) => value
                for
                (key, value) in pairs(get(record, "overrides", Dict()))),
                Dict{String, Float64}(String(key) => Float64(value)
                for
                (key, value) in pairs(get(record, "relative_limits", Dict()))),
                Int(get(record, "min_samples", 1)),
                String(get(record, "execution_target", "local")),
                state === :waiting_agent ? "" : String(get(record, "claimed_by", "")),
                "", "", Int(get(record, "attempts", 0)),
                String(get(record, "created_by", "unknown")), state,
                String(get(record, "created_at", "")),
                state in (:queued, :waiting_agent) ? "" :
                String(get(record, "started_at", "")),
                String(get(record, "finished_at", "")),
                String(get(record, "report_directory", "")),
                String(get(record, "message", "")),
                Dict{String, Any}(String(key) => value
                for (key, value) in pairs(
                    get(record, "progress", Dict{String, Any}()))), nothing)
            workspace.jobs[entry.id] = entry
            state === :queued && push!(workspace.pending, entry.id)
        catch error
            @warn "Skipping unrestorable PerfChecker Studio job" exception=(
                error, catch_backtrace())
        end
    end
    return workspace
end

function _job_dict(entry::StudioJobEntry)
    worker_state = entry.suite_job === nothing ? nothing :
                   PerfChecker.suite_job_status(entry.suite_job)
    progress = entry.suite_job === nothing ? entry.progress :
               PerfChecker.suite_job_progress(entry.suite_job)
    return Dict{String, Any}(
        "schema_version" => "perfchecker-studio-job/1", "job_id" => entry.id,
        "state" => string(entry.state),
        "worker_state" => worker_state === nothing ? nothing : string(worker_state),
        "progress" => progress,
        "profile" => string(entry.plan.profile), "plan_revision" => entry.plan_revision,
        "execution_target" => entry.execution_target,
        "claimed_by" => isempty(entry.claimed_by) ? nothing : entry.claimed_by,
        "lease_until" => isempty(entry.lease_until) ? nothing : entry.lease_until,
        "attempts" => entry.attempts, "created_by" => entry.created_by,
        "selected_run_ids" => PerfChecker.planned_run_id.(entry.plan.runs),
        "run_count" => length(entry.plan.runs), "created_at" => entry.created_at,
        "started_at" => entry.started_at, "finished_at" => entry.finished_at,
        "reports_ready" => !isempty(entry.report_directory),
        "message" => entry.message)
end

function _finish_job!(workspace::StudioWorkspace, entry::StudioJobEntry)
    try
        result = PerfChecker.wait_suite(entry.suite_job; strict = false)
        entry.state === :cancelled && return
        entry.state = :writing
        lock(workspace.lock) do
            _persist_workspace!(workspace)
        end
        reports = joinpath(workspace.reports_root, "jobs", entry.id)
        PerfChecker.write_suite_reports(result, reports;
            relative_limits = entry.relative_limits, min_samples = entry.min_samples)
        entry.report_directory = reports
        entry.state = PerfChecker.suite_passed(result) ? :complete : :failed
        entry.message = PerfChecker.suite_passed(result) ? "" :
                        "one or more feature runs failed"
    catch error
        if entry.state !== :cancelled
            entry.state = :failed
            entry.message = first(sprint(showerror, error), 1_000)
        end
    finally
        entry.finished_at = string(Dates.now(Dates.UTC))
        lock(workspace.lock) do
            delete!(workspace.running, entry.id)
            _drain_workspace!(workspace)
            _persist_workspace!(workspace)
        end
    end
end

function _drain_workspace!(workspace::StudioWorkspace)
    while length(workspace.running) < workspace.max_concurrent &&
          !isempty(workspace.pending)
        id = popfirst!(workspace.pending)
        entry = workspace.jobs[id]
        entry.state = :running
        entry.started_at = string(Dates.now(Dates.UTC))
        push!(workspace.running, id)
        progress_callback = progress -> begin
            entry.progress = progress
            get(progress, "current_run", nothing) === nothing &&
                lock(workspace.lock) do
                    _persist_workspace!(workspace)
                end
        end
        entry.suite_job = PerfChecker.launch_suite(entry.plan;
            overrides = entry.overrides, executor = workspace.executor,
            progress_callback)
        @async _finish_job!(workspace, entry)
    end
    _persist_workspace!(workspace)
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
        haskey(_STUDIO_OVERRIDE_RULES, name) ||
            throw(ArgumentError("override $name is not allowed"))
        type, minimum, maximum = _STUDIO_OVERRIDE_RULES[name]
        value isa Real || throw(ArgumentError("override $name must be numeric"))
        normalized = type === Int ? Int(value) : Float64(value)
        minimum <= normalized <= maximum ||
            throw(ArgumentError("override $name is outside its allowed range"))
        result[Symbol(name)] = normalized
    end
    return result
end

function _validated_limits(payload)
    payload isa AbstractDict || throw(ArgumentError("relative_limits must be an object"))
    result = Dict{String, Float64}()
    for (metric, value) in pairs(payload)
        value isa Real && 0 <= value <= 10 ||
            throw(ArgumentError("relative limit for $metric must be between 0 and 10"))
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
    function records(name)
        Dict{String, Any}[Dict{String, Any}(
                              String(key) => value
                          for (key, value) in pairs(item))
                          for item in get(payload, name, Any[])]
    end
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
    unavailable = Set{Tuple{String, String}}()
    failed = Set{Tuple{String, String}}()
    for diagnostic in bundle.diagnostics
        run_key = (String(get(diagnostic, "case_id", "")),
            String(get(diagnostic, "target_id", "")))
        all(isempty, run_key) && continue
        rule = String(get(diagnostic, "rule_id", ""))
        severity = String(get(diagnostic, "severity", ""))
        if rule == "feature.unavailable"
            push!(unavailable, run_key)
        elseif rule == "feature.failed" || severity == "error"
            push!(failed, run_key)
        end
    end
    total = length(entry.plan.runs)
    failed_count = length(failed)
    unavailable_count = length(unavailable)
    if entry.state === :failed && failed_count == 0
        failed_count = max(total - unavailable_count, 1)
    end
    passed_count = max(total - unavailable_count - failed_count, 0)
    entry.progress = Dict{String, Any}(
        "state" => string(entry.state), "total" => total, "completed" => total,
        "remaining" => 0, "fraction" => 1.0, "percent" => 100.0,
        "passed" => passed_count, "unavailable" => unavailable_count,
        "failed" => failed_count, "current_run" => nothing)
    return entry
end

function _agent_id(payload)
    id = String(strip(String(get(payload, "agent_id", ""))))
    isempty(id) && throw(ArgumentError("agent_id is required"))
    occursin(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$", id) ||
        throw(ArgumentError("agent_id has an invalid format"))
    return id
end

function _agent_identity_allowed(request, id::String)
    identity = get(request.context, :perfchecker_identity, Dict{String, Any}())
    roles = Set(String.(get(identity, "roles", get(identity, :roles, String[]))))
    "admin" in roles && return true
    identity_id = _identity_id(identity)
    allowed = String.(get(identity, "agent_ids", get(identity, :agent_ids,
        [identity_id])))
    return id in allowed
end

function _expire_agent_leases!(workspace::StudioWorkspace)
    now = Dates.now(Dates.UTC)
    for entry in values(workspace.jobs)
        entry.state === :leased || continue
        expires = try
            Dates.DateTime(entry.lease_until)
        catch
            now
        end
        expires > now && continue
        entry.claimed_by = ""
        entry.lease_token_digest = ""
        entry.lease_until = ""
        if entry.attempts >= workspace.max_agent_attempts
            entry.state = :failed
            entry.finished_at = string(now)
            entry.message = "remote agent lease expired after $(entry.attempts) attempts"
        else
            entry.state = :waiting_agent
            entry.message = "remote agent lease expired; waiting for retry"
        end
    end
    return workspace
end

function _register_suite_workspace!(suite::PerfChecker.SoftwareSuite;
        profile::Symbol, prefix::String, version_provider, overrides,
        executor, reports_root::String, max_concurrent::Int, authenticator, authorizer,
        lease_seconds::Int, max_agent_attempts::Int, session_hours::Int,
        secure_cookies::Bool)
    profile in _STUDIO_PROFILES || throw(ArgumentError("unknown suite profile $profile"))
    max_concurrent > 0 || throw(ArgumentError("max_concurrent must be positive"))
    lease_seconds > 0 || throw(ArgumentError("lease_seconds must be positive"))
    max_agent_attempts > 0 || throw(ArgumentError("max_agent_attempts must be positive"))
    session_hours > 0 || throw(ArgumentError("session_hours must be positive"))
    mkpath(reports_root)
    workspace = StudioWorkspace(suite, profile, version_provider,
        Dict{Symbol, Any}(Symbol(key) => value for (key, value) in pairs(overrides)),
        executor, reports_root, joinpath(reports_root, "studio-state.json"),
        max_concurrent, lease_seconds, max_agent_attempts, session_hours,
        secure_cookies, authorizer,
        Dict{String, StudioJobEntry}(), Dict{String, Dict{String, Any}}(),
        Dict{String, Dict{String, Any}}(), String[], Set{String}(), ReentrantLock())
    lock(workspace.lock) do
        _restore_workspace!(workspace)
        _drain_workspace!(workspace)
        _persist_workspace!(workspace)
    end
    api = Oxygen.router(prefix; tags = ["PerfChecker Studio"])
    protected = authenticator === nothing ? api :
                Oxygen.router(prefix;
        tags = ["PerfChecker Studio"],
        middleware = [_studio_auth_middleware(authenticator, workspace.sessions,
            workspace.lock)])
    _register_studio_assets!(api)
    Oxygen.get(api("/")) do
        _studio_response(prefix; writable = true,
            auth_required = authenticator !== nothing)
    end
    Oxygen.get(protected("/capabilities")) do
        Oxygen.json(Dict("schema_version" => "perfchecker-capabilities/1",
            "read_only" => false, "runner" => "Malt", "max_concurrent" => max_concurrent,
            "profiles" => string.(sort!(collect(_STUDIO_PROFILES))),
            "network" => Dict(
                "interface" => PerfChecker.network_interface_capabilities(),
                "isolation" =>
                    PerfChecker.network_isolation_capabilities(; probe = true)),
            "resources" => ["suite-plan", "jobs", "agents", "results",
                "version-comparison", "plots"]))
    end
    Oxygen.get(protected("/me")) do request
        identity = get(request.context, :perfchecker_identity,
            Dict("id" => "local", "name" => "Local user", "roles" => ["admin"]))
        Oxygen.json(Dict("schema_version" => "perfchecker-identity/1",
            "identity" => identity))
    end
    Oxygen.post(protected("/session")) do request
        identity = get(request.context, :perfchecker_identity, nothing)
        identity === nothing &&
            return Oxygen.json(Dict("error" => "authentication required");
                status = 401)
        session_id = bytes2hex(PerfChecker.SHA.sha256(
            "$(PerfChecker.uuid4())-$(PerfChecker.uuid4())-$(time_ns())"))
        expires = Dates.now(Dates.UTC) + Dates.Hour(workspace.session_hours)
        csrf = bytes2hex(PerfChecker.SHA.sha256(
            "csrf-$(PerfChecker.uuid4())-$(time_ns())"))
        lock(workspace.lock) do
            workspace.sessions[session_id] = Dict{String, Any}(
                "identity" => identity, "expires_at" => expires, "csrf" => csrf)
            _persist_workspace!(workspace)
        end
        secure = workspace.secure_cookies ? "; Secure" : ""
        Oxygen.json(
            Dict("schema_version" => "perfchecker-session/1",
                "expires_at" => string(expires), "csrf_token" => csrf);
            headers = ["Set-Cookie" => "perfchecker_session=$session_id; HttpOnly; SameSite=Strict$secure; Path=$(prefix); Max-Age=$(workspace.session_hours * 3600)"])
    end
    Oxygen.get(protected("/session")) do request
        csrf = String(get(request.context, :perfchecker_csrf, ""))
        isempty(csrf) && return Oxygen.json(Dict("error" => "no active browser session");
            status = 404)
        Oxygen.json(Dict("schema_version" => "perfchecker-session/1",
            "csrf_token" => csrf))
    end
    Oxygen.delete(protected("/session")) do request
        session_id = String(get(request.context, :perfchecker_session_id, ""))
        lock(workspace.lock) do
            isempty(session_id) || delete!(workspace.sessions, session_id)
            _persist_workspace!(workspace)
        end
        Oxygen.json(Dict("signed_out" => true);
            headers = ["Set-Cookie" => "perfchecker_session=; HttpOnly; SameSite=Strict; Path=$(prefix); Max-Age=0"])
    end
    Oxygen.get(protected("/suite-plan")) do request
        denied = _authorize(workspace, request, :view)
        denied === nothing || return denied
        requested = get(Oxygen.queryparams(request), "profile", string(profile))
        selected_profile = try
            _profile(requested)
        catch error
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
            full_plan = PerfChecker.plan_suite(
                suite; profile = selected_profile, version_provider)
            plan_payload = PerfChecker.suite_plan_dict(full_plan)
            revision = String(get(payload, "plan_revision", ""))
            revision == plan_payload["plan_revision"] || return Oxygen.json(
                Dict("error" => "suite plan is stale",
                    "plan_revision" => plan_payload["plan_revision"]); status = 409)
            selected_ids = get(payload, "selected_run_ids", Any[])
            selected_ids isa AbstractVector && !isempty(selected_ids) ||
                throw(ArgumentError("selected_run_ids must be a non-empty array"))
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
            identity = get(request.context, :perfchecker_identity,
                Dict("id" => "local"))
            entry = StudioJobEntry(id, plan, selected_revision, merged_overrides, limits,
                minimum, execution_target, "", "", "", 0, _identity_id(identity),
                execution_target == "local" ? :queued : :waiting_agent,
                string(Dates.now(Dates.UTC)), "", "", "", "",
                PerfChecker._suite_progress(plan, PerfChecker.FeatureRun[];
                    state = execution_target == "local" ? :queued : :waiting_agent),
                nothing)
            lock(workspace.lock) do
                workspace.jobs[id] = entry
                if execution_target == "local"
                    push!(workspace.pending, id)
                    _drain_workspace!(workspace)
                end
                _persist_workspace!(workspace)
            end
            return Oxygen.json(_job_dict(entry); status = 202)
        catch error
            return Oxygen.json(
                Dict("error" => first(sprint(showerror, error), 1_000)); status = 400)
        end
    end
    Oxygen.get(protected("/jobs")) do request
        denied = _authorize(workspace, request, :view)
        denied === nothing || return denied
        id = get(Oxygen.queryparams(request), "id", "")
        if isempty(id)
            entries = sort!(
                collect(values(workspace.jobs)); by = item -> item.created_at, rev = true)
            return Oxygen.json(_job_dict.(entries))
        end
        entry = get(workspace.jobs, id, nothing)
        entry === nothing &&
            return Oxygen.json(Dict("error" => "unknown job"); status = 404)
        return Oxygen.json(_job_dict(entry))
    end
    Oxygen.post(protected("/jobs/cancel")) do request
        denied = _authorize(workspace, request, :launch)
        denied === nothing || return denied
        try
            payload = _request_payload(request)
            id = String(get(payload, "job_id", ""))
            entry = get(workspace.jobs, id, nothing)
            entry === nothing && return Oxygen.json(Dict("error" => "unknown job");
                status = 404)
            result = lock(workspace.lock) do
                entry.state in (:complete, :failed, :cancelled) && return false
                filter!(candidate -> candidate != id, workspace.pending)
                entry.state = :cancelled
                entry.finished_at = string(Dates.now(Dates.UTC))
                entry.message = "cancelled by $(_identity_id(get(request.context,
                    :perfchecker_identity, Dict())))"
                entry.suite_job === nothing || PerfChecker.cancel_suite!(entry.suite_job)
                _persist_workspace!(workspace)
                return true
            end
            return Oxygen.json(merge(_job_dict(entry), Dict("cancelled" => result)))
        catch error
            return Oxygen.json(Dict("error" => first(sprint(showerror, error), 1_000));
                status = 400)
        end
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
            _agent_identity_allowed(request, id) || return Oxygen.json(
                Dict("error" => "agent identity is not allowed to claim as $id"); status = 403)
            capabilities = get(payload, "capabilities", Dict{String, Any}())
            claimed = lock(workspace.lock) do
                _expire_agent_leases!(workspace)
                workspace.agents[id] = Dict{String, Any}(
                    "agent_id" => id, "state" => "online",
                    "last_seen_at" => string(Dates.now(Dates.UTC)),
                    "capabilities" => capabilities)
                candidates = sort!(
                    [entry
                     for entry in values(workspace.jobs)
                     if entry.state === :waiting_agent &&
                        entry.execution_target in ("agent:any", "agent:$id")];
                    by = entry -> entry.created_at)
                if isempty(candidates)
                    _persist_workspace!(workspace)
                    return nothing
                end
                entry = first(candidates)
                lease_token = bytes2hex(PerfChecker.SHA.sha256(
                    "lease-$(PerfChecker.uuid4())-$(time_ns())"))
                entry.state = :leased
                entry.claimed_by = id
                entry.started_at = string(Dates.now(Dates.UTC))
                entry.attempts += 1
                entry.lease_until = string(Dates.now(Dates.UTC) +
                                           Dates.Second(workspace.lease_seconds))
                entry.lease_token_digest = bytes2hex(PerfChecker.SHA.sha256(lease_token))
                entry.message = ""
                _persist_workspace!(workspace)
                return (entry, lease_token)
            end
            claimed === nothing && return HTTP.Response(204)
            claimed_entry, lease_token = claimed
            return Oxygen.json(Dict(
                "schema_version" => "perfchecker-agent-job/1",
                "job_id" => claimed_entry.id,
                "lease_token" => lease_token,
                "lease_until" => claimed_entry.lease_until,
                "plan" => PerfChecker.suite_plan_dict(claimed_entry.plan),
                "overrides" => Dict(string(key) => value
                for
                (key, value) in claimed_entry.overrides),
                "relative_limits" => claimed_entry.relative_limits,
                "min_samples" => claimed_entry.min_samples))
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
            _agent_identity_allowed(request, id) || return Oxygen.json(
                Dict("error" => "agent identity is not allowed to heartbeat as $id"); status = 403)
            lock(workspace.lock) do
                agent = get!(workspace.agents, id, Dict{String, Any}("agent_id" => id))
                agent["state"] = "online"
                agent["last_seen_at"] = string(Dates.now(Dates.UTC))
                for entry in values(workspace.jobs)
                    entry.state === :leased && entry.claimed_by == id || continue
                    entry.lease_until = string(Dates.now(Dates.UTC) +
                                               Dates.Second(workspace.lease_seconds))
                    progress = get(payload, "progress", nothing)
                    progress isa AbstractDict &&
                        (entry.progress = Dict{String, Any}(String(key) => value
                        for (key, value) in pairs(progress)))
                end
                _persist_workspace!(workspace)
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
            _agent_identity_allowed(request, id) || return Oxygen.json(
                Dict("error" => "agent identity is not allowed to complete as $id"); status = 403)
            job_id = String(get(payload, "job_id", ""))
            entry = get(workspace.jobs, job_id, nothing)
            entry === nothing &&
                return Oxygen.json(Dict("error" => "unknown job"); status = 404)
            entry.state === :leased && entry.claimed_by == id || return Oxygen.json(
                Dict("error" => "job is not leased to this agent"); status = 409)
            supplied_lease = String(get(payload, "lease_token", ""))
            supplied_digest = bytes2hex(PerfChecker.SHA.sha256(supplied_lease))
            !isempty(entry.lease_token_digest) &&
            supplied_digest == entry.lease_token_digest ||
                return Oxygen.json(Dict("error" => "invalid lease token"); status = 403)
            bundle = _bundle_payload(get(payload, "bundle", Dict()))
            get(bundle.manifest, "suite", "") == string(workspace.suite.id) ||
                throw(ArgumentError("bundle suite does not match the job"))
            bundle_plan = get(bundle.manifest, "plan", Dict{String, Any}())
            get(bundle_plan, "plan_revision", "") == entry.plan_revision ||
                throw(ArgumentError("bundle plan revision does not match the job"))
            _persist_agent_bundle!(workspace, entry, bundle)
            lock(workspace.lock) do
                entry.lease_token_digest = ""
                entry.lease_until = ""
                _persist_workspace!(workspace)
            end
            return Oxygen.json(_job_dict(entry))
        catch error
            return Oxygen.json(Dict("error" => first(sprint(showerror, error), 1_000));
                status = 400)
        end
    end
    Oxygen.post(protected("/agents/fail")) do request
        denied = _authorize(workspace, request, :agent)
        denied === nothing || return denied
        try
            payload = _request_payload(request)
            id = _agent_id(payload)
            _agent_identity_allowed(request, id) || return Oxygen.json(
                Dict("error" => "agent identity is not allowed to fail as $id"); status = 403)
            job_id = String(get(payload, "job_id", ""))
            entry = get(workspace.jobs, job_id, nothing)
            entry === nothing && return Oxygen.json(Dict("error" => "unknown job");
                status = 404)
            supplied_digest = bytes2hex(PerfChecker.SHA.sha256(
                String(get(payload, "lease_token", ""))))
            response = lock(workspace.lock) do
                entry.state === :leased && entry.claimed_by == id || return nothing
                supplied_digest == entry.lease_token_digest || return nothing
                entry.claimed_by = ""
                entry.lease_token_digest = ""
                entry.lease_until = ""
                entry.message = first(
                    String(get(payload, "message", "remote agent failed")),
                    1_000)
                if entry.attempts >= workspace.max_agent_attempts
                    entry.state = :failed
                    entry.finished_at = string(Dates.now(Dates.UTC))
                else
                    entry.state = :waiting_agent
                end
                _persist_workspace!(workspace)
                return _job_dict(entry)
            end
            response === nothing && return Oxygen.json(
                Dict("error" => "invalid lease"); status = 409)
            return Oxygen.json(response)
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
    lower_server = lowercase(server)
    if startswith(lower_server, "http://") &&
       !any(host -> startswith(lower_server, "http://$host"),
        ("127.0.0.1", "localhost", "[::1]"))
        throw(ArgumentError("remote PerfChecker agents require HTTPS"))
    end
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
        String(get(
        parsed, "error", "agent request failed with status $(response.status)"))))
    return response.status, parsed
end

"Poll a hosted Studio and execute leased jobs with this machine's isolated runner."
function PerfChecker.run_studio_agent(suite::PerfChecker.SoftwareSuite;
        server::AbstractString, token::AbstractString, agent_id::AbstractString,
        version_provider = PerfChecker.get_pkg_versions,
        executor = PerfChecker._default_suite_executor,
        poll_seconds::Real = 2, heartbeat_seconds::Real = 30,
        max_jobs::Integer = typemax(Int), once::Bool = false)
    poll_seconds >= 0 || throw(ArgumentError("poll_seconds must be non-negative"))
    max_jobs > 0 || throw(ArgumentError("max_jobs must be positive"))
    heartbeat_seconds > 0 || throw(ArgumentError("heartbeat_seconds must be positive"))
    completed = 0
    capabilities = Dict("runtime" => "julia", "julia_version" => string(VERSION),
        "os" => string(Sys.KERNEL), "architecture" => string(Sys.ARCH),
        "threads" => Threads.nthreads(), "runner" => "Malt",
        "network" => Dict(
            "interface" => PerfChecker.network_interface_capabilities(),
            "isolation" => PerfChecker.network_isolation_capabilities(; probe = true)))
    while completed < max_jobs
        _, claim = _agent_request(String(server), "agents/claim", String(token);
            method = "POST", payload = Dict("agent_id" => String(agent_id),
                "capabilities" => capabilities))
        if claim === nothing
            once && return completed
            sleep(poll_seconds)
            continue
        end
        lease_token = String(claim["lease_token"])
        heartbeat_done = Ref(false)
        latest_progress = Ref{Any}(nothing)
        @async begin
            while !heartbeat_done[]
                sleep(heartbeat_seconds)
                heartbeat_done[] && break
                try
                    _agent_request(String(server), "agents/heartbeat", String(token);
                        method = "POST", payload = Dict("agent_id" => String(agent_id),
                            "job_id" => String(claim["job_id"]),
                            "progress" => latest_progress[]))
                catch error
                    @warn "PerfChecker agent heartbeat failed" exception=(
                        error, catch_backtrace())
                end
            end
        end
        try
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
            result = PerfChecker.run_suite(selected; overrides, executor, strict = false,
                progress_callback = progress -> (latest_progress[] = progress))
            bundle = PerfChecker._suite_run_bundle(result)
            _agent_request(String(server), "agents/complete", String(token);
                method = "POST", payload = Dict("agent_id" => String(agent_id),
                    "job_id" => claim["job_id"], "lease_token" => lease_token,
                    "bundle" => PerfChecker.bundle_dict(bundle)))
        catch error
            try
                _agent_request(String(server), "agents/fail", String(token);
                    method = "POST", payload = Dict("agent_id" => String(agent_id),
                        "job_id" => claim["job_id"], "lease_token" => lease_token,
                        "message" => first(sprint(showerror, error), 1_000)))
            catch report_error
                @warn "PerfChecker agent could not report failure" exception=(
                    report_error, catch_backtrace())
            end
            once && rethrow()
        finally
            heartbeat_done[] = true
        end
        completed += 1
        once && return completed
    end
    return completed
end
