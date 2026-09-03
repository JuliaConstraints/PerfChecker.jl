using Documenter, DocumenterVitepress

using PerfChecker

makedocs(;
    modules = [PerfChecker],
    authors = "Mirage Interactive and contributors",
    repo = "https://github.com/Mirage-Interactive-Fr/PerfChecker.jl",
    sitename = "PerfChecker.jl",
    format = DocumenterVitepress.MarkdownVitepress(
        repo = "https://github.com/Mirage-Interactive-Fr/PerfChecker.jl",
        devurl = "dev",
        deploy_url = "https://mirage-interactive-fr.github.io/PerfChecker.jl/",
        description = "Deep, reproducible performance testing for Julia packages and software suites"
    ),
    checkdocs = :exports,
    pages = [
        "Home" => "index.md",
        "Get started" => [
            "Overview" => "guide/overview.md",
            "Installation" => "guide/installation.md",
            "Your first check" => "guide/first-check.md"
        ],
        "Suites and comparisons" => [
            "Software suites" => "software-suites.md",
            "Measurement model" => "measurement-model.md",
            "Compare versions and revisions" => "tutorials/comparisons.md",
            "Bibliography walkthrough" => "tutorials/bibliography.md"
        ],
        "Measurements" => [
            "Check catalog" => "reference/checks.md",
            "Network measurement" => "network-measurement.md",
            "Julia RC and nightly" => "tutorials/julia-runtimes.md",
            "Native and external dependencies" => "reference/native-external.md"
        ],
        "Interfaces" => [
            "VS Code" => "interfaces/vscode.md",
            "Oxygen web studio" => "interfaces/web-studio.md",
            "REPL and Pluto" => "interfaces/repl-pluto.md",
            "Makie and interactive plots" => "interfaces/visualization.md",
            "Documenter integration" => "interfaces/documentation.md"
        ],
        "Automation and hosting" => [
            "CI/CD" => "tutorials/ci.md",
            "Hosted controller and agents" => "operations/hosted.md"
        ],
        "Contracts and API" => [
            "Run bundles" => "reference/run-bundles.md",
            "Queries and documentation blocks" => "report-queries.md",
            "Command line" => "reference/cli.md",
            "Extensions and providers" => "reference/extensions.md",
            "Julia API" => "reference/api.md"
        ],
        "Project" => [
            "V1 candidate" => "v1-candidate.md",
            "Architecture roadmap" => "architecture-roadmap.md",
            "Documentation guide" => "contributing/documentation.md"
        ]
    ],
    warnonly = true
)

deploydocs(;
    repo = "github.com/Mirage-Interactive-Fr/PerfChecker.jl",
    push_preview = true
)
