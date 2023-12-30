prep(d::Dict, block::Expr, ::Val{:alloc}) = quote
    import Pkg
    Pkg.instantiate()
    import Profile
    $block
    nothing
end

function check(d::Dict, block::Expr, ::Val{:alloc})

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

function post(result, d::Dict, ::Val{:alloc})
    files = find_malloc_files(result[1])
    delete_files = find_malloc_files(result[2])
    myallocs = analyze_malloc_files(files)
    if !isempty(myallocs)
        rm.(delete_files)
    else
        @error "No allocation files found in $(d[:targets])"
    end
    myallocs
end


prep(d::Dict, b::Expr, v::Symbol) = prep(d, b, Val(v))
check(d::Dict, b::Expr, v::Symbol) = check(d, b, Val(v))
post(result, d::Dict, v::Symbol) = post(result, d, Val(v))

macro check(x, d, block1, block2)
    block1, block2 = Expr(:quote, block1), Expr(:quote, block2)
    quote
        g = prep($d, $block1, $x)
        h = check($d, $block2, $x)
        p = remotecall_fetch(Core.eval, 1, Main,
            Expr(:toplevel, quote
                import Distributed
                d = $($d)
                Distributed.addprocs(1; exeflags=["--track-allocation=$(d[:track])", "--project=$(d[:path])", "-t $(d[:threads])"])
            end).args...) |> first

        remotecall_fetch(Core.eval, p, Main,
            Expr(:toplevel, g.args...))

        j = remotecall_fetch(Core.eval, p, Main,
            Expr(:toplevel, h.args...))

        remotecall_fetch(Core.eval, 1, Main,
            Expr(:toplevel, quote
                 import Distributed
                Distributed.rmprocs($p)
            end).args...)

        $post(j, $d, $x)
    end
end

#=
function alloc_check(
    title,
    dependencies,
    targets,
    pre_alloc,
    alloc;
    path=pwd(),
    labeller=:version,
    threads=nothing,
)
    @info "Tracking allocations: $title"

    # cd to path if valid
    isdir(path) && cd(path)

    # add a proc (id == p) that track allocations
    p = first(isnothing(threads) ? addprocs(1; exeflags=["--track-allocation=user", "--project=$path"]) : addprocs(1; exeflags=["--track-allocation=user", "--project=$path", "-t $threads"]))

    remotecall_fetch(Core.eval, p, Main, Expr(:toplevel, (quote
        import Pkg; Pkg.instantiate()
        import Profile;
        nothing
    end).args...))

    for d in dependencies
        remotecall_fetch(Core.eval, p, Main, Expr(:toplevel, (quote
            using $(Symbol(d))
            nothing
        end).args...))
    end

    @eval @everywhere $p $pre_alloc()
    @eval @everywhere $p Profile.clear_malloc_data()
    @eval @everywhere $p $alloc()

    rmprocs(p)

    myallocs = CoverageTools.analyze_malloc(map(dirname ∘ pathof ∘ eval, targets))

    for t in dependencies, d in walkdir(dirname(pathof(t))), f in d[end]
        splitext(f)[2] == ".mem" && rm(joinpath(d[1], f))
    end
    for d in walkdir(path), f in d[end]
        splitext(f)[2] == ".mem" && rm(joinpath(d[1], f))
    end

    if isempty(myallocs)
        @warn "No allocations was found in " targets
        return nothing
    end

    # Smart paths

    # common, specifics = smart_paths(map(a -> a.filename, Iterators.reverse(myallocs)))
    # @info "sizes" map(a -> a.filename, Iterators.reverse(myallocs)) specifics
    # slash = Sys.iswindows() ? "\\" : "/"

    # Make the allocations data readable through a dataframe

    #=
    df = DataFrame()
    df.bytes = map(a -> a.bytes, Iterators.reverse(myallocs))
    df[!, "ratio (%)"] = round.(df.bytes / sum(df.bytes) * 100; digits=2)
    df[!, "filename: [$common$slash"] = map(first ∘ splitext ∘ first ∘ splitext, specifics)
    df.linenumber = map(a -> a.linenumber, Iterators.reverse(myallocs))
    =#
    t = let
        b = map(a -> a.bytes, Iterators.reverse(myallocs))
        r = round.(b / sum(b) * 100; digits=2)
        f = map(first ∘ splitext ∘ first ∘ splitext, map(a -> a.filename, Iterators.reverse(myallocs)))
        l = map(a -> a.linenumber, Iterators.reverse(myallocs))
        TypedTables.Table(bytes = b, percentage = r, filenames = f, linenumbers = l)
    end

    # Save it as a CSV file
    label = ""
    if labeller == :oid
        label = oid2string(map(p -> joinpath(dirname(pathof(p)), ".."), targets))
    elseif labeller == :version
        label = version2string(map(p -> joinpath(dirname(pathof(p)), ".."), targets))
    end
    mkpath("mallocs")
    CSV.write(joinpath(path, "mallocs/mallocs$label.csv"), t)

    # Visualize a pretty table
    return t
end

function pie_filter(df, threshold=5.0)
    i = findfirst(x -> x < threshold, df[!, 2])
    X = df[1:(i - 1), 3] .* " line " .* map(string, df[1:(i - 1), 4])
    push!(X, "others .< $threshold")
    Y = df[1:(i - 1), 2]
    push!(Y, sum(df[i:end, 2]))
    return X, Y
end

function alloc_plot(
    targets; formats=["pdf", "svg", "png"], backend=Plots.GRBackend, seriestype=:step
)
    backend()
    for target in targets
        path = normpath(joinpath(dirname(pathof(target)), "..", "perf", "mallocs"))
        versions = Vector{VersionNumber}()
        for f in readdir(path; join=true)
            st = splitext(basename(f))
            last(st) == ".csv" || continue
            push!(versions, VersionNumber(first(st)[9:end]))
        end
        sort!(versions)

        bytes = Dict{String,Vector{Int}}()
        for (i, version) in enumerate(versions)
            csv_path = joinpath(path, "mallocs-$(string(version)).csv")
            df = DataFrame(CSV.File(csv_path))
            v = get!(bytes, "Total", zeros(Int, length(versions)))
            v[i] = sum(df.bytes)
            for (b, f) in zip(df[:, 1], df[:, 3])
                w = get!(bytes, "$f", zeros(Int, length(versions)))
                w[i] += b
            end

            X, Y = pie_filter(df)
            pie(X, Y; title="Mallocs for $target.jl@v$(string(version))", l=0.5)
            for format in formats
                savefig(joinpath(path, "mallocs-$version.$format"))
            end
        end

        X = map(string, versions)
        Y = reshape(
            collect(Iterators.flatten(values(bytes))), length(versions), length(bytes)
        )
        L = reshape(collect(keys(bytes)), 1, length(bytes))
        plot(
            X,
            Y;
            xlabel="version",
            ylabel="bytes",
            markershape=:circle,
            # seriestype,
            title="Mallocs evolution in\n$target.jl",
            l=(0.5, 2),
            label=L,
            # yaxis=:log,
        )
        for format in formats
            savefig(joinpath(path, "mallocs-evolutions.$format"))
        end
    end
end
=#

