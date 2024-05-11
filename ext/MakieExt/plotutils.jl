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
