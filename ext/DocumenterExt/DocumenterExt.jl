module DocumenterExt

using Documenter
using PerfChecker

function PerfChecker.documenter_page(bundle::PerfChecker.RunBundle,
        destination::AbstractString; title::AbstractString = "Performance",
        blocks::AbstractVector{<:PerfChecker.PerformanceDocumentBlock} =
        PerfChecker.PerformanceDocumentBlock[], config = nothing)
    selected_blocks = config === nothing ? blocks :
                      PerfChecker.read_document_blocks(String(config))
    target = abspath(String(destination))
    mkpath(dirname(target))
    open(target, "w") do io
        println(io, "# ", title, "\n")
        if isempty(selected_blocks)
            comparison = PerfChecker.compare_suite_versions(bundle)
            temporary = tempname()
            try
                PerfChecker.write_version_comparison_markdown(comparison, temporary)
                println(io, read(temporary, String))
            finally
                rm(temporary; force = true)
            end
            println(io, "\n## Interactive artifacts\n")
            println(io,
                "The PerfChecker Studio, Speedscope, folded stacks, and PProf exports are generated from the same versioned run bundle.")
        else
            for block in selected_blocks
                _write_document_block(io, bundle, block)
            end
        end
    end
    return target
end

_md(value) = replace(string(value), '|' => "\\|", '\n' => " ", '\r' => " ")

function _write_table(io, records, columns)
    isempty(records) && return println(io, "_No matching evidence._\n")
    println(io, "| ", join(first.(columns), " | "), " |")
    println(io, "| ", join(fill("---", length(columns)), " | "), " |")
    for record in records
        println(
            io, "| ", join((_md(get(record, field, "")) for (_, field) in columns),
                " | "), " |")
    end
    println(io)
end

function _write_document_block(io, bundle, block)
    model = PerfChecker.performance_document_block(bundle, block)
    result = model["result"]
    provenance = model["provenance"]
    println(io, "## ", block.title, "\n")
    println(io, "Run `", _md(provenance["run_id"]), "` · evidence `",
        _md(provenance["evidence"]), "` · runtime `",
        _md(get(provenance["runtime"], "version", "unknown")), "`\n")
    block.interactive_url === nothing || println(io,
        "[Open the interactive PerfChecker view](", block.interactive_url, ")\n")
    :comparison in block.views && begin
        println(io, "### Comparisons\n")
        _write_table(io,
            result["comparison"],
            [
                "Case" => "case_id", "Metric" => "metric", "Status" => "status",
                "Baseline" => "baseline_median", "Candidate" => "candidate_median",
                "Delta" => "relative_delta"])
    end
    :observations in block.views && begin
        println(io, "### Observations\n")
        _write_table(io,
            result["observations"],
            [
                "Case" => "case_id", "Target" => "target_id", "Metric" => "metric",
                "Value" => "value", "Unit" => "unit"])
    end
    :diagnostics in block.views && begin
        println(io, "### Diagnostics\n")
        _write_table(io, result["diagnostics"],
            [
                "Rule" => "rule_id", "Severity" => "severity", "Message" => "message"])
    end
    :plots in block.views && begin
        println(io, "### Interactive plots\n")
        if isempty(result["plots"])
            println(io, "_No matching plot._\n")
        else
            for plot in result["plots"]
                println(io, "- `", _md(plot["id"]), "` — ", _md(plot["label"]))
            end
            println(io)
        end
    end
    :artifacts in block.views && begin
        println(io, "### Artifacts\n")
        _write_table(io,
            result["artifacts"],
            [
                "Role" => "role", "Media type" => "media_type",
                "Path" => "relative_path", "Digest" => "sha256"])
    end
end

function PerfChecker.documenter_page(result::PerfChecker.SoftwareSuiteResult,
        destination::AbstractString; kwargs...)
    return PerfChecker.documenter_page(PerfChecker._suite_run_bundle(result),
        destination; kwargs...)
end

function PerfChecker.documenter_makedocs(bundle;
        root::AbstractString = pwd(), source::AbstractString = "src",
        build::AbstractString = "build", page::AbstractString = "performance.md",
        sitename::AbstractString = "Performance", format = Documenter.HTML(), kwargs...)
    source_root = joinpath(String(root), String(source))
    PerfChecker.documenter_page(bundle, joinpath(source_root, String(page));
        title = sitename)
    options = Dict{Symbol, Any}(pairs(kwargs))
    get!(options, :remotes, nothing)
    get!(options, :pages, ["Performance" => String(page)])
    return Documenter.makedocs(; root = String(root), source = String(source),
        build = String(build), sitename = String(sitename), format, options...)
end

end
