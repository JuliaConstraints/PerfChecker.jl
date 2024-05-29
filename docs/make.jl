using Documenter, DocumenterVitepress

using PerfChecker

makedocs(;
    modules = [PerfChecker],
    authors = "azzaare <jf@baffier.fr>",
    repo = "https://github.com/JuliaConstraints/PerfChecker.jl",
    sitename = "PerfChecker.jl",
    format = DocumenterVitepress.MarkdownVitepress(
        repo = "https://github.com/JuliaConstraints/PerfChecker.jl",
        devurl = "dev",
        deploy_url = "JuliaConstraints.github.io/PerfChecker.jl"
    ),
    pages = [
        "Home" => "index.md"
    ],
    warnonly = true
)

deploydocs(;
    repo = "github.com/JuliaConstraints/PerfChecker.jl",
    push_preview = true
)
