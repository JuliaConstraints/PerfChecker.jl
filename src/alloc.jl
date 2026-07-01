prep(d::Dict, block::Expr, ::Val{:alloc}) = quote
    import Profile
    $block
    nothing
end

function default_options(::Val{:alloc})
    return Dict(:threads => 1, :targets => [], :track => "user", :repeat => true)
end

stop_before_post(::Val{:alloc}) = true

function check(d::Dict, block::Expr, ::Val{:alloc})
    j = haskey(d, :repeat) && d[:repeat] ? block : nothing

    quote
        $j
        Profile.clear_malloc_data()
        $block
        rmstuff = Base.loaded_modules_array()
        target_names = Set(Symbol.(String.($(d[:targets]))))
        targets = if isempty(target_names)
            rmstuff
        else
            filter(m -> nameof(m) in target_names, rmstuff)
        end
        return dirname.(filter(!isnothing, pathof.(targets))),
        dirname.(filter(!isnothing, pathof.(rmstuff)))
    end
end

function post(d::Dict, ::Val{:alloc})
    result = d[:check_result]
    files = find_malloc_files(result[1])
    delete_files = find_malloc_files(result[2])
    try
        if isempty(files)
            throw(ErrorException("No allocation files found in $(d[:targets])"))
        end
        myallocs = analyze_malloc_files(files; skip_zeros = true)
        if isempty(myallocs)
            @warn "Allocation files do not contain non-zero allocation entries" targets = d[:targets]
        end
        return myallocs
    finally
        rm_malloc_files(delete_files)
    end
end

function rm_malloc_files(paths)
    for file in unique(_malloc_files(paths))
        try
            rm(file; force = true)
        catch err
            @debug "failed to remove allocation tracking file" file exception = (
                err, catch_backtrace())
        end
    end
    return nothing
end

function _malloc_files(paths)
    files = String[]
    for path in paths
        path === nothing && continue
        strpath = String(path)
        if isdir(strpath)
            append!(files, find_malloc_files([strpath]))
        elseif isfile(strpath) && endswith(strpath, ".mem")
            push!(files, strpath)
        end
    end
    return files
end

function cleanup(d::Dict, ::Val{:alloc})
    paths = String[@__DIR__]
    haskey(d, :path) && push!(paths, String(d[:path]))
    result = get(d, :check_result, nothing)
    if result !== nothing
        append!(paths, result[1])
        append!(paths, result[2])
    end
    rm_malloc_files(unique(paths))
    return nothing
end

function to_table(myallocs::Vector{MallocInfo})
    b = map(a -> a.bytes, Iterators.reverse(myallocs))
    r = round.(b / sum(b) * 100; digits = 2)
    f = map(first ∘ splitext ∘ first ∘ splitext,
        map(a -> a.filename, Iterators.reverse(myallocs)))
    l = map(a -> a.linenumber, Iterators.reverse(myallocs))
    Table(bytes = b, percentage = r, filename = f, line = l, filenames = f, linenumbers = l)
end
