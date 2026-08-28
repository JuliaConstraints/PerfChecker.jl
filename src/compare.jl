"A definition-aware comparison between two portable run bundles."
struct BundleComparison
    baseline_run_id::String
    candidate_run_id::String
    inputs_passed::Bool
    environment_status::Symbol
    warnings::Vector{String}
    records::Vector{Dict{String, Any}}
end

function _median(values::Vector{Float64})
    isempty(values) && return nothing
    ordered = sort(values)
    middle = length(ordered) ÷ 2
    return isodd(length(ordered)) ? ordered[middle + 1] :
           (ordered[middle] + ordered[middle + 1]) / 2
end

function _observation_groups(bundle::RunBundle)
    groups = Dict{String, Vector{Dict{String, Any}}}()
    for observation in bundle.observations
        case_id = String(get(observation, "case_id", "unknown"))
        comparison_key = get(observation, "comparison_key", nothing)
        comparison_key === nothing &&
            (comparison_key = get(observation, "measurement_definition", "unknown"))
        join_key = "$case_id::$(String(comparison_key))"
        push!(get!(groups, join_key, Dict{String, Any}[]), observation)
    end
    return groups
end

function _definition_index(bundle::RunBundle)
    return Dict(String(definition["id"]) => definition
                for definition in bundle.measurement_definitions)
end

function _environment_comparability(baseline::RunBundle, candidate::RunBundle)
    left_runtime = get(baseline.manifest, "runtime", Dict{String, Any}())
    right_runtime = get(candidate.manifest, "runtime", Dict{String, Any}())
    left_environment = get(baseline.manifest, "environment", Dict{String, Any}())
    right_environment = get(candidate.manifest, "environment", Dict{String, Any}())
    warnings = String[]
    get(left_runtime, "language", nothing) == get(right_runtime, "language", nothing) ||
        return :incomparable, ["runtime languages differ"]
    for key in ("os", "architecture")
        left = get(left_environment, key, nothing)
        right = get(right_environment, key, nothing)
        left == right || return :incomparable, ["environment field $key differs"]
    end
    if get(left_runtime, "version", nothing) != get(right_runtime, "version", nothing)
        push!(warnings, "runtime versions differ")
    end
    return isempty(warnings) ? :identical : :compatible, warnings
end

function _limit_for(relative_limits::AbstractDict, metric::String)
    value = get(relative_limits, metric, nothing)
    value === nothing && return nothing
    value isa Real && value >= 0 ||
        throw(ArgumentError("relative limit for $metric must be non-negative"))
    return Float64(value)
end

"Compare exact measurement definitions; no cross-unit conversion is implicit."
function compare_bundles(baseline::RunBundle, candidate::RunBundle;
        relative_limits::AbstractDict = Dict{String, Float64}(), min_samples::Integer = 1)
    min_samples > 0 || throw(ArgumentError("min_samples must be positive"))
    environment_status, warnings = _environment_comparability(baseline, candidate)
    baseline_groups = _observation_groups(baseline)
    candidate_groups = _observation_groups(candidate)
    baseline_definitions = _definition_index(baseline)
    candidate_definitions = _definition_index(candidate)
    records = Dict{String, Any}[]
    keys_union = sort!(collect(union(keys(baseline_groups), keys(candidate_groups))))
    for key in keys_union
        left = get(baseline_groups, key, Dict{String, Any}[])
        right = get(candidate_groups, key, Dict{String, Any}[])
        template = isempty(right) ? first(left) : first(right)
        metric = String(get(template, "metric", "unknown"))
        definition_id = String(get(template, "measurement_definition", "unknown"))
        unit = String(get(template, "unit", "unknown"))
        record = Dict{String, Any}(
            "case_id" => String(get(template, "case_id", "unknown")),
            "comparison_key" => String(get(template, "comparison_key", definition_id)),
            "metric" => metric,
            "measurement_definition" => definition_id,
            "unit" => unit,
            "baseline_samples" => length(left),
            "candidate_samples" => length(right))
        if isempty(left) || isempty(right)
            record["status"] = "missing"
            record["reason"] = isempty(left) ? "baseline observation is missing" :
                               "candidate observation is missing"
            push!(records, record)
            continue
        end
        left_definition_id = String(get(first(left), "measurement_definition", "unknown"))
        right_definition_id = String(get(first(right), "measurement_definition", "unknown"))
        left_definition = get(baseline_definitions, left_definition_id, nothing)
        right_definition = get(candidate_definitions, right_definition_id, nothing)
        if left_definition_id != right_definition_id ||
                left_definition === nothing || right_definition === nothing ||
                _canonical_json(left_definition) != _canonical_json(right_definition)
            record["status"] = "incomparable"
            record["reason"] = "measurement definition or unit differs"
            push!(records, record)
            continue
        end
        left_values = Float64[observation["value"] for observation in left
                              if observation["value"] isa Number]
        right_values = Float64[observation["value"] for observation in right
                               if observation["value"] isa Number]
        if length(left_values) < min_samples || length(right_values) < min_samples
            record["status"] = "insufficient_samples"
            record["reason"] = "minimum sample count is $min_samples"
            push!(records, record)
            continue
        end
        baseline_median = _median(left_values)
        candidate_median = _median(right_values)
        absolute_delta = candidate_median - baseline_median
        relative_delta = iszero(baseline_median) ? nothing :
                         absolute_delta / abs(baseline_median)
        record["baseline_median"] = baseline_median
        record["candidate_median"] = candidate_median
        record["absolute_delta"] = absolute_delta
        record["relative_delta"] = relative_delta
        limit = _limit_for(relative_limits, metric)
        record["relative_limit"] = limit
        if environment_status === :incomparable
            record["status"] = "incomparable"
            record["reason"] = first(warnings)
        elseif limit === nothing
            record["status"] = "diagnostic"
            record["reason"] = "no CI policy configured for this metric"
        elseif relative_delta === nothing
            record["status"] = "incomparable"
            record["reason"] = "zero baseline cannot produce a relative delta"
        else
            direction = String(get(right_definition, "preference", "lower"))
            regression = direction == "higher" ? relative_delta < -limit :
                         relative_delta > limit
            record["status"] = regression ? "regression" : "pass"
            record["reason"] = regression ? "relative limit exceeded" : "within policy"
        end
        push!(records, record)
    end
    return BundleComparison(String(baseline.manifest["run_id"]),
        String(candidate.manifest["run_id"]),
        bundle_passed(baseline) && bundle_passed(candidate), environment_status,
        warnings, records)
end

comparison_passed(comparison::BundleComparison) =
    comparison.inputs_passed && comparison.environment_status !== :incomparable &&
    !any(get(record, "status", "") in
         ("regression", "missing", "incomparable", "insufficient_samples")
         for record in comparison.records)

function comparison_dict(comparison::BundleComparison)
    return Dict{String, Any}(
        "schema_version" => "perfchecker-comparison/1",
        "baseline_run_id" => comparison.baseline_run_id,
        "candidate_run_id" => comparison.candidate_run_id,
        "inputs_passed" => comparison.inputs_passed,
        "environment_status" => string(comparison.environment_status),
        "warnings" => comparison.warnings,
        "passed" => comparison_passed(comparison),
        "records" => comparison.records)
end

function write_comparison_json(comparison::BundleComparison, path::AbstractString)
    mkpath(dirname(path))
    _write_json(path, comparison_dict(comparison); canonical = true)
    return String(path)
end

function write_comparison_markdown(comparison::BundleComparison, path::AbstractString)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "# PerfChecker comparison\n")
        println(io, "Environment: `$(comparison.environment_status)`  ")
        println(io, "Status: **$(comparison_passed(comparison) ? "PASS" : "FAIL")**\n")
        println(io, "| Metric | Baseline median | Candidate median | Delta | Status |")
        println(io, "| --- | ---: | ---: | ---: | --- |")
        for record in comparison.records
            baseline = get(record, "baseline_median", "—")
            candidate = get(record, "candidate_median", "—")
            delta = get(record, "relative_delta", nothing)
            formatted_delta = delta === nothing ? "—" :
                              "$(round(100 * delta; digits = 2))%"
            println(io, "| $(record["metric"]) | $baseline | $candidate | " *
                        "$formatted_delta | $(record["status"]) |")
        end
    end
    return String(path)
end

@testitem "Definition-aware bundle comparison" tags=[:unit, :protocol, :comparison] begin
    using PerfChecker

    definition = Dict{String, Any}(
        "id" => "julia.wall.time/test-v1", "metric" => "julia.wall.time",
        "unit" => "ns", "preference" => "lower")
    function example_bundle(id, values; os = string(Sys.KERNEL))
        observations = [Dict{String, Any}(
            "metric" => "julia.wall.time", "value" => value, "unit" => "ns",
            "measurement_definition" => "julia.wall.time/test-v1",
            "comparison_key" => "parse::julia.wall.time/test-v1") for value in values]
        manifest = Dict{String, Any}(
            "schema_version" => "perfchecker-run-bundle/1", "run_id" => id,
            "attempt_id" => id, "reuse_key" => repeat("a", 64),
            "evidence" => "fresh", "state" => "complete", "suite" => "example",
            "runtime" => Dict("language" => "julia", "version" => string(VERSION)),
            "environment" => Dict("os" => os, "architecture" => string(Sys.ARCH)),
            "collector_capabilities" => ["test"], "warnings" => String[])
        RunBundle(manifest, [definition], observations, Dict{String, Any}[],
            Dict{String, Any}[])
    end

    baseline = example_bundle("00000000-0000-0000-0000-000000000001", [10, 10, 10])
    candidate = example_bundle("00000000-0000-0000-0000-000000000002", [12, 12, 12])
    diagnostic = compare_bundles(baseline, candidate)
    @test comparison_passed(diagnostic)
    @test only(diagnostic.records)["status"] == "diagnostic"
    gated = compare_bundles(baseline, candidate;
        relative_limits = Dict("julia.wall.time" => 0.1), min_samples = 3)
    @test !comparison_passed(gated)
    @test only(gated.records)["status"] == "regression"
    @test only(gated.records)["relative_delta"] ≈ 0.2

    for observation in baseline.observations
        observation["case_id"] = "parse@dev"
    end
    for observation in candidate.observations
        observation["case_id"] = "parse@dev"
    end
    append!(baseline.observations, [merge(copy(observation),
        Dict("case_id" => "format@dev", "value" => 1000))
        for observation in baseline.observations[1:3]])
    append!(candidate.observations, [merge(copy(observation),
        Dict("case_id" => "format@dev", "value" => 1000))
        for observation in candidate.observations[1:3]])
    separated = compare_bundles(baseline, candidate)
    @test length(separated.records) == 2
    @test Set(record["case_id"] for record in separated.records) ==
          Set(["parse@dev", "format@dev"])
    @test all(record["comparison_key"] == "parse::julia.wall.time/test-v1"
              for record in separated.records)

    failed = example_bundle("00000000-0000-0000-0000-000000000003", [12, 12, 12])
    failed.manifest["state"] = "failed"
    @test !comparison_passed(compare_bundles(baseline, failed))

    mktempdir() do dir
        @test isfile(write_comparison_json(gated, joinpath(dir, "comparison.json")))
        @test occursin("20.0%",
            read(write_comparison_markdown(gated, joinpath(dir, "comparison.md")), String))
    end
end
