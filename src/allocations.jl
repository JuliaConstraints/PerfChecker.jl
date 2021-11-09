function alloc_check(title, dependencies, targets, pre_alloc, alloc; path=pwd(), labeller=:version)
    @info "Tracking allocations: $title"

    # cd to path if valid
    isdir(path) && cd(path)

    # add a proc (id == p) that track allocations
    p = first(addprocs(1; exeflags=["--track-allocation=user", "--project=$path"]))

    @eval @everywhere $p using Pkg
    @eval @everywhere $p Pkg.instantiate()
    @eval @everywhere $p using Profile

    # @info read("Project.toml", String)
    # @warn read("Manifest.toml", String)

    for d in dependencies
        @eval @everywhere $p using $(Symbol(d))
    end

    @eval @everywhere $p $pre_alloc()
    @eval @everywhere $p Profile.clear_malloc_data()
    @eval @everywhere $p $alloc()

    rmprocs(p)

    myallocs = Coverage.analyze_malloc(map(dirname ∘ pathof ∘ eval, targets))

    for t in targets, d in walkdir(dirname(pathof(t))), f in d[end]
        splitext(f)[2] == ".mem" && rm(joinpath(d[1], f))
    end
    for d in walkdir(path), f in d[end]
        splitext(f)[2] == ".mem" && rm(joinpath(d[1], f))
    end

    # Make the allocations data readable through a dataframe
    df = DataFrame()
    df.bytes = map(a -> a.bytes, Iterators.reverse(myallocs))
    df.ratio = round.(df.bytes / sum(df.bytes) * 100; digits = 2)
    df.filename = map(a -> a.filename, Iterators.reverse(myallocs))
    df.linenumber = map(a -> a.linenumber, Iterators.reverse(myallocs))

    # Save it as a CSV file
    label = ""
    if labeller == :oid
        label = oid2string(map(p -> joinpath(dirname(pathof(p)), ".."), targets))
    elseif labeller == :version
        label = version2string(map(p -> joinpath(dirname(pathof(p)), ".."), targets))
    end
    mkpath("mallocs")
    CSV.write(joinpath(path, "mallocs/mallocs$label.csv"), df)

    # Visualize a pretty table
    pretty_table(df)

    return nothing
end
