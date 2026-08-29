const PERFORMANCE_PLOT_SCHEMA = "perfchecker-plot/1"

"Backend-neutral plot description consumed by Makie, Oxygen, notebooks and CI exporters."
struct PerformancePlot
    id::String
    kind::Symbol
    title::String
    description::String
    encoding::Dict{String, Any}
    data::Vector{Dict{String, Any}}
    options::Dict{String, Any}
end

function performance_plot_dict(plot::PerformancePlot)
    return Dict{String, Any}(
        "schema_version" => PERFORMANCE_PLOT_SCHEMA,
        "id" => plot.id,
        "kind" => string(plot.kind),
        "title" => plot.title,
        "description" => plot.description,
        "encoding" => plot.encoding,
        "data" => plot.data,
        "options" => plot.options)
end

function _plot_id(kind::Symbol, identity...)
    return "$(replace(string(kind), '_' => '-'))-$(_content_digest((kind, identity...))[1:16])"
end

function _series_catalog(bundle::RunBundle)
    entries = Dict{String, Any}[]
    series = suite_version_series(bundle)
    for item in series
        identity = String(item["series_id"])
        common = Dict{String, Any}(
            "package" => item["package"], "feature" => item["feature"],
            "metric" => item["metric"], "unit" => item["unit"],
            "series_id" => identity)
        kinds = item["measurement_definition"] in (
            "julia.alloc.bytes/line-tracking-v1", "julia.alloc.bytes/profile-allocs-v1",
            "julia.alloc.count/profile-allocs-v1", "julia.cpu.samples/profile-v1") ?
                ((:version_series, "Version trajectory"),
            (:version_delta, "Regression deltas")) :
                ((:version_series, "Version trajectory"),
            (:distribution, "Sample distribution"),
            (:version_delta, "Regression deltas"))
        for (kind, label) in kinds
            push!(entries,
                merge(copy(common),
                    Dict{String, Any}(
                        "id" => _plot_id(kind, identity), "kind" => string(kind),
                        "title" => "$(item["package"]) · $(item["feature"]) · $(item["metric"])",
                        "label" => label)))
        end
    end
    return entries
end

function _plot_base_comparison_key(series)
    suffix = "::$(series["measurement_definition"])"
    key = String(series["comparison_key"])
    return endswith(key, suffix) ? chop(key; tail = length(suffix)) : key
end

function _allocation_observations(bundle::RunBundle)
    return [observation
            for observation in bundle.observations
            if get(observation, "measurement_definition", "") in (
        "julia.alloc.bytes/line-tracking-v1",
        "julia.alloc.bytes/profile-allocs-v1") &&
        get(get(observation, "attributes", Dict()), "source_file", nothing) !==
        nothing]
end

function _allocation_catalog(bundle::RunBundle)
    identities = Dict{Tuple{String, String, String}, Dict{String, Any}}()
    for observation in _allocation_observations(bundle)
        attributes = observation["attributes"]
        package = String(get(attributes, "package", "package"))
        feature = String(get(attributes, "feature", "feature"))
        case_id = String(get(observation, "case_id", "$package/$feature"))
        identities[(package, feature, case_id)] = Dict{String, Any}(
            "package" => package, "feature" => feature, "case_id" => case_id)
    end
    entries = Dict{String, Any}[]
    for ((package, feature, case_id), common) in sort!(collect(identities); by = first)
        for (kind, label) in ((:allocation_pie, "Allocation share by line (%)"),
            (:allocation_files, "Allocations by file"),
            (:allocation_lines, "Allocation hotspots by line"),
            (:allocation_heatmap, "Allocation line heatmap"))
            push!(entries,
                merge(copy(common),
                    Dict{String, Any}(
                        "id" => _plot_id(kind, case_id), "kind" => string(kind),
                        "title" => "$package · $feature · allocations", "label" => label,
                        "metric" => "julia.alloc.bytes", "unit" => "By")))
        end
        observations = _allocation_records(bundle, case_id)
        if any(
            observation -> get(get(observation, "attributes", Dict()),
                "stack", nothing) isa AbstractVector,
            observations)
            push!(entries,
                merge(copy(common),
                    Dict{String, Any}(
                        "id" => _plot_id(:allocation_flamegraph, case_id),
                        "kind" => "allocation_flamegraph",
                        "title" => "$package · $feature · allocation flame graph",
                        "label" => "Allocation flame graph",
                        "metric" => "julia.alloc.bytes", "unit" => "By")))
        end
    end
    return entries
end

function _profile_catalog(bundle::RunBundle)
    identities = Dict{Tuple{String, String, String, String}, Dict{String, Any}}()
    for observation in bundle.observations
        definition = get(observation, "measurement_definition", "")
        definition in ("julia.cpu.samples/profile-v1",
            "julia.wall.samples/profile-walltime-v1") || continue
        attributes = get(observation, "attributes", Dict())
        get(attributes, "stack", nothing) isa AbstractVector || continue
        package = String(get(attributes, "package", "package"))
        feature = String(get(attributes, "feature", "feature"))
        case_id = String(get(observation, "case_id", "$package/$feature"))
        identities[(package, feature, case_id, definition)] = Dict{String, Any}(
            "package" => package, "feature" => feature, "case_id" => case_id,
            "definition" => definition)
    end
    return [merge(copy(common),
                Dict{String, Any}(
                    "id" => _plot_id(
                        definition == "julia.cpu.samples/profile-v1" ?
                        :cpu_flamegraph : :wall_flamegraph,
                        case_id),
                    "kind" =>
                        definition == "julia.cpu.samples/profile-v1" ?
                        "cpu_flamegraph" : "wall_flamegraph",
                    "title" =>
                        "$package · $feature · " *
                        (definition == "julia.cpu.samples/profile-v1" ? "CPU" :
                         "wall-time") *
                        " flame graph",
                    "label" =>
                        definition == "julia.cpu.samples/profile-v1" ?
                        "CPU flame graph" : "Wall-time flame graph",
                    "metric" =>
                        definition == "julia.cpu.samples/profile-v1" ?
                        "julia.cpu.samples" : "julia.wall.samples",
                    "unit" => "samples"))
            for ((package, feature, case_id, definition), common) in sort!(
        collect(identities); by = first)]
end

function _tradeoff_catalog(bundle::RunBundle)
    grouped = Dict{Tuple{String, String, String}, Dict{String, Any}}()
    for series in suite_version_series(bundle)
        metric = String(series["metric"])
        metric in ("julia.wall.time", "julia.alloc.bytes") || continue
        key = (String(series["package"]), String(series["feature"]),
            _plot_base_comparison_key(series))
        get!(grouped, key, Dict{String, Any}())[metric] = series
    end
    entries = Dict{String, Any}[]
    for ((package, feature, comparison_key), metrics) in sort!(collect(grouped); by = first)
        all(haskey(metrics, metric)
        for metric in ("julia.wall.time", "julia.alloc.bytes")) ||
            continue
        push!(entries,
            Dict{String, Any}(
                "id" => _plot_id(
                    :time_allocation_tradeoff, package, feature, comparison_key),
                "kind" => "time_allocation_tradeoff", "package" => package,
                "feature" => feature, "comparison_key" => comparison_key,
                "metric" => "julia.wall.time+julia.alloc.bytes", "unit" => "s+By",
                "title" => "$package · $feature · time/allocation trade-off",
                "label" => "Time vs allocations"))
    end
    return entries
end

"List every plot supported by the evidence contained in a run bundle."
function plot_catalog(bundle::RunBundle)
    plots = vcat(_series_catalog(bundle), _tradeoff_catalog(bundle),
        _allocation_catalog(bundle), _profile_catalog(bundle))
    sort!(plots;
        by = item -> (String(get(item, "package", "")),
            String(get(item, "feature", "")), String(item["kind"]), String(item["id"])))
    return plots
end

function _catalog_entry(bundle::RunBundle, id::AbstractString)
    entry = findfirst(item -> item["id"] == id, plot_catalog(bundle))
    entry === nothing && throw(ArgumentError("unknown performance plot $id"))
    return plot_catalog(bundle)[entry]
end

function _series_by_id(bundle::RunBundle, id::AbstractString)
    series = suite_version_series(bundle)
    index = findfirst(item -> item["series_id"] == id, series)
    index === nothing && throw(ArgumentError("unknown performance series $id"))
    return series[index]
end

function _series_observations(bundle::RunBundle, series)
    return [observation
            for observation in bundle.observations
            if
            get(observation, "comparison_key", "") == series["comparison_key"] &&
                get(observation, "metric", "") == series["metric"] &&
                get(observation, "measurement_definition", "") ==
                series["measurement_definition"] &&
                get(get(observation, "attributes", Dict()), "package", "") ==
                series["package"] &&
                get(get(observation, "attributes", Dict()), "feature", "") ==
                series["feature"]]
end

function _version_records(series)
    return [Dict{String, Any}(
                "version" => point["version"], "target_kind" => point["target_kind"],
                "value" => point["median"], "samples" => point["samples"],
                "aggregation" => get(point, "aggregation", "median"))
            for point in series["points"]]
end

function _distribution_records(bundle, series)
    return [Dict{String, Any}(
                "version" => get(observation, "target_id",
                    get(observation["attributes"], "version", "unknown")),
                "target_kind" => get(observation["attributes"], "target_kind", "release"),
                "value" => Float64(observation["value"]))
            for observation in _series_observations(bundle, series)
            if observation["value"] isa Number]
end

function _delta_records(bundle, series)
    comparison = compare_suite_versions(bundle)
    return [copy(record)
            for record in comparison.records
            if get(record, "series_id", "") == series["series_id"]]
end

function _allocation_records(bundle, case_id::String)
    return [observation
            for observation in _allocation_observations(bundle)
            if get(observation, "case_id", "") == case_id]
end

function _short_source_path(path::AbstractString)
    normalized = replace(normpath(String(path)), '\\' => '/')
    parts = split(normalized, '/')
    return join(last(parts, min(length(parts), 3)), '/')
end

function _allocation_file_records(bundle, case_id)
    grouped = Dict{Tuple{String, String}, Float64}()
    for observation in _allocation_records(bundle, case_id)
        version = String(get(observation, "target_id", "unknown"))
        file = _short_source_path(String(observation["attributes"]["source_file"]))
        key = (version, file)
        grouped[key] = get(grouped, key, 0.0) + Float64(observation["value"])
    end
    versions = unique!(String[first(key) for key in keys(grouped)])
    sort!(versions;
        by = item -> _version_point_key(Dict("version" => item,
            "target_kind" => startswith(item, "dev@") ? "dev" : "release")))
    files = sort!(unique!(String[last(key) for key in keys(grouped)]))
    return [Dict{String, Any}("version" => version, "file" => file,
                "bytes" => get(grouped, (version, file), 0.0))
            for version in versions for file in files if haskey(grouped, (version, file))]
end

function _allocation_pie_records(bundle, case_id; version = nothing, top::Integer = 40)
    records, versions, selected = _allocation_line_records(bundle, case_id;
        version, top = typemax(Int))
    total = sum(item -> Float64(item["bytes"]), records; init = 0.0)
    limit = max(Int(top), 2)
    selected_records = length(records) <= limit ? records : copy(records[1:(limit - 1)])
    if length(records) > limit
        other_bytes = sum(item -> Float64(item["bytes"]), records[limit:end]; init = 0.0)
        push!(selected_records,
            Dict{String, Any}(
                "version" => selected, "file" => "other", "line" => 0,
                "label" => "Other allocation sites", "bytes" => other_bytes))
    end
    for item in selected_records
        item["percentage"] = total == 0 ? 0.0 : 100 * Float64(item["bytes"]) / total
    end
    return selected_records, versions, selected
end

function _allocation_line_records(bundle, case_id; version = nothing, top::Integer = 40)
    grouped = Dict{Tuple{String, String, Int}, Float64}()
    for observation in _allocation_records(bundle, case_id)
        target = String(get(observation, "target_id", "unknown"))
        file = _short_source_path(String(observation["attributes"]["source_file"]))
        line = Int(get(observation["attributes"], "source_line", 0))
        key = (target, file, line)
        grouped[key] = get(grouped, key, 0.0) + Float64(observation["value"])
    end
    versions = unique!(String[first(key) for key in keys(grouped)])
    sort!(versions;
        by = _version_point_key ∘ (item -> Dict("version" => item,
            "target_kind" => startswith(item, "dev@") ? "dev" : "release")))
    selected = version === nothing ? (isempty(versions) ? "" : last(versions)) :
               String(version)
    records = [Dict{String, Any}("version" => target, "file" => file, "line" => line,
                   "label" => "$file:$line", "bytes" => bytes)
               for ((target, file, line), bytes) in grouped if target == selected]
    sort!(records; by = item -> (-Float64(item["bytes"]), String(item["label"])))
    resize!(records, min(length(records), max(Int(top), 1)))
    return records, versions, selected
end

function _allocation_heatmap_records(bundle, case_id; top::Integer = 40)
    grouped = Dict{Tuple{String, String}, Float64}()
    totals = Dict{String, Float64}()
    versions = String[]
    for observation in _allocation_records(bundle, case_id)
        version = String(get(observation, "target_id", "unknown"))
        file = _short_source_path(String(observation["attributes"]["source_file"]))
        line = Int(get(observation["attributes"], "source_line", 0))
        label = "$file:$line"
        grouped[(version, label)] = get(grouped, (version, label), 0.0) +
                                    Float64(observation["value"])
        totals[label] = get(totals, label, 0.0) + Float64(observation["value"])
        push!(versions, version)
    end
    unique!(versions)
    sort!(versions;
        by = item -> _version_point_key(Dict("version" => item,
            "target_kind" => startswith(item, "dev@") ? "dev" : "release")))
    labels = first.(first(sort!(collect(totals); by = item -> -last(item)),
        min(length(totals), max(Int(top), 1))))
    data = [Dict{String, Any}("version" => version, "label" => label,
                "bytes" => get(grouped, (version, label), 0.0))
            for label in labels for version in versions]
    return data, versions, labels
end

function _flame_records(observations; version = nothing, top::Integer = 40)
    versions = unique!(String[String(get(item, "target_id", "unknown"))
                              for item in observations])
    sort!(versions;
        by = item -> _version_point_key(Dict("version" => item,
            "target_kind" => startswith(item, "dev@") ? "dev" : "release")))
    selected = version === nothing ? (isempty(versions) ? "" : last(versions)) :
               String(version)
    grouped = Dict{Tuple{Vararg{String}}, Dict{String, Any}}()
    for observation in observations
        String(get(observation, "target_id", "unknown")) == selected || continue
        attributes = get(observation, "attributes", Dict())
        stack = get(attributes, "stack", nothing)
        stack isa AbstractVector || continue
        labels = Tuple(String.(stack))
        isempty(labels) && continue
        count = length(labels)
        vector_attribute(name, fallback) = begin
            values = get(attributes, name, nothing)
            values isa AbstractVector && length(values) == count ? collect(values) :
            fill(fallback, count)
        end
        runtime_dispatch = Bool.(vector_attribute("runtime_dispatch", false))
        gc_event = Bool.(vector_attribute("gc_event", false))
        inference_status = String.(vector_attribute("inference_status", "unknown"))
        inferred_return_type = String.(vector_attribute("inferred_return_type", ""))
        record = get!(grouped, labels) do
            Dict{String, Any}("value" => 0.0,
                "runtime_dispatch_value" => zeros(Float64, count),
                "gc_event_value" => zeros(Float64, count),
                "inference_status" => [Set{String}() for _ in 1:count],
                "inferred_return_type" => [Set{String}() for _ in 1:count])
        end
        value = Float64(observation["value"])
        record["value"] += value
        for index in eachindex(labels)
            runtime_dispatch[index] &&
                (record["runtime_dispatch_value"][index] += value)
            gc_event[index] && (record["gc_event_value"][index] += value)
            push!(record["inference_status"][index], inference_status[index])
            isempty(inferred_return_type[index]) ||
                push!(record["inferred_return_type"][index], inferred_return_type[index])
        end
    end
    stacks = sort!(collect(grouped); by = item -> -Float64(last(item)["value"]))
    resize!(stacks, min(length(stacks), max(Int(top), 1)))
    root = Dict{String, Any}("value" => 0.0,
        "children" => Dict{String, Any}())
    for (stack, stack_record) in stacks
        value = Float64(stack_record["value"])
        root["value"] += value
        node = root
        for (index, label) in pairs(stack)
            children = node["children"]
            child = get!(children, label) do
                Dict{String, Any}("value" => 0.0,
                    "runtime_dispatch_value" => 0.0, "gc_event_value" => 0.0,
                    "inference_status" => Set{String}(),
                    "inferred_return_type" => Set{String}(),
                    "children" => Dict{String, Any}())
            end
            child["value"] += value
            child["runtime_dispatch_value"] += stack_record["runtime_dispatch_value"][index]
            child["gc_event_value"] += stack_record["gc_event_value"][index]
            union!(child["inference_status"], stack_record["inference_status"][index])
            union!(child["inferred_return_type"],
                stack_record["inferred_return_type"][index])
            node = child
        end
    end
    total = Float64(root["value"])
    records = Dict{String, Any}[]
    function visit(children, depth, start, path)
        cursor = start
        ordered = sort!(collect(children); by = item -> -Float64(last(item)["value"]))
        for (label, child) in ordered
            width = total == 0 ? 0.0 : Float64(child["value"]) / total
            child_path = [path; String(label)]
            value = Float64(child["value"])
            runtime_dispatch_value = Float64(child["runtime_dispatch_value"])
            gc_event_value = Float64(child["gc_event_value"])
            inference_status = sort!(collect(child["inference_status"]))
            inferred_return_type = sort!(collect(child["inferred_return_type"]))
            inference_warning = any(status -> status in ("any", "union", "abstract"),
                inference_status)
            status = runtime_dispatch_value > 0 ? "runtime_dispatch" :
                     inference_warning ? "inference_warning" :
                     gc_event_value > 0 ? "gc_event" : "normal"
            push!(records,
                Dict{String, Any}(
                    "label" => String(label), "path" => child_path,
                    "depth" => depth, "x0" => cursor, "x1" => cursor + width,
                    "value" => value,
                    "percentage" => total == 0 ? 0.0 : 100 * value / total,
                    "status" => status,
                    "runtime_dispatch_value" => runtime_dispatch_value,
                    "runtime_dispatch_percentage" =>
                        value == 0 ? 0.0 :
                        100 * runtime_dispatch_value / value,
                    "gc_event_value" => gc_event_value,
                    "gc_event_percentage" =>
                        value == 0 ? 0.0 :
                        100 * gc_event_value / value,
                    "inference_status" => inference_status,
                    "inferred_return_type" => inferred_return_type))
            visit(child["children"], depth + 1, cursor, child_path)
            cursor += width
        end
    end
    visit(root["children"], 1, 0.0, String[])
    return records, versions, selected, total
end

function _tradeoff_records(bundle, entry)
    matching = [series
                for series in suite_version_series(bundle)
                if series["package"] == entry["package"] &&
                       series["feature"] == entry["feature"] &&
                       _plot_base_comparison_key(series) == entry["comparison_key"]]
    time = only(filter(series -> series["metric"] == "julia.wall.time", matching))
    bytes = only(filter(series -> series["metric"] == "julia.alloc.bytes", matching))
    times = Dict(String(point["version"]) => point for point in time["points"])
    allocations = Dict(String(point["version"]) => point for point in bytes["points"])
    versions = sort!(collect(intersect(keys(times), keys(allocations)));
        by = item -> _version_point_key(times[item]))
    return [Dict{String, Any}("version" => version,
                "target_kind" => times[version]["target_kind"],
                "time" => times[version]["median"], "bytes" =>
                    allocations[version]["median"])
            for version in versions]
end

"Build one backend-neutral plot payload from a bundle and catalog identifier."
function performance_plot(bundle::RunBundle, id::AbstractString; version = nothing,
        top::Integer = 40)
    entry = _catalog_entry(bundle, id)
    kind = Symbol(entry["kind"])
    data = Dict{String, Any}[]
    encoding = Dict{String, Any}()
    options = Dict{String, Any}("package" => get(entry, "package", ""),
        "feature" => get(entry, "feature", ""), "unit" => get(entry, "unit", ""))
    description = String(entry["label"])
    if kind in (:version_series, :distribution, :version_delta)
        series = _series_by_id(bundle, entry["series_id"])
        options["series_id"] = series["series_id"]
        options["metric"] = series["metric"]
        data = kind === :version_series ? _version_records(series) :
               kind === :distribution ? _distribution_records(bundle, series) :
               _delta_records(bundle, series)
        encoding = kind === :version_delta ?
                   Dict(
            "x" => "candidate_version", "y" => "relative_delta", "color" => "status") :
                   Dict("x" => "version", "y" => "value", "color" => "target_kind")
    elseif kind === :allocation_pie
        data, versions, selected = _allocation_pie_records(bundle, entry["case_id"];
            version, top)
        options["versions"] = versions
        options["selected_version"] = selected
        options["top"] = Int(top)
        encoding = Dict("theta" => "bytes", "color" => "label", "label" => "percentage")
    elseif kind === :allocation_files
        data = _allocation_file_records(bundle, entry["case_id"])
        encoding = Dict("x" => "version", "y" => "bytes", "color" => "file")
    elseif kind === :allocation_lines
        data, versions, selected = _allocation_line_records(bundle, entry["case_id"];
            version, top)
        options["versions"] = versions
        options["selected_version"] = selected
        options["top"] = Int(top)
        encoding = Dict("x" => "label", "y" => "bytes", "color" => "file")
    elseif kind === :allocation_heatmap
        data, versions, labels = _allocation_heatmap_records(bundle, entry["case_id"]; top)
        options["versions"] = versions
        options["labels"] = labels
        options["top"] = Int(top)
        encoding = Dict("x" => "version", "y" => "label", "color" => "bytes")
    elseif kind === :allocation_flamegraph
        observations = _allocation_records(bundle, entry["case_id"])
        data, versions, selected, total = _flame_records(observations; version, top)
        options["versions"] = versions
        options["selected_version"] = selected
        options["top"] = Int(top)
        options["total"] = total
        options["value_label"] = "allocated bytes"
        encoding = Dict("x" => "percentage", "y" => "depth", "color" => "status")
    elseif kind === :cpu_flamegraph
        observations = [observation
                        for observation in bundle.observations
                        if get(observation, "case_id", "") == entry["case_id"] &&
            get(observation, "measurement_definition", "") ==
            "julia.cpu.samples/profile-v1"]
        data, versions, selected, total = _flame_records(observations; version, top)
        options["versions"] = versions
        options["selected_version"] = selected
        options["top"] = Int(top)
        options["total"] = total
        options["value_label"] = "CPU samples"
        options["diagnostic_semantics"] = "runtime dispatch and cached Julia inference metadata"
        encoding = Dict("x" => "percentage", "y" => "depth", "color" => "status")
    elseif kind === :wall_flamegraph
        observations = [observation
                        for observation in bundle.observations
                        if get(observation, "case_id", "") == entry["case_id"] &&
            get(observation, "measurement_definition", "") ==
            "julia.wall.samples/profile-walltime-v1"]
        data, versions, selected, total = _flame_records(observations; version, top)
        options["versions"] = versions
        options["selected_version"] = selected
        options["top"] = Int(top)
        options["total"] = total
        options["value_label"] = "wall-time task samples"
        options["diagnostic_semantics"] = "runtime dispatch and cached Julia inference metadata"
        encoding = Dict("x" => "percentage", "y" => "depth", "color" => "status")
    elseif kind === :time_allocation_tradeoff
        data = _tradeoff_records(bundle, entry)
        encoding = Dict("x" => "bytes", "y" => "time", "label" => "version")
    else
        throw(ArgumentError("unsupported performance plot kind $kind"))
    end
    return PerformancePlot(String(entry["id"]), kind, String(entry["title"]),
        description, encoding, data, options)
end

"Extension point implemented by MakieExt."
function performance_figure end

"Extension point implemented by WGLMakieExt."
function performance_plot_html end

@testitem "Performance plot grammar" tags=[:unit, :plots] begin
    using PerfChecker

    definitions = [Dict{String, Any}("id" => "julia.wall.time/benchmarktools-v1",
        "metric" => "julia.wall.time", "unit" => "s")]
    observations = [Dict{String, Any}(
                        "case_id" => "demo/Demo/parse", "target_id" => version,
                        "comparison_key" => "parse/v1::julia.wall.time/benchmarktools-v1",
                        "metric" => "julia.wall.time", "measurement_definition" => "julia.wall.time/benchmarktools-v1",
                        "value" => value, "unit" => "s",
                        "attributes" => Dict("package" => "Demo", "feature" => "parse",
                            "version" => version, "target_kind" => kind))
                    for (version, kind, value) in (("1.0.0", "release", 1.0),
        ("1.1.0", "release", 0.8),
        ("dev@1.2.0", "dev", 0.7))]
    bundle = RunBundle(
        Dict{String, Any}("run_id" => "plot-run", "suite" => "demo",
            "state" => "complete"),
        definitions, observations,
        Dict{String, Any}[], Dict{String, Any}[])
    catalog = plot_catalog(bundle)
    @test length(catalog) == 3
    trajectory = only(filter(item -> item["kind"] == "version_series", catalog))
    plot = performance_plot(bundle, trajectory["id"])
    @test performance_plot_dict(plot)["schema_version"] == "perfchecker-plot/1"
    @test length(plot.data) == 3
end

@testitem "Allocation plot grammar" tags=[:unit, :plots, :allocations] begin
    using PerfChecker

    definition = Dict{String, Any}(
        "id" => "julia.alloc.bytes/line-tracking-v1",
        "metric" => "julia.alloc.bytes", "unit" => "By")
    observations = Dict{String, Any}[]
    for (version, kind) in (("1.0.0", "release"), ("dev@1.1.0", "dev"))
        for (file, line, bytes) in (("src/parse.jl", 10, 100.0),
            ("src/parse.jl", 20, 40.0),
            ("src/model.jl", 8, 20.0))
            push!(observations,
                Dict{String, Any}(
                    "case_id" => "demo/Demo/parse_allocations", "target_id" => version,
                    "comparison_key" => "parse/v1::julia.alloc.bytes/line-tracking-v1",
                    "metric" => "julia.alloc.bytes", "measurement_definition" => "julia.alloc.bytes/line-tracking-v1",
                    "value" => bytes,
                    "unit" => "By", "attributes" => Dict{String, Any}(
                        "package" => "Demo", "feature" => "parse_allocations",
                        "version" => version, "target_kind" => kind,
                        "source_file" => file, "source_line" => line,
                        "stack" => ["parse (src/parse.jl:1)", "$file:$line"])))
        end
    end
    bundle = RunBundle(
        Dict{String, Any}("run_id" => "allocation-plot-run",
            "suite" => "demo", "state" => "complete"),
        [definition],
        observations,
        Dict{String, Any}[], Dict{String, Any}[])
    catalog = plot_catalog(bundle)
    allocation = filter(item -> startswith(item["kind"], "allocation_"), catalog)
    @test Set(item["kind"] for item in allocation) == Set(("allocation_pie",
        "allocation_files", "allocation_lines", "allocation_heatmap",
        "allocation_flamegraph"))
    plots = Dict(item["kind"] => performance_plot(bundle, item["id"])
    for item in allocation)
    @test length(plots["allocation_files"].data) == 4
    @test sum(item["percentage"] for item in plots["allocation_pie"].data) ≈ 100
    @test plots["allocation_lines"].options["selected_version"] == "dev@1.1.0"
    @test length(plots["allocation_lines"].data) == 3
    @test plots["allocation_heatmap"].options["versions"] ==
          ["1.0.0", "dev@1.1.0"]
    @test !isempty(plots["allocation_flamegraph"].data)
    series = only(filter(item -> item["kind"] == "version_series", catalog))
    @test performance_plot(bundle, series["id"]).data[1]["value"] == 160.0
end

@testitem "CPU flame graph grammar" tags=[:unit, :plots, :profile, :flamegraph] begin
    using PerfChecker

    definition = Dict{String, Any}("id" => "julia.cpu.samples/profile-v1",
        "metric" => "julia.cpu.samples", "unit" => "1")
    observations = [Dict{String, Any}(
                        "case_id" => "demo/Demo/parse_profile", "target_id" => "dev@1.1.0",
                        "comparison_key" => "parse/v1::julia.cpu.samples/profile-v1",
                        "metric" => "julia.cpu.samples", "measurement_definition" => "julia.cpu.samples/profile-v1",
                        "value" => samples, "unit" => "1",
                        "attributes" => Dict{String, Any}(
                            "package" => "Demo", "feature" => "parse_profile",
                            "version" => "dev@1.1.0", "target_kind" => "dev",
                            "source_file" => "src/parse.jl", "source_line" => 10,
                            "stack" => stack, "runtime_dispatch" => dispatch,
                            "gc_event" => gc, "inference_status" => inference,
                            "inferred_return_type" => return_types))
                    for (samples, stack, dispatch, gc, inference, return_types) in (
        (8, ["parse", "tokenize"], [false, true], [false, false],
        ["concrete", "union"], ["Nothing", "Union{String, Nothing}"]),
        (2, ["parse", "normalize"], [false, false], [false, false],
        ["concrete", "abstract"], ["Nothing", "AbstractString"]),
        (1, ["parse", "cleanup"], [false, false], [false, true],
        ["concrete", "concrete"], ["Nothing", "Nothing"]))]
    bundle = RunBundle(
        Dict{String, Any}("run_id" => "profile-plot-run",
            "suite" => "demo", "state" => "complete"),
        [definition],
        observations,
        Dict{String, Any}[], Dict{String, Any}[])
    entry = only(filter(item -> item["kind"] == "cpu_flamegraph",
        plot_catalog(bundle)))
    plot = performance_plot(bundle, entry["id"])
    @test plot.options["total"] == 11
    @test plot.options["selected_version"] == "dev@1.1.0"
    root = only(filter(item -> item["depth"] == 1, plot.data))
    @test root["label"] == "parse"
    @test root["percentage"] == 100
    tokenize = only(filter(item -> item["label"] == "tokenize", plot.data))
    @test tokenize["status"] == "runtime_dispatch"
    @test tokenize["runtime_dispatch_value"] == 8
    @test tokenize["runtime_dispatch_percentage"] == 100
    @test tokenize["inference_status"] == ["union"]
    @test tokenize["inferred_return_type"] == ["Union{String, Nothing}"]
    normalize = only(filter(item -> item["label"] == "normalize", plot.data))
    @test normalize["status"] == "inference_warning"
    cleanup = only(filter(item -> item["label"] == "cleanup", plot.data))
    @test cleanup["status"] == "gc_event"
end
