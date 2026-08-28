module OxygenExt

using Oxygen
using PerfChecker
using JSON

function _bundle_store_html(prefix::String)
    endpoint = JSON.json(rstrip(prefix, '/'))
    return """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>PerfChecker runs</title>
  <style>
    :root{font:16px system-ui,sans-serif;color:#172033;background:#f5f7fb}
    body{margin:0}header{padding:2rem clamp(1rem,5vw,4rem);background:#172033;color:white}
    main{display:grid;grid-template-columns:minmax(16rem,24rem) 1fr;gap:1rem;padding:1rem}
    section{background:white;border:1px solid #dce2ec;border-radius:.75rem;padding:1rem}
    button{width:100%;text-align:left;margin:.35rem 0;padding:.75rem;border:1px solid #dce2ec;
      border-radius:.5rem;background:white;cursor:pointer}button:hover{border-color:#536dfe}
    .pass{color:#08783e}.fail{color:#b42318}.muted{color:#667085}table{border-collapse:collapse;width:100%}
    th,td{padding:.55rem;border-bottom:1px solid #eaecf0;text-align:left}code{font-size:.85em}
    @media(max-width:800px){main{grid-template-columns:1fr}}
  </style>
</head>
<body>
  <header><h1>PerfChecker</h1><p>Portable performance evidence</p></header>
  <main><section><h2>Runs</h2><div id="runs">Loading…</div></section>
  <section><h2 id="title">Select a run</h2><div id="details" class="muted">No run selected.</div></section></main>
  <script>
    const base=$endpoint;
    const escapeHtml=value=>String(value).replace(/[&<>\"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;'}[c]));
    async function loadRuns(){
      const runs=await fetch(base+'/runs').then(r=>r.json());
      document.querySelector('#runs').innerHTML=runs.length?runs.map(run=>
        '<button onclick="loadRun(\''+encodeURIComponent(run.run_id)+'\')"><strong>'+escapeHtml(run.suite)+'</strong><br>'+
        '<span class="'+(run.state==='complete'?'pass':'fail')+'">'+escapeHtml(run.state)+'</span> · '+
        '<span class="muted">'+escapeHtml(run.runtime?.language||'unknown')+' '+escapeHtml(run.runtime?.version||'')+'</span></button>'
      ).join(''):'<p class="muted">No bundle found.</p>';
    }
    async function loadRun(id){
      const bundle=await fetch(base+'/runs?id='+id).then(r=>r.json());
      const manifest=bundle.manifest, observations=bundle.observations||[], diagnostics=bundle.diagnostics||[];
      document.querySelector('#title').textContent=manifest.suite+' · '+manifest.run_id;
      const counts={};for(const item of observations)counts[item.metric]=(counts[item.metric]||0)+1;
      document.querySelector('#details').innerHTML='<p><strong class="'+(bundle.passed?'pass':'fail')+'">'+(bundle.passed?'PASS':'FAIL')+'</strong>'+
        ' · '+observations.length+' observations · '+diagnostics.length+' diagnostics</p>'+
        '<table><thead><tr><th>Metric</th><th>Samples</th></tr></thead><tbody>'+
        Object.entries(counts).sort().map(([metric,count])=>'<tr><td><code>'+escapeHtml(metric)+'</code></td><td>'+count+'</td></tr>').join('')+
        '</tbody></table>';
    }
    loadRuns().catch(error=>document.querySelector('#runs').textContent=error.message);
  </script>
</body>
</html>
"""
end

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

function PerfChecker.register_oxygen_routes!(bundle::PerfChecker.RunBundle;
        prefix::AbstractString = "/perfchecker/v1")
    api = Oxygen.router(String(prefix); tags = ["PerfChecker bundles"])

    Oxygen.get(api("/capabilities")) do
        return Oxygen.json(Dict(
            "schema_version" => "perfchecker-capabilities/1",
            "read_only" => true,
            "resources" => ["manifest", "measurement-definitions", "observations",
                "diagnostics", "artifacts"]))
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
    return api
end

function PerfChecker.register_oxygen_routes!(root::AbstractString;
        prefix::AbstractString = "/perfchecker/v1", allow_ingest::Bool = false)
    store = abspath(String(root))
    allow_ingest ? mkpath(store) :
        isdir(store) || throw(ArgumentError("bundle store does not exist: $store"))
    api = Oxygen.router(String(prefix); tags = ["PerfChecker bundle store"])

    Oxygen.get(api("/")) do
        return Oxygen.html(_bundle_store_html(String(prefix)))
    end

    Oxygen.get(api("/capabilities")) do
        return Oxygen.json(Dict(
            "schema_version" => "perfchecker-capabilities/1",
            "read_only" => !allow_ingest,
            "resources" => allow_ingest ? ["runs", "ingest"] : ["runs"],
            "protocol" => "perfchecker-run-bundle/1"))
    end
    Oxygen.get(api("/runs")) do request
        id = get(Oxygen.queryparams(request), "id", "")
        manifests = PerfChecker.list_run_bundles(store)
        if isempty(id)
            public_manifests = [Dict(key => value for (key, value) in pairs(manifest)
                                     if key != "bundle_path") for manifest in manifests]
            return Oxygen.json(public_manifests)
        end
        manifest = findfirst(item -> get(item, "run_id", "") == id, manifests)
        manifest === nothing && return Oxygen.json(Dict("error" => "unknown run"))
        bundle = PerfChecker.read_run_bundle(manifests[manifest]["bundle_path"])
        return Oxygen.json(PerfChecker.bundle_dict(bundle))
    end
    if allow_ingest
        Oxygen.post(api("/ingest")) do request
            payload = JSON.parse(String(request.body))
            bundle = PerfChecker._provider_result(payload)
            destination = joinpath(store, "run-$(bundle.manifest["run_id"])")
            PerfChecker.write_run_bundle(bundle, destination)
            return Oxygen.json(PerfChecker.bundle_dict(bundle; include_records = false))
        end
    end
    return api
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
        async::Bool = false, prefix::AbstractString = "/perfchecker/v1", kwargs...)
    PerfChecker.register_oxygen_routes!(suite; prefix, kwargs...)
    return Oxygen.serve(; host = String(host), port = Int(port), async)
end

end
