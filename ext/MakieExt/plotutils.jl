function make_colors(l)
	Makie.distinguishable_colors(
		l, [Makie.RGB(1, 1, 1), Makie.RGB(0, 0, 0)], dropseed = true)
end

function smart_paths(paths)
	splitted_paths = map(splitpath ∘ normpath, paths)

	common = paths |> first |> dirname |> splitpath
	for path in splitted_paths
		to_pop = length(common)
		for name in Iterators.zip(common, path)
			name[1] == name[2] || break
			to_pop -= 1
		end
		foreach(_ -> pop!(common), 1:to_pop)
	end

	for path in splitted_paths
		foreach(_ -> popfirst!(path), 1:length(common))
	end

	return joinpath(common...), map(joinpath, splitted_paths)
end

function PerfChecker.table_to_pie(x::Table, ::Val{:alloc}; pkg_name = "")
	data = x.bytes
	@info data
	paths = smart_paths(x.filenames)[2] .* " — line " .* string.(x.linenumbers)
	percentage = data .* 100 ./ sum(data)
	@info percentage
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
end



function PerfChecker.checkres_to_scatterlines(x::PerfChecker.CheckerResult, ::Val{:alloc}; title = "")
	di = Dict()
	for i in eachindex(x.tables)
		j = x.tables[i]
		p = x.pkgs[i]
		u = unique(j.filenames)
		paths = smart_paths(u)[2]
		for k in eachindex(u)
			if haskey(di, paths[k])
				push!(di[paths[k]], (sum(j.bytes[j.filenames .== u[k]]), p.version))
			else
				di[paths[k]] = [(sum(j.bytes[j.filenames .== u[k]]), p.version)]
			end
		end
	end

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
	save("/var/home/varlad/uba.png", f)
	return f
end
