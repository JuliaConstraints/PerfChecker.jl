
prep(::Val{:alloc}, d::Dict, block::Expr, ) = quote
    import Pkg
    Pkg.instantiate()
    import Profile
    $block
    return nothing
end

function check(::Val{:alloc}, d::Dict, block::Expr)

    j = haskey(d, :repeat) && d[:repeat] ? block : nothing

    quote
        $j
        Profile.clear_malloc_data()
        $block
        targets = eval(Meta.parse("[" * join($(d[:targets]), ", ") *  "]"))
        rmstuff = Base.loaded_modules_array()
        return dirname.(filter(!isnothing, pathof.(targets))), dirname.(filter(!isnothing, pathof.(rmstuff)))
    end
end

function post(::Val{:alloc}, d::Dict, result)
    @info  "debug" d
    # result = d[:check_result]
    files = find_malloc_files(result[1])
    delete_files = find_malloc_files(result[2])
    myallocs = analyze_malloc_files(files)
    if !isempty(myallocs)
        rm.(delete_files)
    else
        @error "No allocation files found in $(d[:targets])"
    end
    return myallocs
end