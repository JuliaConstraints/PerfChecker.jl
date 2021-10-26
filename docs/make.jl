using PerfChecker
using Documenter

DocMeta.setdocmeta!(PerfChecker, :DocTestSetup, :(using PerfChecker); recursive=true)

makedocs(;
    modules=[PerfChecker],
    authors="Azzaare <jf@baffier.fr>",
    repo="https://github.com/JuliaConstraints/PerfChecker.jl/blob/{commit}{path}#{line}",
    sitename="PerfChecker.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://JuliaConstraints.github.io/PerfChecker.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/JuliaConstraints/PerfChecker.jl",
    devbranch="main",
)
