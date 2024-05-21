function __init__()
	# If the UUID is not set in the environment ...
	if !haskey(ENV, "PERFCHECKER_UUID")
		@info "PERFCHECKER_UUID not set in the environment. Looking for it ..."
		# ... read it from the file ...
		path = joinpath(Base.Sys.DEPOT_PATH[1], "perfchecker", "uuid")
		ENV["PERFCHECKER_UUID"] = if isfile(path)
			@info "... found it in $path."
			UUID(read(path, UInt128))
		else # or generate a new one and write it to the file
			u = uuid4()
			str = """
				... not found. Generating a new one and writing it to $path.
				Please set it in the environment, `ENV["PerfChecker_UUID"] = "your_UUID"`, if you want to use a specific one.
				\t`PerfChecker.get_uuid()`: $u
			"""
			@warn str
			mkpath(dirname(path))
			open(path, "w") do f
				write(f, u.value)
			end
			u
		end
	end
end
