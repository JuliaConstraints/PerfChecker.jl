function __init__()
    if isinteractive()
        eval(Meta.parse("""
        function TypedTables.showtable(io::IO, t::TypedTables.Table{NamedTuple{(:bytes, :percentage, :filenames, :linenumbers), Tuple{Int64, Float64, String, Int64}}, 1, NamedTuple{(:bytes, :percentage, :filenames, :linenumbers), Tuple{Vector{Int64}, Vector{Float64}, Vector{String}, Vector{Int64}}}})
            fn = Term.Link.("file://" .* t.filenames, t.linenumbers)
            Term.tprint(io, Term.Table([t.bytes t.percentage fn]; header = ["bytes", "ratio (%)", "filenames (links)"]))
        end
        """))

        eval(Meta.parse("""
        function TypedTables.showtable(io::IO, t::TypedTables.Table{NamedTuple{(:times, :gctimes, :memory, :allocs), Tuple{Float64, Float64, Int64, Int64}}, 1, NamedTuple{(:times, :gctimes, :memory, :allocs), Tuple{Vector{Float64}, Vector{Float64}, Vector{Int64}, Vector{Int64}}}})
            Term.tprint(io, Term.Table([t.times t.gctimes t.memory t.allocs]; header = ["times", "gctimes", "memory", "allocs"]))
        end
        """))
    end
end
