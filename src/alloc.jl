prep(d::Dict, block::Expr, ::Val{:alloc}) = quote
    import Profile
    $block
    nothing
end

function default_options(::Val{:alloc})
    return Dict(:threads => 1, :targets => [], :track => "user", :repeat => true)
end

function check(d::Dict, block::Expr, ::Val{:alloc})
    j = haskey(d, :repeat) && d[:repeat] ? block : nothing

    quote
        $j
        Profile.clear_malloc_data()
        $block
        targets = eval(Meta.parse("[" * join($(d[:targets]), ", ") * "]"))
        rmstuff = Base.loaded_modules_array()
        if isempty(targets)
            targets = Base.loaded_modules_array()
        end
        return dirname.(filter(!isnothing, pathof.(targets))),
        dirname.(filter(!isnothing, pathof.(rmstuff)))
    end
end

function post(d::Dict, ::Val{:alloc})
    result = d[:check_result]
    files = find_malloc_files(result[1])
    delete_files = find_malloc_files(result[2])
    myallocs = analyze_malloc_files(files; skip_zeros = true)
    if !isempty(myallocs)
        rm.(delete_files)
    else
        @error "No allocation files found in $(d[:targets])"
    end
    myallocs
end

function to_table(myallocs::Vector{MallocInfo})
    b = map(a -> a.bytes, Iterators.reverse(myallocs))
    r = round.(b / sum(b) * 100; digits = 2)
    f = map(first ∘ splitext ∘ first ∘ splitext,
        map(a -> a.filename, Iterators.reverse(myallocs)))
    l = map(a -> a.linenumber, Iterators.reverse(myallocs))
    Table(bytes = b, percentage = r, filenames = f, linenumbers = l)
end
