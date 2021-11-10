function store_benchmark(bench, target; path=pwd())
    df = DataFrame(;
        times=bench.times, gctimes=bench.gctimes, memory=bench.memory, allocs=bench.allocs
    )

    # Save it as a CSV file
    label = version2string(map(p -> joinpath(dirname(pathof(p)), ".."), [target]))
    mkpath("benchmarks")
    CSV.write(joinpath(path, "benchmarks/benchmark$label.csv"), df)

    # Visualize a pretty table
    pretty_table(df)

    return nothing
end

function bench_plot(targets; formats=["pdf", "tikz", "svg", "png"], backend=pgfplotsx)
    backend()
    for target in targets
        path = normpath(joinpath(dirname(pathof(target)), "..", "perf", "benchmarks"))
        versions = Vector{VersionNumber}()
        for f in readdir(path; join=true)
            st = splitext(basename(f))
            last(st) == ".csv" || continue
            push!(versions, VersionNumber(first(st)[11:end]))
        end
        sort!(versions)

        data = [
            Dict(
                "times" => Vector{Float64}(),
                "gctimes" => Vector{Float64}(),
                "memory" => Vector{Float64}(),
                "allocs" => Vector{Float64}(),
            ) for _ in 1:length(versions)
        ]
        means = Dict(
            "times" => Vector{Float64}(),
            "gctimes" => Vector{Float64}(),
            "memory" => Vector{Float64}(),
            "allocs" => Vector{Float64}(),
        )
        for (i, version) in enumerate(versions)
            csv_path = joinpath(path, "benchmark-$(string(version)).csv")
            df = DataFrame(CSV.File(csv_path))
            for dim in ["times", "gctimes", "memory", "allocs"]
                data[i][dim] = df[!, dim]
                push!(means[dim], mean(df[!, dim]))
            end
        end
        X = map(string, versions)
        aux = Vector{Vector{Float64}}()
        for (i, dim) in enumerate(["times", "gctimes", "memory", "allocs"])
            ylabel = if dim == "memory"
                "size (bytes)"
            elseif dim == "allocs"
                "allocations"
            else
                "time (ns)"
            end
            aux = map(i -> data[i][dim], 1:length(versions))
            y = collect(Iterators.flatten(Iterators.zip(aux...)))
            boxplot(
                X,
                y;
                xlabel="version",
                ylabel,
                title="Benchmarks ($dim) evolution in\n$target.jl",
                l=(0.5, 2),
                label=dim,
            )
            for format in formats
                savefig(joinpath(path, "benchmark-$dim-evolutions-boxplot.$format"))
            end
            z = map(mean, aux)
            plot(
                X,
                z / last(z);
                xlabel="version",
                ylabel="ratio",
                title="Benchmarks ($dim) evolution in\n$target.jl",
                markershape=:circle,
                l=(0.5, 2),
                label=dim,
            )
            for format in formats
                savefig(joinpath(path, "benchmark-$dim-evolutions-line.$format"))
            end
            # push!(aux, y)
        end
        # Y = reshape(collect(Iterators.flatten(values(means))), length(means["times"]), 4)
        # L = reshape(collect(keys(means)), 1, length(means))
        # plot(X, Y;
        # xlabel="version",
        # ylabel="time",
        # markershape=:circle,
        # title="Benchmarks evolution in\n$target.jl",
        # l=(0.5, 2),
        # label=L,)
        # for format in formats
        #     savefig(joinpath(path, "benchmark-evolutions.$format"))
        # end
    end
end
