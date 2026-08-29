module DocumenterExt

using Documenter
using PerfChecker

function PerfChecker.documenter_page(bundle::PerfChecker.RunBundle,
        destination::AbstractString; title::AbstractString = "Performance")
    target = abspath(String(destination))
    mkpath(dirname(target))
    comparison = PerfChecker.compare_suite_versions(bundle)
    temporary = tempname()
    PerfChecker.write_version_comparison_markdown(comparison, temporary)
    body = read(temporary, String)
    rm(temporary; force = true)
    open(target, "w") do io
        println(io, "# ", title, "\n")
        println(io, body)
        println(io, "\n## Interactive artifacts\n")
        println(io,
            "The PerfChecker Studio, Speedscope, folded stacks, and PProf exports are generated from the same versioned run bundle.")
    end
    return target
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
