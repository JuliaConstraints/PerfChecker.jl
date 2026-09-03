prep(d::Dict, block::Expr, ::Val{:profile_alloc}) = quote
    import Profile
    $block
    nothing
end

function default_options(::Val{:profile_alloc})
    return Dict(:threads => 1, :targets => [], :track => "none", :repeat => true,
        :sample_rate => 1.0, :profile_repetitions => 1,
        :max_profile_stacks => 50_000)
end

function check(d::Dict, block::Expr, ::Val{:profile_alloc})
    warmup = get(d, :repeat, true) ? block : nothing
    sample_rate = Float64(get(d, :sample_rate, 1.0))
    0.0 < sample_rate <= 1.0 ||
        throw(ArgumentError(":sample_rate must be in the interval (0, 1]"))
    repetitions = Int(get(d, :profile_repetitions, 1))
    repetitions > 0 || throw(ArgumentError(":profile_repetitions must be positive"))
    max_stacks = Int(get(d, :max_profile_stacks, 50_000))
    max_stacks > 1 || throw(ArgumentError(":max_profile_stacks must be greater than one"))
    target_names = String.(get(d, :targets, String[]))
    return quote
        $warmup
        target_names = Set(Symbol.($target_names))
        loaded = Base.loaded_modules_array()
        targets = isempty(target_names) ? loaded :
                  filter(module_value -> nameof(module_value) in target_names, loaded)
        target_roots = String[]
        for module_value in targets
            source = pathof(module_value)
            source === nothing || push!(target_roots, dirname(abspath(source)))
        end
        isempty(target_roots) &&
            error("No loaded allocation target found in $(collect(target_names))")
        function normalize_source(path)
            Sys.iswindows() ? lowercase(normpath(path)) :
            normpath(path)
        end
        normalized_roots = normalize_source.(target_roots)

        total_bytes = Base.@allocated $block
        total_allocs = Base.@allocations $block
        Profile.Allocs.clear()
        Profile.Allocs.@profile sample_rate=$sample_rate begin
            for _ in 1:($repetitions)
                $block
            end
        end
        allocation_results = Profile.Allocs.fetch()
        grouped = Dict{Tuple{String, Int, Tuple{Vararg{String}}}, Tuple{Int, Int}}()
        for allocation in allocation_results.allocs
            target_positions = findall(allocation.stacktrace) do candidate
                candidate.line > 0 || return false
                source = String(candidate.file)
                isempty(source) && return false
                normalized = normalize_source(abspath(source))
                any(root -> startswith(normalized, root), normalized_roots)
            end
            isempty(target_positions) && continue
            site = allocation.stacktrace[first(target_positions)]
            root_position = last(target_positions)
            frames = reverse(allocation.stacktrace[1:root_position])
            stack = String[]
            for candidate in frames
                candidate.line > 0 || continue
                source = String(candidate.file)
                isempty(source) && continue
                source_parts = split(replace(normpath(source), '\\' => '/'), '/')
                short_source = join(last(source_parts, min(length(source_parts), 3)), '/')
                push!(stack, "$(candidate.func) ($short_source:$(candidate.line))")
            end
            isempty(stack) && continue
            key = (abspath(String(site.file)), Int(site.line), Tuple(stack))
            bytes, count = get(grouped, key, (0, 0))
            grouped[key] = (bytes + Int(allocation.size), count + 1)
        end
        sampled_bytes = sum(first, values(grouped); init = 0)
        sampled_allocs = sum(last, values(grouped); init = 0)
        sampled_bytes > 0 || error("Allocation profiler found no target source sites")
        byte_scale = Float64(total_bytes) / sampled_bytes
        alloc_scale = sampled_allocs == 0 ? 0.0 : Float64(total_allocs) / sampled_allocs
        ordered = sort!(
            collect(grouped); by = item -> (
                -last(item)[1], first(item)[1], first(item)[2]))
        keep = length(ordered) > $max_stacks ? $max_stacks - 1 : length(ordered)
        output = [(bytes = values[1] * byte_scale,
                      allocs = values[2] * alloc_scale,
                      filename = key[1], line = key[2], stack = collect(key[3]))
                  for (key, values) in first(ordered, keep)]
        if length(ordered) > $max_stacks
            remainder_bytes = sum(item -> last(item)[1],
                ordered[($max_stacks):end]; init = 0) * byte_scale
            remainder_allocs = sum(item -> last(item)[2],
                ordered[($max_stacks):end]; init = 0) * alloc_scale
            push!(output,
                (bytes = remainder_bytes, allocs = remainder_allocs,
                    filename = "[other]", line = 0,
                    stack = ["Other sampled allocation stacks"]))
        end
        output
    end
end

post(d::Dict, ::Val{:profile_alloc}) = d[:check_result]

const ProfileAllocSite = @NamedTuple{
    bytes::Float64, allocs::Float64, filename::String, line::Int,
    stack::Vector{String}}

function to_table(records::Vector{ProfileAllocSite})
    return Table(
        bytes = [record.bytes for record in records],
        allocs = [record.allocs for record in records],
        filename = [record.filename for record in records],
        line = [record.line for record in records],
        stack = [record.stack for record in records])
end

@testitem "Profile allocation records" tags=[:unit, :allocations, :profile_alloc] begin
    using PerfChecker

    records = PerfChecker.ProfileAllocSite[
        (bytes = 64.0, allocs = 2.0, filename = "src/demo.jl", line = 12,
        stack = ["demo (src/demo.jl:12)"])]
    table = PerfChecker.to_table(records)
    @test table.bytes == [64.0]
    @test table.allocs == [2.0]
    @test table.filename == ["src/demo.jl"]
    @test table.stack == [["demo (src/demo.jl:12)"]]
    @test PerfChecker.default_options(Val(:profile_alloc))[:track] == "none"
end
