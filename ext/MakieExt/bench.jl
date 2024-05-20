function PerfChecker.checkres_to_scatterlines(
        x::PerfChecker.CheckerResult, ::Val{:benchmark})
    println("Hello!")
    @warn "Here!"
end

function PerfChecker.checkres_to_boxplots(
        x::PerfChecker.CheckerResult, ::Val{:benchmark}; kwarg = :times)
    di = Dict()
    data = []
    #for i in eachindex(x.tables)
    #j = x.tables[i]
    #p = x.pkgs[i]
    #g = getproperties(j[i], (kwargs,))
    #g = [g[k][1] for k in eachindex(g)]
    #push!((fill(i, length(g)), g))
    #end

    #=
    w = getproperties(j[1], (:allocs,))
    versions = Dict()
    for i in eachindex(x.pkgs)
    versions[x.pkgs[i].version] = i
    end

    versionnums = [x.pkgs[i].version for i in eachindex(x.pkgs)] 
    f = Figure()
    ax = Axis(f[1, 1])
    ax.xticks = (eachindex(versionnums), string.(versionnums))
    ax.xlabel = "versions"
    ax.ylabel = "bytes"
    colors = make_colors(length(keys(di)))
    i = 1
    for (keys, values) in di
    xs = [values[i][1] for i in eachindex(values)]
    ys = [versions[values[i][2]] for i in eachindex(values)]
    scatterlines!(f[1,1], ys, xs, label = keys, color = (colors[i], 0.6)); i += 1
    end
    ax.title = x.pkgs[1].name
    Legend(f[1,2], ax)
    return f
    =#
    return data
end
