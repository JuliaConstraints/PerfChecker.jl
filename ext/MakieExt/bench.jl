function PerfChecker.checkres_to_scatterlines(
        x::PerfChecker.CheckerResult, ::Val{:benchmark})
    data = []
    props = TypedTables.columnnames(x.tables[1])
    for i in eachindex(x.tables)
        t = x.tables[i]
        m = [map(TypedTables.GetProperty{i}(), t) for i in props]
        g = minimum.(m)
        push!(data, g)
    end

    d = [[data[i][j] for i in eachindex(data)] for j in eachindex(data[1])]

    v = map(y -> filter(x -> x > 0, y), d)

    r = minimum.(d)

    versionnums = [x.pkgs[i].version for i in eachindex(x.pkgs)]

    f = Figure()
    ax = f[1, 1] = Axis(f)
    colors = make_colors(length(props))
    max = 2

    lx = length(versionnums)
    ly = length(data[1])
    step = 0.02 * (lx - 1)
    diff = (1 - ly) * step / 2.0

    for i in eachindex(data[1])
        xs = collect(eachindex(versionnums)) .+ diff
        ys = [isempty(v[i]) ? 0 : d[i][j] / r[i] for j in eachindex(d[i])]
        t = maximum(ys)
        if max < ϵ(t)
            max = ϵ(t)
        end
        scatterlines!(
            xs, ys; label = string(props[i]), color = (colors[i], 1.0), linewidth = 0.5)
        diff += step
    end
    ax.yscale = Makie.pseudolog10
    ax.xticks = (eachindex(versionnums), string.(versionnums))
    ax.xlabel = "versions"
    ax.ylabel = "ratio"
    ax.title = "Evolution for $(x.pkgs[1].name) (via BenchmarkTools.jl)"
    f[1, 2] = Legend(f, ax)
    return f
end

function PerfChecker.checkres_to_boxplots(
        x::PerfChecker.CheckerResult, ::Val{:benchmark}; kwarg::Symbol = :times)
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
    ax = f[1, 1] = Axis(f)
    ax.xticks = (eachindex(versionnums), string.(versionnums))
    ax.xlabel = "versions"
    ax.ylabel = string(kwarg)
    boxplot!(datax, datay, label = string(kwarg))
    ax.title = x.pkgs[1].name
    f[1, 2] = Legend(f, ax)
    return f
end
