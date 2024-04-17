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
        d = $(esc(d))
        di = default_options(d, $x)
        g = prep(di, $block1, $x)
        h = check(di, $block2, $x)
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
            [PackageSpec(name=di[:pkgs][1], version=i) for i in get_versions(di[:pkgs])[2]]
        else 
            PackageSpec[PackageSpec()]
        end

        devop = haskey(di, :devops)

        len = length(pkgs) + devop
        
        for i in 1:len
            p = remotecall_fetch(Core.eval, 1, Main,

            Expr(:toplevel, quote
                import Distributed
                d = $di
                t = tempname()
                cp(d[:path], t)
                Distributed.addprocs(1; exeflags=["--track-allocation=$(d[:track])", "--project=$t", "-t $(d[:threads])"])
            end).args...) |> first

            remotecall_fetch(Core.eval, p, Main,
                    Expr(:toplevel, quote
                        import Pkg;
                        Pkg.instantiate();
                        import PerfChecker
                        d = $di

                        pkgs = if haskey(d, :pkgs)
                            [Pkg.PackageSpec(name=d[:pkgs][1], version=i) for i in PerfChecker.get_versions(d[:pkgs])[2]]
                        else 
                            Pkg.PackageSpec[Pkg.PackageSpec()]
                        end
                        
                        if !($i == $len && $devop)
                            pkgs != [Pkg.PackageSpec()] && Pkg.add(getindex(pkgs, $i))
                        else
                            pkg = d[:devops]
                            pkg isa Tuple ? Pkg.develop(pkg[1]; pkg[2]...) : Pkg.develop(pkg)
                        end                       
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
            if !(devop && i == len) 
                push!(results.pkgs, pkgs[i])
            end

        end
        results
    end
end

function perf_table end

function perf_plot end
