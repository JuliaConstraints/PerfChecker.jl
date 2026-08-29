function _performance_figure(title::AbstractString; size = (1100, 620))
    figure = Figure(; size, backgroundcolor = RGBf(0.96, 0.97, 0.99))
    axis = Axis(figure[1, 1]; title = String(title), backgroundcolor = :white,
        xgridcolor = (:gray, 0.16), ygridcolor = (:gray, 0.16))
    return figure, axis
end

function _empty_performance_figure(plot::PerfChecker.PerformancePlot)
    figure = Figure(; size = (900, 480), backgroundcolor = RGBf(0.96, 0.97, 0.99))
    Label(figure[1, 1], "No evidence available for\n$(plot.title)";
        fontsize = 24, color = RGBf(0.32, 0.38, 0.45))
    return figure
end

function _version_labels(data, field = "version")
    labels = unique!(String[String(item[field]) for item in data])
    return labels, Dict(label => index for (index, label) in pairs(labels))
end

function _add_inspector(figure)
    try
        DataInspector(figure)
    catch error
        @debug "Makie DataInspector is unavailable for this backend" exception=(
            error, catch_backtrace())
    end
    return figure
end

function _has_positive_range(values)
    !isempty(values) && all(>=(0), values) &&
        maximum(values) > minimum(values)
end

function _version_series_figure(plot)
    isempty(plot.data) && return _empty_performance_figure(plot)
    figure, axis = _performance_figure(plot.title)
    labels, index = _version_labels(plot.data)
    xs = [index[String(item["version"])] for item in plot.data]
    ys = Float64[item["value"] for item in plot.data]
    colors = [item["target_kind"] == "dev" ? RGBf(0.93, 0.43, 0.18) :
              RGBf(0.04, 0.52, 0.57) for item in plot.data]
    lines!(axis, xs, ys; color = RGBf(0.04, 0.52, 0.57), linewidth = 3)
    scatter!(axis, xs, ys; color = colors, markersize = 15, strokewidth = 2,
        strokecolor = :white, inspector_label = (self,
            index,
            position) -> "$(labels[index])\n$(round(position[2]; sigdigits = 5)) $(plot.options["unit"])")
    axis.xticks = (collect(eachindex(labels)), labels)
    axis.xticklabelrotation = pi / 4
    axis.xlabel = "package version"
    axis.ylabel = "$(plot.options["metric"]) ($(plot.options["unit"]))"
    _has_positive_range(ys) && (axis.yscale = Makie.pseudolog10)
    return _add_inspector(figure)
end

function _distribution_figure(plot)
    isempty(plot.data) && return _empty_performance_figure(plot)
    figure, axis = _performance_figure(plot.title)
    labels, index = _version_labels(plot.data)
    xs = [index[String(item["version"])] for item in plot.data]
    ys = Float64[item["value"] for item in plot.data]
    boxplot!(axis, xs, ys; color = (RGBf(0.04, 0.52, 0.57), 0.68),
        strokecolor = RGBf(0.02, 0.31, 0.35), show_outliers = true)
    scatter!(axis, xs, ys; color = (RGBf(0.08, 0.14, 0.24), 0.28), markersize = 4)
    axis.xticks = (collect(eachindex(labels)), labels)
    axis.xticklabelrotation = pi / 4
    axis.xlabel = "package version"
    axis.ylabel = "$(plot.options["metric"]) ($(plot.options["unit"]))"
    _has_positive_range(ys) && (axis.yscale = Makie.pseudolog10)
    return _add_inspector(figure)
end

function _delta_figure(plot)
    records = [item
               for item in plot.data if get(item, "relative_delta", nothing) isa Number]
    isempty(records) && return _empty_performance_figure(plot)
    figure, axis = _performance_figure(plot.title)
    labels = ["$(item["baseline_version"]) → $(item["candidate_version"])"
              for item in records]
    values = Float64[item["relative_delta"] * 100 for item in records]
    colors = [value > 0 ? RGBf(0.77, 0.16, 0.13) :
              value < 0 ?
              RGBf(0.05, 0.49, 0.25) : RGBf(0.36, 0.42, 0.50) for value in values]
    barplot!(axis, eachindex(values), values; color = colors, strokecolor = :white,
        strokewidth = 1)
    hlines!(axis, [0.0]; color = RGBf(0.08, 0.14, 0.24), linewidth = 2)
    axis.xticks = (collect(eachindex(labels)), labels)
    axis.xticklabelrotation = pi / 3
    axis.xlabel = "comparison"
    axis.ylabel = "relative change (%)"
    return _add_inspector(figure)
end

function _allocation_files_figure(plot)
    isempty(plot.data) && return _empty_performance_figure(plot)
    figure, axis = _performance_figure(plot.title; size = (1200, 650))
    versions, version_index = _version_labels(plot.data)
    files = sort!(unique!(String[String(item["file"]) for item in plot.data]))
    file_index = Dict(file => index for (index, file) in pairs(files))
    xs = [version_index[String(item["version"])] for item in plot.data]
    ys = Float64[item["bytes"] for item in plot.data]
    stacks = [file_index[String(item["file"])] for item in plot.data]
    colors = make_colors(length(files))
    barplot!(axis, xs, ys; stack = stacks, color = colors[stacks])
    axis.xticks = (collect(eachindex(versions)), versions)
    axis.xticklabelrotation = pi / 4
    axis.xlabel = "package version"
    axis.ylabel = "allocated bytes by source file"
    _has_positive_range(ys) && (axis.yscale = Makie.pseudolog10)
    Legend(figure[1, 2], [PolyElement(color = color) for color in colors], files;
        title = "source file", tellheight = false)
    return _add_inspector(figure)
end

function _allocation_pie_figure(plot)
    isempty(plot.data) && return _empty_performance_figure(plot)
    figure = Figure(; size = (1100, 650), backgroundcolor = RGBf(0.96, 0.97, 0.99))
    axis = Axis(figure[1, 1];
        title = "$(plot.title) · $(plot.options["selected_version"])",
        aspect = DataAspect(), backgroundcolor = :white)
    labels = String[String(item["label"]) for item in plot.data]
    values = Float64[item["bytes"] for item in plot.data]
    percentages = Float64[item["percentage"] for item in plot.data]
    colors = make_colors(length(labels))
    pie!(axis, values; color = colors, strokecolor = :white, strokewidth = 2)
    hidedecorations!(axis)
    hidespines!(axis)
    legend_labels = ["$(labels[index]) · $(round(percentages[index]; digits = 1))%"
                     for index in eachindex(labels)]
    Legend(figure[1, 2], [PolyElement(color = color) for color in colors], legend_labels;
        title = "allocation share", tellheight = false)
    return _add_inspector(figure)
end

function _allocation_lines_figure(plot)
    isempty(plot.data) && return _empty_performance_figure(plot)
    width = max(1100, 34 * length(plot.data))
    figure, axis = _performance_figure(
        "$(plot.title) · $(plot.options["selected_version"])"; size = (width, 650))
    labels = String[String(item["label"]) for item in plot.data]
    values = Float64[item["bytes"] for item in plot.data]
    files = String[String(item["file"]) for item in plot.data]
    unique_files = sort!(unique(files))
    palette = make_colors(length(unique_files))
    color_index = Dict(file => index for (index, file) in pairs(unique_files))
    colors = [palette[color_index[file]] for file in files]
    barplot!(axis, eachindex(values), values; color = colors)
    axis.xticks = (collect(eachindex(labels)), labels)
    axis.xticklabelrotation = pi / 2.7
    axis.xlabel = "source file and line"
    axis.ylabel = "allocated bytes"
    _has_positive_range(values) && (axis.yscale = Makie.pseudolog10)
    return _add_inspector(figure)
end

function _allocation_heatmap_figure(plot)
    isempty(plot.data) && return _empty_performance_figure(plot)
    versions = String.(plot.options["versions"])
    labels = String.(plot.options["labels"])
    version_index = Dict(version => index for (index, version) in pairs(versions))
    label_index = Dict(label => index for (index, label) in pairs(labels))
    matrix = zeros(Float64, length(versions), length(labels))
    for item in plot.data
        matrix[version_index[String(item["version"])], label_index[String(item["label"])]] = Float64(item["bytes"])
    end
    height = max(650, 20 * length(labels))
    figure, axis = _performance_figure(plot.title; size = (1250, height))
    heat = heatmap!(axis, eachindex(versions), eachindex(labels), matrix;
        colorscale = Makie.pseudolog10, colormap = :thermal)
    axis.xticks = (collect(eachindex(versions)), versions)
    axis.yticks = (collect(eachindex(labels)), labels)
    axis.xticklabelrotation = pi / 4
    axis.xlabel = "package version"
    axis.ylabel = "source file and line"
    Colorbar(figure[1, 2], heat; label = "allocated bytes")
    return _add_inspector(figure)
end

const _FLAME_STATUS_COLORS = Dict(
    "runtime_dispatch" => RGBf(0.78, 0.08, 0.19),
    "inference_warning" => RGBf(0.46, 0.20, 0.72),
    "gc_event" => RGBf(0.95, 0.50, 0.08))

function _flame_tooltip(item, plot)
    value_label = String(plot.options["value_label"])
    lines = String[
        "Frame: $(item["label"])",
        "Path: $(join(item["path"], " → "))",
        "Share: $(round(Float64(item["percentage"]); digits = 3))%",
        "Weight: $(round(Float64(item["value"]); sigdigits = 6)) $value_label"]
    dispatch_value = Float64(get(item, "runtime_dispatch_value", 0.0))
    dispatch_percentage = Float64(get(item, "runtime_dispatch_percentage", 0.0))
    dispatch_value > 0 && push!(lines,
        "Runtime dispatch: $(round(dispatch_percentage; digits = 2))% ($(round(dispatch_value; sigdigits = 6)) $value_label)")
    gc_value = Float64(get(item, "gc_event_value", 0.0))
    gc_percentage = Float64(get(item, "gc_event_percentage", 0.0))
    gc_value > 0 && push!(lines,
        "Garbage collection: $(round(gc_percentage; digits = 2))% ($(round(gc_value; sigdigits = 6)) $value_label)")
    inference_status = String.(get(item, "inference_status", String[]))
    return_types = String.(get(item, "inferred_return_type", String[]))
    isempty(inference_status) || push!(lines,
        "Julia inference: $(join(inference_status, ", "))")
    isempty(return_types) || push!(lines,
        "Inferred return: $(join(return_types, " | "))")
    any(status -> status in ("any", "union", "abstract"), inference_status) &&
        push!(lines, "Inspect with @code_warntype or Cthulhu")
    return join(lines, '\n')
end

function _flame_legend!(figure, allocation_only)
    normal_color = RGBf(0.22, 0.66, 0.72)
    if allocation_only
        elements = [PolyElement(color = normal_color)]
        labels = ["sampled allocation frame"]
        note = "Width = share of allocated bytes.\nHover any frame for its full path."
    else
        statuses = ("normal", "runtime_dispatch", "inference_warning", "gc_event")
        colors = [normal_color;
                  [_FLAME_STATUS_COLORS[status] for status in statuses[2:end]]]
        elements = [PolyElement(color = color) for color in colors]
        labels = [
            "sampled Julia frame", "runtime dispatch", "non-concrete inferred return",
            "garbage collection"]
        note = "Red = observed dynamic dispatch.\nPurple = non-concrete inferred return.\nOrange = garbage collection.\nHover any frame for full diagnostics."
    end
    legend_grid = figure[1, 2] = GridLayout()
    Legend(legend_grid[1, 1], elements, labels;
        title = "frame diagnostics", tellheight = false)
    Label(legend_grid[2, 1], note;
        tellwidth = false, justification = :left, halign = :left,
        color = RGBf(0.30, 0.35, 0.42), fontsize = 12)
    return figure
end

function _flamegraph_figure(plot)
    isempty(plot.data) && return _empty_performance_figure(plot)
    maximum_depth = maximum(item -> Int(item["depth"]), plot.data)
    figure, axis = _performance_figure(
        "$(plot.title) · $(plot.options["selected_version"])";
        size = (1400, 620))
    labels = sort!(unique!(String[String(item["label"]) for item in plot.data]))
    palette = make_colors(length(labels))
    label_colors = Dict(label => palette[index] for (index, label) in pairs(labels))
    allocation_only = plot.kind === :allocation_flamegraph
    depths = Float64[Int(item["depth"]) for item in plot.data]
    starts = Float64[100 * Float64(item["x0"]) for item in plot.data]
    stops = Float64[100 * Float64(item["x1"]) for item in plot.data]
    rectangle_colors = [get(_FLAME_STATUS_COLORS, String(get(item, "status", "normal")),
                            label_colors[String(item["label"])])
                        for item in plot.data]
    barplot!(axis, depths, stops; fillto = starts, direction = :x,
        width = 0.84, gap = 0, color = rectangle_colors, strokecolor = :white,
        strokewidth = 0.8, inspectable = true,
        inspector_label = (self, index, position) -> _flame_tooltip(plot.data[index], plot))
    for item in plot.data
        x0 = 100 * Float64(item["x0"])
        width = 100 * (Float64(item["x1"]) - Float64(item["x0"]))
        width >= 7 || continue
        text!(axis, x0 + width / 2, Int(item["depth"]);
            text = String(item["label"]), align = (:center, :center), fontsize = 11,
            color = RGBf(0.04, 0.08, 0.13))
    end
    xlims!(axis, 0, 100)
    ylims!(axis, 0.4, maximum_depth + 0.6)
    axis.xlabel = "share of captured $(lowercase(String(plot.options["value_label"]))) (%)"
    axis.ylabel = "call stack depth"
    axis.xticks = 0:10:100
    _flame_legend!(figure, allocation_only)
    return _add_inspector(figure)
end

function _tradeoff_figure(plot)
    isempty(plot.data) && return _empty_performance_figure(plot)
    figure, axis = _performance_figure(plot.title)
    xs = Float64[item["bytes"] for item in plot.data]
    ys = Float64[item["time"] for item in plot.data]
    colors = 1:length(plot.data)
    scatterlines!(axis, xs, ys; color = colors, colormap = :viridis,
        markersize = 16, linewidth = 2)
    for (index, item) in pairs(plot.data)
        text!(axis, xs[index], ys[index]; text = String(item["version"]),
            align = (:left, :bottom), offset = (7, 5), fontsize = 12)
    end
    axis.xlabel = "allocated bytes"
    axis.ylabel = "wall time (s)"
    _has_positive_range(xs) && (axis.xscale = Makie.pseudolog10)
    _has_positive_range(ys) && (axis.yscale = Makie.pseudolog10)
    return _add_inspector(figure)
end

"Render the common PerfChecker plot grammar with the active Makie backend."
function PerfChecker.performance_figure(plot::PerfChecker.PerformancePlot)
    plot.kind === :version_series && return _version_series_figure(plot)
    plot.kind === :distribution && return _distribution_figure(plot)
    plot.kind === :version_delta && return _delta_figure(plot)
    plot.kind === :allocation_pie && return _allocation_pie_figure(plot)
    plot.kind === :allocation_files && return _allocation_files_figure(plot)
    plot.kind === :allocation_lines && return _allocation_lines_figure(plot)
    plot.kind === :allocation_heatmap && return _allocation_heatmap_figure(plot)
    plot.kind === :allocation_flamegraph && return _flamegraph_figure(plot)
    plot.kind === :cpu_flamegraph && return _flamegraph_figure(plot)
    plot.kind === :wall_flamegraph && return _flamegraph_figure(plot)
    plot.kind === :time_allocation_tradeoff && return _tradeoff_figure(plot)
    throw(ArgumentError("Makie does not support performance plot kind $(plot.kind)"))
end

function PerfChecker.performance_figure(bundle::PerfChecker.RunBundle,
        id::AbstractString; kwargs...)
    return PerfChecker.performance_figure(PerfChecker.performance_plot(
        bundle, id; kwargs...))
end
