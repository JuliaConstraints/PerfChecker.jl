module PropCheckExt

using PerfChecker
using PropCheck
using Random

function PerfChecker.freeze_propcheck_corpus(path::AbstractString, generator;
        count::Integer = 100, seed::Integer = 0, encode::Function = identity,
        metadata::AbstractDict = Dict(), force::Bool = false)
    count > 0 || throw(ArgumentError("corpus count must be positive"))
    rng = Random.Xoshiro(seed)
    generated = [PropCheck.generate(rng, generator) for _ in 1:count]
    cases = [value isa PropCheck.Tree ? PropCheck.root(value) : value
             for value in generated]
    details = Dict{String, Any}(string(key) => value for (key, value) in pairs(metadata))
    details["generator_type"] = string(typeof(generator))
    details["seed"] = seed
    return PerfChecker.write_property_corpus(path, map(encode, cases);
        producer = "PropCheck.jl", metadata = details, force)
end

end
