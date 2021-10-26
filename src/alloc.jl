function alloc_set(title, targets, ex_pre, ex_checker)
    @info "Tracking allocations: $title"

    # add a proc (id == p) that track allocations
    p = first(addprocs(1; exeflags=["--track-allocation=user", "--project"]))

    # load packages used by p independently of the targets
    ex = quote
        using Profile
    end
    remotecall_wait(eval, p, ex)

    # execute the pre-check expression on p
    remotecall_wait(eval, p, ex_pre)

    # clear malloc data on p
    remotecall_wait(Profile.clear_malloc_data, p)

    # execute the allocation checker on p
    remotecall_wait(eval, p, ex_checker)

    # close p to retrieve the allocation data
    rmprocs(p)

    # Retrieve the allocations data through Coverage.jl
    myallocs = Coverage.analyze_malloc(dirname(pathof(CompositionalNetworks)))

    # Clean the *.mem files from the allocation tracking
    for t in targets, d in walkdir(dirname(pathof(t))), f in d[end]
        splitext(f)[2] == ".mem" && rm(joinpath(d[1], f))
    end

    # Make the allocations data readable through a dataframe
    df = DataFrame()
    df.bytes = map(a -> a.bytes, Iterators.reverse(myallocs))
    df.filename = map(a -> a.filename, Iterators.reverse(myallocs))
    df.linenumber = map(a -> a.linenumber, Iterators.reverse(myallocs))

    # Save it as a CSV file
    CSV.write(joinpath(pwd(), "mallocs.csv"), df)

    # pretty print the data
    pretty_table(df)

    return nothing
end
