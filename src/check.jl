initpkgs(x) = quote
    nothing
end
prep(d, b, v) = quote
    nothing
end
check(d, b, v) = quote
    nothing
end
post(d, v) = nothing
default_options(v) = Dict()

initpkgs(x::Symbol) = initpkgs(Val(x))
prep(d::Dict, b::Expr, v::Symbol) = prep(d, b, Val(v))
check(d::Dict, b::Expr, v::Symbol) = check(d, b, Val(v))
post(d::Dict, v::Symbol) = post(d, Val(v))

function default_options(d::Dict, v::Symbol)
    di = default_options(Val(v))
    return merge(di, d)
end

function check_function(x::Symbol, d::Dict, block1, block2)
    di = default_options(d, x)
    g = prep(di, block1, x)
    h = check(di, block2, x)
    initpkg = initpkgs(x)

    results = CheckerResult(
        Table[],
        HwInfo(
            cpu_info(),
            CPU_NAME,
            WORD_SIZE,
            simdbytes(),
            (cpucores(), cputhreads(), cputhreads_per_core())
        ),
        haskey(di, :tags) ? di[:tags] : Symbol[:none],
        PackageSpec[]
    )

    pkgs = if haskey(di, :pkgs)
        [PackageSpec(name = di[:pkgs][1], version = i) for i in get_versions(di[:pkgs])[2]]
    else
        PackageSpec[PackageSpec()]
    end

    devop = haskey(di, :devops)

    len = length(pkgs) + devop

    t = [tempname() for _ in 1:len]
    cp.(Ref(di[:path]), t)

    procs = @sync begin
        fetch.([@async(Worker(;
                    exeflags = ["--track-allocation=$(di[:track])",
                        "-t $(di[:threads])", "--project=$(t[i])"])) for i in 1:len])
    end

    for i in 1:len
        is_loaded = false
        if i ≤ length(pkgs)
            path = joinpath(di[:path], "metadata", "metadata.csv")
            fp = flatten_parameters(x, pkgs[i].name, pkgs[i].version, d[:tags])
            u = get_uuid() |> Base.UUID
            if in_metadata(path, fp, u)
                is_loaded = true
            end
        end

        if !is_loaded
            remote_eval_wait(Main, procs[i], quote
                import Pkg
                let
                    i = $i
                    @info "Worker No.: $i"
                end
                Pkg.instantiate(; io = stderr)
            end)

            remote_eval_wait(Main, procs[i], initpkg)

            remote_eval_wait(Main, procs[i],
                quote
                    d = $di
                    pkgs = $pkgs
                    if !($i == $len && $devop)
                        pkgs != [Pkg.PackageSpec()] && Pkg.add(getindex(pkgs, $i))
                    else
                        pkg = d[:devops]
                        pkg isa Tuple ? Pkg.develop(pkg[1]; pkg[2]...) : Pkg.develop(pkg)
                    end
                    haskey(d, :extra_pkgs) && Pkg.add(d[:extra_pkgs])
                end)

            di[:prep_result] = remote_eval_fetch(Main, procs[i], g)
            di[:check_result] = remote_eval_fetch(Main, procs[i], h)

            stop(procs[i])
        end

        res = if is_loaded
            fp = flatten_parameters(x, pkgs[i].name, pkgs[i].version, d[:tags])
            u = uuid5(get_uuid() |> Base.UUID, fp)
            path = joinpath(di[:path], "output", string(u)) * ".csv"
            csv_to_table(path)
        else
            post(di, x) |> to_table
        end
        push!(results.tables, res)
        if !(devop && i == len)
            push!(results.pkgs, pkgs[i])
        else
            pkg = d[:devops]
            p = pkg isa Tuple ? pkg[1] : pkg
            p = p isa Pkg.PackageSpec ? p.name : p
            push!(results.pkgs, Pkg.PackageSpec(name = p, version = "dev"))
        end
    end

    for (k, t) in enumerate(results.tables)
        tags = results.tags
        ps = results.pkgs[k]
        pkg = ps.name
        v = ps.version
        (isnothing(pkg) || v == "dev") && continue
        name = filename(x, pkg, v, tags; ext = "csv")
        path = joinpath(d[:path], "output", name)
        metadata = joinpath(d[:path], "metadata", "metadata.csv")
        fp = flatten_parameters(x, pkg, v, tags)
        u = get_uuid() |> Base.UUID
        if in_metadata(metadata, fp, u)
            continue
        end
        table_to_csv(t, path)
        check_to_metadata_csv(x, pkg, v, tags; metadata)
    end

    return results
end

macro check(x, d, block1, block2)
    block1, block2 = Expr(:quote, block1), Expr(:quote, block2)
    quote
        x = $(esc(x))
        d = $(esc(d))
        check_function(x, d, $block1, $block2)
    end
end

function perf_table end

function perf_plot end

function table_to_pie end

function checkres_to_scatterlines end

function checkres_to_pie end

function saveplot end

function checkres_to_boxplots end
