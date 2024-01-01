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
        p = remotecall_fetch(Core.eval, 1, Main,
            Expr(:toplevel, quote
                import Distributed
                d = $di
                Distributed.addprocs(1; exeflags=["--track-allocation=$(d[:track])", "--project=$(d[:path])", "-t $(d[:threads])"])
            end).args...) |> first

        di[:prep_result] = remotecall_fetch(Core.eval, p, Main,
            Expr(:toplevel, g.args...))

        di[:check_result] = remotecall_fetch(Core.eval, p, Main,
            Expr(:toplevel, h.args...))

        remotecall_fetch(Core.eval, 1, Main,
            Expr(:toplevel, quote
                import Distributed
                Distributed.rmprocs($p)
            end).args...)

        $post(di, $x)
    end
end

macro check(x, d, block)
    quote
        @check $x $d nothing $block
    end
end