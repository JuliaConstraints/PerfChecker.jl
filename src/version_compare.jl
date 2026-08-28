"A release-by-release comparison and its plottable version series."
struct VersionComparison
    run_id::String
    input_passed::Bool
    warnings::Vector{String}
    availability::Vector{Dict{String, Any}}
    series::Vector{Dict{String, Any}}
    records::Vector{Dict{String, Any}}
end

function _version_point_key(point::AbstractDict)
    kind = String(get(point, "target_kind", "release"))
    label = String(get(point, "version", ""))
    if kind == "dev"
        return (1, v"0.0.0", label)
    end
    version = try
        VersionNumber(label)
    catch
        v"0.0.0"
    end
    return (0, version, label)
end

function _series_identifier(parts)
    return _content_digest(parts)[1:16]
end

"Aggregate raw observations into plottable medians for every package feature/version."
function suite_version_series(bundle::RunBundle)
    groups = Dict{NTuple{8, String}, Vector{Float64}}()
    for observation in bundle.observations
        attributes = get(observation, "attributes", nothing)
        attributes isa AbstractDict || continue
        all(haskey(attributes, key) for key in
            ("package", "feature", "version", "target_kind")) || continue
        value = get(observation, "value", nothing)
        value isa Number || continue
        numeric = Float64(value)
        isfinite(numeric) || continue
        key = (
            String(attributes["package"]),
            String(attributes["feature"]),
            String(get(observation, "comparison_key", "")),
            String(get(observation, "metric", "unknown")),
            String(get(observation, "measurement_definition", "unknown")),
            String(get(observation, "unit", "unknown")),
            String(attributes["version"]),
            String(attributes["target_kind"]),
        )
        push!(get!(groups, key, Float64[]), numeric)
    end

    series_groups = Dict{NTuple{6, String}, Vector{Dict{String, Any}}}()
    for (key, values) in groups
        package, feature, comparison_key, metric, definition, unit, version, kind = key
        point = Dict{String, Any}(
            "version" => version,
            "target_kind" => kind,
            "median" => _median(values),
            "samples" => length(values),
        )
        series_key = (package, feature, comparison_key, metric, definition, unit)
        push!(get!(series_groups, series_key, Dict{String, Any}[]), point)
    end

    result = Dict{String, Any}[]
    for (key, points) in series_groups
        package, feature, comparison_key, metric, definition, unit = key
        sort!(points; by = _version_point_key)
        push!(result, Dict{String, Any}(
            "series_id" => _series_identifier(key),
            "package" => package,
            "feature" => feature,
            "comparison_key" => comparison_key,
            "metric" => metric,
            "measurement_definition" => definition,
            "unit" => unit,
            "points" => points,
        ))
    end
    sort!(result; by = series -> (
        series["package"], series["feature"], series["metric"],
        series["measurement_definition"]))
    return result
end

function _version_pairs(points)
    releases = [point for point in points if point["target_kind"] == "release"]
    development = [point for point in points if point["target_kind"] == "dev"]
    pairs = Tuple{Any, Any, String}[]
    for index in 2:length(releases)
        push!(pairs, (releases[index - 1], releases[index], "adjacent-release"))
    end
    if !isempty(releases)
        for point in development
            push!(pairs, (last(releases), point, "dev-vs-latest-release"))
        end
    end
    return pairs
end

function _availability_records(bundle::RunBundle)
    plan = get(bundle.manifest, "plan", nothing)
    plan isa AbstractDict || return Dict{String, Any}[]
    planned = get(plan, "runs", nothing)
    planned isa AbstractVector || return Dict{String, Any}[]
    observed = Set((String(get(item, "case_id", "")),
                    String(get(item, "target_id", ""))) for item in bundle.observations)
    diagnostics = Dict(
        (String(get(item, "case_id", "")), String(get(item, "target_id", ""))) => item
        for item in bundle.diagnostics)
    suite = String(get(bundle.manifest, "suite", "suite"))
    records = Dict{String, Any}[]
    for run in planned
        package_id = String(get(run, "package_id", get(run, "package", "package")))
        feature = String(get(run, "feature", "feature"))
        case_id = "$suite/$package_id/$feature"
        target_id = String(get(run, "version", ""))
        diagnostic = get(diagnostics, (case_id, target_id), nothing)
        status, reason = if diagnostic !== nothing
            (String(get(get(diagnostic, "evidence", Dict()), "status", "failed")),
             String(get(diagnostic, "message", "")))
        elseif (case_id, target_id) in observed
            ("observed", "")
        elseif String(get(run, "status", "ready")) == "unavailable"
            ("unavailable", String(get(run, "reason", "")))
        else
            ("missing", "planned target produced no observation")
        end
        push!(records, Dict{String, Any}(
            "run_id" => String(get(run, "id", "")), "case_id" => case_id,
            "package" => String(get(run, "package", package_id)),
            "package_id" => package_id, "feature" => feature,
            "version" => target_id,
            "target_kind" => String(get(run, "target_kind", "release")),
            "comparison_key" => String(get(run, "comparison_key", "")),
            "status" => status, "reason" => reason))
    end
    sort!(records; by = item -> (item["package"], item["feature"],
        _version_point_key(item)))
    return records
end

function _expected_points(series, availability)
    definition_suffix = "::$(series["measurement_definition"])"
    base_key = endswith(String(series["comparison_key"]), definition_suffix) ?
        chop(String(series["comparison_key"]); tail = length(definition_suffix)) :
        String(series["comparison_key"])
    matching = [Dict{String, Any}(
                    "version" => item["version"],
                    "target_kind" => item["target_kind"],
                    "availability" => item["status"],
                    "reason" => item["reason"])
                for item in availability
                if item["package"] == series["package"] &&
                   item["feature"] == series["feature"] &&
                   item["comparison_key"] == base_key]
    unique!(item -> (item["version"], item["target_kind"]), matching)
    sort!(matching; by = _version_point_key)
    return matching
end

function _comparison_pairs(series, availability)
    expected = _expected_points(series, availability)
    isempty(expected) && return _version_pairs(series["points"])
    observed = Dict(String(point["version"]) => point for point in series["points"])
    return [(get(observed, String(baseline["version"]), baseline),
             get(observed, String(candidate["version"]), candidate), relation)
            for (baseline, candidate, relation) in _version_pairs(expected)]
end

function _version_comparison_record(series, baseline, candidate, relation,
        definition, relative_limits, min_samples)
    metric = String(series["metric"])
    baseline_median = Float64(baseline["median"])
    candidate_median = Float64(candidate["median"])
    absolute_delta = candidate_median - baseline_median
    relative_delta = iszero(baseline_median) ? nothing :
                     absolute_delta / abs(baseline_median)
    limit = _limit_for(relative_limits, metric)
    record = Dict{String, Any}(
        "series_id" => series["series_id"],
        "package" => series["package"],
        "feature" => series["feature"],
        "comparison_key" => series["comparison_key"],
        "metric" => metric,
        "measurement_definition" => series["measurement_definition"],
        "unit" => series["unit"],
        "relation" => relation,
        "baseline_version" => baseline["version"],
        "candidate_version" => candidate["version"],
        "baseline_samples" => baseline["samples"],
        "candidate_samples" => candidate["samples"],
        "baseline_median" => baseline_median,
        "candidate_median" => candidate_median,
        "absolute_delta" => absolute_delta,
        "relative_delta" => relative_delta,
        "relative_limit" => limit,
    )
    if baseline["samples"] < min_samples || candidate["samples"] < min_samples
        record["status"] = "insufficient_samples"
        record["reason"] = "minimum sample count is $min_samples"
    elseif limit === nothing
        record["status"] = "diagnostic"
        record["reason"] = "no CI policy configured for this metric"
    elseif relative_delta === nothing
        record["status"] = "incomparable"
        record["reason"] = "zero baseline cannot produce a relative delta"
    else
        preference = String(get(definition, "preference", "lower"))
        regression = preference == "higher" ? relative_delta < -limit :
                     relative_delta > limit
        record["status"] = regression ? "regression" : "pass"
        record["reason"] = regression ? "relative limit exceeded" : "within policy"
    end
    return record
end

function _missing_version_record(series, baseline, candidate, relation)
    missing = String[]
    haskey(baseline, "median") || push!(missing, String(baseline["version"]))
    haskey(candidate, "median") || push!(missing, String(candidate["version"]))
    reasons = unique!(String[get(point, "reason", "no observation")
        for point in (baseline, candidate) if !haskey(point, "median")])
    return Dict{String, Any}(
        "series_id" => series["series_id"], "package" => series["package"],
        "feature" => series["feature"], "comparison_key" => series["comparison_key"],
        "metric" => series["metric"],
        "measurement_definition" => series["measurement_definition"],
        "unit" => series["unit"], "relation" => relation,
        "baseline_version" => baseline["version"],
        "candidate_version" => candidate["version"],
        "baseline_samples" => get(baseline, "samples", 0),
        "candidate_samples" => get(candidate, "samples", 0),
        "baseline_median" => get(baseline, "median", nothing),
        "candidate_median" => get(candidate, "median", nothing),
        "absolute_delta" => nothing, "relative_delta" => nothing,
        "relative_limit" => nothing, "status" => "missing",
        "reason" => "missing observations for $(join(missing, ", ")): $(join(reasons, "; "))")
end

"Compare adjacent releases, then compare a development checkout to the latest release."
function compare_suite_versions(bundle::RunBundle;
        relative_limits::AbstractDict = Dict{String, Float64}(),
        min_samples::Integer = 1)
    min_samples > 0 || throw(ArgumentError("min_samples must be positive"))
    series = suite_version_series(bundle)
    availability = _availability_records(bundle)
    definitions = _definition_index(bundle)
    records = Dict{String, Any}[]
    warnings = String[]
    isempty(series) && push!(warnings,
        "bundle has no package/feature/version observations")
    for item in series
        definition = get(definitions, String(item["measurement_definition"]), nothing)
        if definition === nothing
            push!(warnings, "missing definition $(item["measurement_definition"])")
            continue
        end
        for (baseline, candidate, relation) in _comparison_pairs(item, availability)
            record = haskey(baseline, "median") && haskey(candidate, "median") ?
                _version_comparison_record(item, baseline, candidate,
                    relation, definition, relative_limits, min_samples) :
                _missing_version_record(item, baseline, candidate, relation)
            push!(records, record)
        end
    end
    return VersionComparison(String(bundle.manifest["run_id"]), bundle_passed(bundle),
        unique!(warnings), availability, series, records)
end

version_comparison_passed(comparison::VersionComparison) =
    comparison.input_passed &&
    !any(get(record, "status", "") in
         ("regression", "incomparable", "insufficient_samples", "missing")
         for record in comparison.records)

function version_comparison_dict(comparison::VersionComparison)
    return Dict{String, Any}(
        "schema_version" => "perfchecker-version-comparison/1",
        "run_id" => comparison.run_id,
        "input_passed" => comparison.input_passed,
        "passed" => version_comparison_passed(comparison),
        "warnings" => comparison.warnings,
        "availability" => comparison.availability,
        "series" => comparison.series,
        "records" => comparison.records,
    )
end

function write_version_series_json(comparison::VersionComparison, path::AbstractString)
    mkpath(dirname(path))
    _write_json(path, Dict(
        "schema_version" => "perfchecker-version-series/1",
        "run_id" => comparison.run_id,
        "availability" => comparison.availability,
        "series" => comparison.series); canonical = true)
    return String(path)
end

function write_version_comparison_json(comparison::VersionComparison,
        path::AbstractString)
    mkpath(dirname(path))
    _write_json(path, version_comparison_dict(comparison); canonical = true)
    return String(path)
end

function write_version_comparison_markdown(comparison::VersionComparison,
        path::AbstractString)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "# PerfChecker version comparison\n")
        println(io, "Status: **$(version_comparison_passed(comparison) ? "PASS" : "FAIL")**  ")
        println(io, "Series: $(length(comparison.series))  ")
        println(io, "Comparisons: $(length(comparison.records))\n")
        println(io, "| Package | Feature | Metric | Baseline | Candidate | Delta | Status |")
        println(io, "| --- | --- | --- | --- | --- | ---: | --- |")
        for record in comparison.records
            delta = record["relative_delta"]
            formatted = delta === nothing ? "—" : "$(round(100 * delta; digits = 2))%"
            println(io, "| $(record["package"]) | $(record["feature"]) | " *
                        "$(record["metric"]) | $(record["baseline_version"]) | " *
                        "$(record["candidate_version"]) | $formatted | " *
                        "$(record["status"]) |")
        end
        unavailable = [item for item in comparison.availability
            if item["status"] != "observed"]
        if !isempty(unavailable)
            println(io, "\n## Unavailable, failed, or missing targets\n")
            println(io, "| Package | Feature | Version | Status | Reason |")
            println(io, "| --- | --- | --- | --- | --- |")
            for item in unavailable
                println(io, "| $(item["package"]) | $(item["feature"]) | " *
                    "$(item["version"]) | $(item["status"]) | $(item["reason"]) |")
            end
        end
    end
    return String(path)
end

@testitem "Historical version series and comparisons" tags=[:unit, :protocol, :comparison] begin
    using PerfChecker

    definition = Dict{String, Any}(
        "id" => "julia.wall.time/test-v1", "metric" => "julia.wall.time",
        "unit" => "ns", "preference" => "lower")
    observations = Dict{String, Any}[]
    for (version, kind, values) in (
            ("0.1.0", "release", [10, 12]),
            ("0.2.0", "release", [8, 10]),
            ("dev@0.3.0", "dev", [12, 14]))
        for (index, value) in enumerate(values)
            push!(observations, Dict{String, Any}(
                "case_id" => "Example/parse@$version",
                "metric" => "julia.wall.time", "value" => value, "unit" => "ns",
                "sample_index" => index,
                "measurement_definition" => "julia.wall.time/test-v1",
                "comparison_key" => "parse/v1::julia.wall.time/test-v1",
                "attributes" => Dict("package" => "Example", "feature" => "parse",
                    "version" => version, "target_kind" => kind)))
        end
    end
    manifest = Dict{String, Any}(
        "schema_version" => "perfchecker-run-bundle/1",
        "run_id" => "00000000-0000-0000-0000-000000000010",
        "attempt_id" => "00000000-0000-0000-0000-000000000011",
        "reuse_key" => repeat("a", 64), "evidence" => "fresh",
        "state" => "complete", "suite" => "example",
        "runtime" => Dict("language" => "julia"),
        "environment" => Dict{String, Any}(),
        "collector_capabilities" => ["test"], "warnings" => String[])
    bundle = RunBundle(manifest, [definition], observations,
        Dict{String, Any}[], Dict{String, Any}[])
    diagnostic = compare_suite_versions(bundle)
    @test length(diagnostic.series) == 1
    @test [point["version"] for point in only(diagnostic.series)["points"]] ==
          ["0.1.0", "0.2.0", "dev@0.3.0"]
    @test length(diagnostic.records) == 2
    @test Set(record["relation"] for record in diagnostic.records) ==
          Set(["adjacent-release", "dev-vs-latest-release"])
    @test all(record["status"] == "diagnostic" for record in diagnostic.records)
    gated = compare_suite_versions(bundle;
        relative_limits = Dict("julia.wall.time" => 0.1), min_samples = 2)
    @test !version_comparison_passed(gated)
    @test only(filter(record -> record["relation"] == "dev-vs-latest-release",
        gated.records))["status"] == "regression"
    mktempdir() do dir
        @test isfile(write_version_series_json(gated, joinpath(dir, "series.json")))
        @test isfile(write_version_comparison_json(gated,
            joinpath(dir, "comparison.json")))
        @test occursin("dev@0.3.0", read(write_version_comparison_markdown(gated,
            joinpath(dir, "comparison.md")), String))
    end
end
