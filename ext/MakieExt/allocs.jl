function PerfChecker.table_to_pie(x::Table, ::Val{:alloc}; pkg_name = "")
    if !isempty(x.filenames)
        data = x.bytes
        paths = smart_paths(x.filenames)[2] .* " — line " .* string.(x.linenumbers)
        percentage = data .* 100 ./ sum(data)
        colors = make_colors(length(percentage))
        str = isempty(pkg_name) ? "" : " for $pkg_name"
        f, ax, _ = pie(
            data;
            axis = (autolimitaspect = 1,),
            color = colors,
            inner_radius = 2,
            radius = 4,
            strokecolor = :white,
            strokewidth = 5
        )
        ax.title = "Mallocs$str"
        hidedecorations!(ax)
        hidespines!(ax)
        Legend(f[1, 2], [PolyElement(color = c) for c in colors], paths)
        return f
    else
        @error "No allocations so can't plot!"
        return nothing
    end
end

function PerfChecker.checkres_to_pie(x::PerfChecker.CheckerResult, ::Val{:alloc})
    name(i) = x.pkgs[i].name * "_v" * string(x.pkgs[i].version)
    return map(
        i -> (name(i) => table_to_pie(x.tables[i], Val(:alloc), pkg_name = name(i))),
        eachindex(x.tables))
end

function PerfChecker.checkres_to_scatterlines(
        x::PerfChecker.CheckerResult, ::Val{:alloc}; title = "")
    di = Dict()
    for i in eachindex(x.tables)
        j = x.tables[i]
        p = x.pkgs[i]
        u = unique(j.filenames)
        if !isempty(u)
            paths = smart_paths(u)[2]
            for k in eachindex(u)
                if haskey(di, paths[k])
                    push!(di[paths[k]], (sum(j.bytes[j.filenames .== u[k]]), p.version))
                else
                    di[paths[k]] = [(sum(j.bytes[j.filenames .== u[k]]), p.version)]
                end
            end
        else
            @error "No allocations so can't plot!"
            return nothing
        end
    end
    versions = Dict()
    for i in eachindex(x.pkgs)
        versions[x.pkgs[i].version] = i
    end

    versionnums = [x.pkgs[i].version for i in eachindex(x.pkgs)]
    f = Figure()
    ax = Axis(f[1, 1])
    ax.yscale = Makie.pseudolog10
    ax.xticks = (eachindex(versionnums), string.(versionnums))
    ax.xlabel = "versions"
    ax.ylabel = "bytes"
    colors = make_colors(length(keys(di)))
    i = 1

    lx = length(versionnums)
    ly = length(keys(di))
    step = 0.02 * (lx - 1)
    diff = (1 - ly) * step / 2.0

    for (keys, values) in di
        ys = [values[i][1] for i in eachindex(values)]
        xs = [versions[values[i][2]] for i in eachindex(values)] .+ diff
        scatterlines!(f[1, 1], xs, ys, label = keys, color = (colors[i], 1.0))
        i += 1
        diff += step
    end
    ax.title = x.pkgs[1].name
    Legend(f[1, 2], ax)
    return f
end
