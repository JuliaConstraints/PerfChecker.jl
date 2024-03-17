prep(d, b, v) = quote nothing end
check(d, b, v) = quote nothing end
post(d, v) = nothing
default_options(v) = Dict()

prep(d::Dict, b::Expr, v::Symbol) = prep(d, b, Val(v))
check(d::Dict, b::Expr, v::Symbol) = check(d, b, Val(v))
post(d::Dict, v::Symbol) = post(d, Val(v))

function default_options(d::Dict, v::Symbol)
  di = default_options(Val(v))
  return merge(di, d)
end

macro check(x, d, block1, block2)
    block1, block2 = Expr(:quote, block1), Expr(:quote, block2)
    quote
        di = default_options($d, $x)
        g = prep(di, $block1, $x)
        h = check(di, $block2, $x)
        results = CheckerResult(
            Table[],
            HwInfo(
                cpu_info(),
                CPU_NAME,
                WORD_SIZE,
                simdbytes(),
                (cpucores(), cpucores_total(), cputhreads_per_core())
            ),
            haskey(di, :tags) ? di[:tags] : Symbol[:none],
            PackageSpec[]
        )

        p = remotecall_fetch(Core.eval, 1, Main,
            Expr(:toplevel, quote
                import Distributed
                d = $di
                t = tempname()
                cp(d[:path], t)
                Distributed.addprocs(1; exeflags=["--track-allocation=$(d[:track])", "--project=$t", "-t $(d[:threads])"])
            end).args...) |> first

        pkgs = haskey(di, :pkgs) ? [PackageSpec(name=di[:pkgs][1], version=i) for i in get_versions(di[:pkgs])] : PackageSpec[PackageSpec()]

        for i in pkgs
            remotecall_fetch(Core.eval, p, Main,
                    Expr(:toplevel, quote
                        import Pkg;
                        d = $di
                        Pkg.instantiate();
                        $pkgs != [Pkg.PackageSpec()] && Pkg.add($i)
                        haskey(d, :extra_pkgs) && Pkg.add(d[:extra_pkgs])
                end).args...)

            di[:prep_result] = remotecall_fetch(Core.eval, p, Main,
                Expr(:toplevel, g.args...))

            di[:check_result] = remotecall_fetch(Core.eval, p, Main,
                Expr(:toplevel, h.args...))

            remotecall_fetch(Core.eval, 1, Main,
                Expr(:toplevel, quote
                    import Distributed
                    Distributed.rmprocs($p)
                end).args...)

            res = $post(di, $x)
            push!(results.tables, res |> to_table)
            push!(results.pkgs, i)
        end
        results
    end
end

function perf_table end

function perf_plot end
