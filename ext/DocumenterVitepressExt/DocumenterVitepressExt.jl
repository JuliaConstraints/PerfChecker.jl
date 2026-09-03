module DocumenterVitepressExt

using Documenter
using DocumenterVitepress
using PerfChecker

function PerfChecker.documenter_vitepress_makedocs(bundle;
        repo::AbstractString, devbranch::AbstractString = "main",
        devurl::AbstractString = "dev", deploy_url = nothing, kwargs...)
    format_options = Dict{Symbol, Any}(:repo => String(repo),
        :devbranch => String(devbranch), :devurl => String(devurl))
    deploy_url === nothing || (format_options[:deploy_url] = String(deploy_url))
    format = DocumenterVitepress.MarkdownVitepress(; format_options...)
    return PerfChecker.documenter_makedocs(bundle; format, kwargs...)
end

end
