function filename(d::Dict; extension = "")
	p = d[:pkgs]
	versions = join(map(x -> "v" * x, p[3]), "-")
	return join([p[1], versions, extension][1:(end - isempty(extension))], "_")
end

function get_uuid()
	path = joinpath(Base.Sys.DEPOT_PATH[1], "perfchecker", "uuid")
	if isfile(path)
		return read(path, String)
	else
		u = UUIDs.uuid4()
		write(path, u)
		return u
	end
end

# const UUID =
