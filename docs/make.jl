using Documenter, DocumenterVitepress

using PerfChecker

makedocs(;
    modules = [PerfChecker],
    authors = "azzaare <jf@baffier.fr>",
    repo = "https://github.com/JuliaConstraints/PerfChecker.jl",
    sitename = "PerfChecker.jl",
    format = DocumenterVitepress.MarkdownVitepress(
        repo = "https://github.com/JuliaConstraints/PerfChecker.jl",
    ),
    pages = [
        "Home" => "index.md",
        "V1 candidate" => "v1-candidate.md",
        "Software suites" => "software-suites.md",
        "Measurement model" => "measurement-model.md",
        "Network measurement" => "network-measurement.md",
        "Report queries" => "report-queries.md",
        "Architecture roadmap" => "architecture-roadmap.md"
    ],
    warnonly = true
)

deploydocs(;
    repo = "github.com/JuliaConstraints/PerfChecker.jl",
    push_preview = true
)
