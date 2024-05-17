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
