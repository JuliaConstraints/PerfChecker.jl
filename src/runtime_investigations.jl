const JULIA_INVESTIGATION_SCHEMA = "perfchecker-julia-investigation/1"

"Ranked source evidence for differences between two Julia runtime runs."
struct JuliaRegressionInvestigation
    campaign_id::String
    generated_at::String
    comparisons::Vector{Dict{String, Any}}
end

function _runtime_source_owner(path::AbstractString)
    normalized = lowercase(replace(String(path), '\\' => '/'))
    return occursin("/share/julia/base/", normalized) ||
           occursin("/share/julia/stdlib/", normalized) ||
           occursin("/compiler/", normalized) ? "julia_runtime" : "package_or_dependency"
end

function _source_observation_totals(bundle::RunBundle)
    totals = Dict{NTuple{5, String}, Float64}()
    for observation in bundle.observations
        attributes = get(observation, "attributes", nothing)
        attributes isa AbstractDict || continue
        file = get(attributes, "source_file", nothing)
        line = get(attributes, "source_line", nothing)
        file isa AbstractString && line isa Integer || continue
        value = get(observation, "value", nothing)
        value isa Number || continue
        key = (String(get(observation, "comparison_key", "")),
            String(get(observation, "metric", "unknown")), String(file),
            string(line), String(get(observation, "measurement_definition", "unknown")))
        totals[key] = get(totals, key, 0.0) + Float64(value)
    end
    return totals
end

function _runtime_investigation_comparison(campaign::JuliaRuntimeCampaign,
        comparison::AbstractDict; max_frames::Integer, obvious_share::Real)
    baseline_id = String(comparison["baseline_runtime_id"])
    candidate_id = String(comparison["candidate_runtime_id"])
    baseline_run = only(filter(run -> run["runtime_id"] == baseline_id, campaign.runs))
    candidate_run = only(filter(run -> run["runtime_id"] == candidate_id, campaign.runs))
    baseline_path = get(baseline_run, "bundle_path", nothing)
    candidate_path = get(candidate_run, "bundle_path", nothing)
    if baseline_path === nothing || candidate_path === nothing
        failed = candidate_path === nothing ? candidate_run : baseline_run
        failure = String(get(failed, "failure_summary", "runtime bundle is unavailable"))
        return Dict{String, Any}(
            "baseline_runtime_id" => baseline_id,
            "candidate_runtime_id" => candidate_id,
            "status" => "unavailable", "frames" => Dict{String, Any}[],
            "failure_kind" => String(get(failed, "failure_kind", "unknown")),
            "failure_frames" => get(failed, "failure_frames", Dict{String, Any}[]),
            "obvious_candidate" => false,
            "reason" => "runtime $(failed["runtime_id"]) is unavailable: $failure")
    end
    baseline = _source_observation_totals(read_run_bundle(String(baseline_path)))
    candidate = _source_observation_totals(read_run_bundle(String(candidate_path)))
    rows = Dict{String, Any}[]
    for key in union(keys(baseline), keys(candidate))
        base = get(baseline, key, 0.0)
        current = get(candidate, key, 0.0)
        delta = current - base
        delta > 0 || continue
        comparison_key, metric, file, line, definition = key
        push!(rows,
            Dict{String, Any}(
                "comparison_key" => comparison_key,
                "metric" => metric,
                "measurement_definition" => definition,
                "source_file" => file,
                "source_line" => Base.parse(Int, line),
                "owner" => _runtime_source_owner(file),
                "baseline_value" => base,
                "candidate_value" => current,
                "positive_delta" => delta))
    end
    sort!(rows; by = row -> -Float64(row["positive_delta"]))
    total = sum(row -> Float64(row["positive_delta"]), rows; init = 0.0)
    for row in rows
        row["positive_delta_share"] = iszero(total) ? 0.0 :
                                      row["positive_delta"] / total
    end
    resize!(rows, min(length(rows), max_frames))
    obvious = !isempty(rows) && rows[1]["owner"] == "julia_runtime" &&
              rows[1]["positive_delta_share"] >= obvious_share
    return Dict{String, Any}(
        "baseline_runtime_id" => baseline_id,
        "candidate_runtime_id" => candidate_id,
        "status" => isempty(rows) ? "no_source_evidence" : "ranked",
        "frames" => rows,
        "obvious_candidate" => obvious,
        "reason" => obvious ?
                    "one Julia runtime frame dominates the positive sampled delta" :
                    "source evidence is ranked but not sufficient for an automatic MWE")
end

"Rank source lines that gained sampled CPU/allocation weight across Julia runtimes."
function investigate_julia_regressions(campaign::JuliaRuntimeCampaign;
        max_frames::Integer = 50, obvious_share::Real = 0.6)
    max_frames > 0 || throw(ArgumentError("max_frames must be positive"))
    0 < obvious_share <= 1 || throw(ArgumentError("obvious_share must be in (0, 1]"))
    comparisons = [_runtime_investigation_comparison(campaign, comparison;
                       max_frames, obvious_share) for comparison in campaign.comparisons]
    return JuliaRegressionInvestigation(campaign.id,
        string(Dates.now(Dates.UTC)), comparisons)
end

function julia_investigation_dict(investigation::JuliaRegressionInvestigation)
    return Dict{String, Any}(
        "schema_version" => JULIA_INVESTIGATION_SCHEMA,
        "campaign_id" => investigation.campaign_id,
        "generated_at" => investigation.generated_at,
        "comparisons" => investigation.comparisons)
end

function write_julia_investigation(investigation::JuliaRegressionInvestigation,
        directory::AbstractString)
    root = abspath(String(directory))
    mkpath(root)
    json_path = joinpath(root, "julia-investigation.json")
    markdown_path = joinpath(root, "julia-investigation.md")
    _write_json(json_path, julia_investigation_dict(investigation); canonical = true)
    open(markdown_path, "w") do io
        println(io, "# Julia runtime regression investigation\n")
        for comparison in investigation.comparisons
            baseline_id = comparison["baseline_runtime_id"]
            candidate_id = comparison["candidate_runtime_id"]
            reason = comparison["reason"]
            println(io, "## $baseline_id → $candidate_id\n")
            println(io, "$reason\n")
            println(io, "| Owner | File | Line | Metric | Positive delta | Share |")
            println(io, "| --- | --- | ---: | --- | ---: | ---: |")
            for frame in comparison["frames"]
                share = round(100 * frame["positive_delta_share"]; digits = 2)
                owner = frame["owner"]
                source_file = frame["source_file"]
                source_line = frame["source_line"]
                metric = frame["metric"]
                delta = frame["positive_delta"]
                println(io,
                    "| $owner | `$source_file` | $source_line | $metric | " *
                    "$delta | $share% |")
            end
            println(io)
        end
    end
    return [json_path, markdown_path]
end

@testitem "Julia regression source attribution" tags=[:unit, :runtime, :attribution] begin
    using PerfChecker

    function bundle(path, id, value)
        definition = Dict{String, Any}("id" => "julia.cpu.samples/profile-v1",
            "metric" => "julia.cpu.samples", "unit" => "1", "preference" => "lower")
        observation = Dict{String, Any}(
            "comparison_key" => "parse::julia.cpu.samples/profile-v1",
            "metric" => "julia.cpu.samples", "value" => value, "unit" => "1",
            "measurement_definition" => "julia.cpu.samples/profile-v1",
            "attributes" => Dict("source_file" => "/share/julia/base/loading.jl",
                "source_line" => 42))
        manifest = Dict{String, Any}("schema_version" => "perfchecker-run-bundle/1",
            "run_id" => id, "attempt_id" => id, "reuse_key" => repeat("a", 64),
            "evidence" => "fresh", "state" => "complete", "suite" => "demo",
            "runtime" => Dict("language" => "julia"), "environment" => Dict(),
            "collector_capabilities" => ["profile"], "warnings" => String[])
        write_run_bundle(
            RunBundle(manifest, [definition], [observation],
                Dict{String, Any}[], Dict{String, Any}[]),
            path)
    end
    mktempdir() do root
        baseline_path = bundle(joinpath(root, "baseline"),
            "00000000-0000-0000-0000-000000000001", 10)
        candidate_path = bundle(joinpath(root, "candidate"),
            "00000000-0000-0000-0000-000000000002", 30)
        runs = [Dict{String, Any}("runtime_id" => "base", "bundle_path" => baseline_path),
            Dict{String, Any}("runtime_id" => "next", "bundle_path" => candidate_path)]
        comparisons = [Dict{String, Any}("baseline_runtime_id" => "base",
            "candidate_runtime_id" => "next")]
        campaign = JuliaRuntimeCampaign("campaign", "suite.jl", :ci, :base,
            "start", "finish", runs, comparisons)
        investigation = investigate_julia_regressions(campaign)
        frame = only(only(investigation.comparisons)["frames"])
        @test frame["owner"] == "julia_runtime"
        @test frame["positive_delta"] == 20
        @test only(investigation.comparisons)["obvious_candidate"]
        @test all(
            isfile, write_julia_investigation(investigation, joinpath(root, "report")))
    end
end
