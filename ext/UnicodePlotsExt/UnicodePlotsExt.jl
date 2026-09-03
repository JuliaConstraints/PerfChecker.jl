module UnicodePlotsExt

using PerfChecker
using UnicodePlots

_short_label(value; width = 34) = first(String(value), min(length(String(value)), width))

function _bar_plot(plot::PerfChecker.PerformancePlot, label_key::String,
        value_key::String; width::Integer, height::Integer, scale::Float64 = 1.0,
        suffix::String = "")
    records = filter(item -> get(item, value_key, nothing) isa Number, plot.data)
    isempty(records) && throw(ArgumentError("performance plot has no numeric data"))
    labels = [_short_label(get(item, label_key, "item")) for item in records]
    values = [Float64(item[value_key]) * scale for item in records]
    title = isempty(suffix) ? plot.title : "$(plot.title) ($suffix)"
    return UnicodePlots.barplot(labels, values; title, width, height)
end

"Render the common performance-plot grammar directly in a text terminal."
function PerfChecker.terminal_plot(plot::PerfChecker.PerformancePlot;
        width::Integer = 80, height::Integer = 20)
    isempty(plot.data) && throw(ArgumentError("performance plot has no data"))
    if plot.kind === :version_series
        labels = String[String(item["version"]) for item in plot.data]
        values = Float64[Float64(item["value"]) for item in plot.data]
        return UnicodePlots.lineplot(collect(eachindex(values)), values;
            title = plot.title,
            xlabel = "versions: $(first(labels)) … $(last(labels))",
            ylabel = String(get(plot.options, "unit", "")), width, height,
            name = "median")
    elseif plot.kind === :version_delta
        records = filter(item -> get(item, "relative_delta", nothing) isa Number,
            plot.data)
        adapted = PerfChecker.PerformancePlot(plot.id, plot.kind, plot.title,
            plot.description, plot.encoding,
            [merge(copy(item),
                 Dict("delta_percent" => 100 * Float64(item["relative_delta"])))
             for item in records],
            plot.options)
        return _bar_plot(adapted, "candidate_version", "delta_percent";
            width, height, suffix = "%")
    elseif plot.kind === :distribution
        values = Float64[Float64(item["value"]) for item in plot.data]
        return UnicodePlots.histogram(values; title = plot.title, width, height)
    elseif plot.kind === :allocation_pie
        return _bar_plot(plot, "label", "percentage"; width, height, suffix = "%")
    elseif plot.kind === :allocation_files
        return _bar_plot(plot, "file", "bytes"; width, height, suffix = "bytes")
    elseif plot.kind === :allocation_lines
        return _bar_plot(plot, "label", "bytes"; width, height, suffix = "bytes")
    elseif plot.kind === :allocation_heatmap
        return _bar_plot(plot, "label", "bytes"; width, height, suffix = "bytes")
    elseif plot.kind in (:allocation_flamegraph, :cpu_flamegraph, :wall_flamegraph)
        records = filter(item -> Int(item["depth"]) == 1, plot.data)
        isempty(records) && (records = plot.data)
        adapted = PerfChecker.PerformancePlot(plot.id, plot.kind, plot.title,
            plot.description, plot.encoding, records, plot.options)
        return _bar_plot(adapted, "label", "percentage";
            width, height, suffix = "% inclusive")
    elseif plot.kind === :time_allocation_tradeoff
        x = Float64[Float64(item["bytes"]) for item in plot.data]
        y = Float64[Float64(item["time"]) for item in plot.data]
        return UnicodePlots.scatterplot(x, y; title = plot.title,
            xlabel = "allocated bytes", ylabel = "time (s)", width, height)
    end
    throw(ArgumentError("unsupported terminal plot kind $(plot.kind)"))
end

function PerfChecker.terminal_plot(comparison::PerfChecker.VersionComparison;
        series_id = nothing, width::Integer = 80, height::Integer = 20)
    isempty(comparison.series) && throw(ArgumentError("comparison has no series"))
    series = series_id === nothing ? first(comparison.series) :
             only(
        filter(item -> item["series_id"] == String(series_id), comparison.series))
    points = series["points"]
    isempty(points) && throw(ArgumentError("selected series has no points"))
    labels = String[String(point["version"]) for point in points]
    values = Float64[Float64(point["median"]) for point in points]
    title = "$(series["package"])/$(series["feature"]) — $(series["metric"])"
    plot = UnicodePlots.lineplot(collect(eachindex(values)), values; title,
        xlabel = "versions: $(first(labels)) … $(last(labels))",
        ylabel = String(series["unit"]), width, height, name = "median")
    return plot
end

function PerfChecker.terminal_plot(bundle::PerfChecker.RunBundle; plot_id = nothing,
        kind = nothing, version = nothing, top::Integer = 20,
        width::Integer = 80, height::Integer = 20)
    catalog = PerfChecker.plot_catalog(bundle)
    isempty(catalog) && throw(ArgumentError("run bundle exposes no performance plots"))
    entries = kind === nothing ? catalog :
              filter(item -> item["kind"] == string(kind), catalog)
    isempty(entries) && throw(ArgumentError("no terminal plot matches kind $kind"))
    entry = plot_id === nothing ? first(entries) :
            only(
        filter(item -> item["id"] == String(plot_id), entries))
    plot = PerfChecker.performance_plot(bundle, entry["id"]; version, top)
    return PerfChecker.terminal_plot(plot; width, height)
end

end
