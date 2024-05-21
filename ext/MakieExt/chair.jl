function PerfChecker.checkres_to_scatterlines(
        x::PerfChecker.CheckerResult, ::Val{:chairmark})
    println("Hello!")
    @warn "Here!"
end

function PerfChecker.checkres_to_boxplots(
        x::PerfChecker.CheckerResult, ::Val{:chairmark}; kwarg::Symbol = :times)
    di = Dict()
    datax, datay = [], []
    
    for i in eachindex(x.tables)
        j = x.tables[i]
        p = x.pkgs[i]
        g = map(TypedTables.GetProperty{kwarg}(), j)
        append!(datax, fill(i, length(g)))
        append!(datay, g)
    end

    versionnums = [x.pkgs[i].version for i in eachindex(x.pkgs)]
    f = Figure()
    ax = f[1,1] = Axis(f)
    ax.xticks = (eachindex(versionnums), string.(versionnums))
    ax.xlabel = "versions"
    ax.ylabel = string(kwarg)
    boxplot!(datax, datay, label=string(kwarg))
    axislegend()
    return f
end
