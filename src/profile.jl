prep(d::Dict, block::Expr, ::Val{:profile}) = quote
    import Profile
    $block
    nothing
end

function default_options(::Val{:profile})
    return Dict(:threads => 1, :targets => [], :track => "none", :repeat => true,
        :profile_seconds => 0.5, :profile_delay => 0.001,
        :profile_buffer => 10_000_000, :max_stack_depth => 128)
end

function check(d::Dict, block::Expr, ::Val{:profile})
    warmup = get(d, :repeat, true) ? block : nothing
    seconds = Float64(get(d, :profile_seconds, 0.5))
    seconds > 0 || throw(ArgumentError(":profile_seconds must be positive"))
    delay = Float64(get(d, :profile_delay, 0.001))
    delay > 0 || throw(ArgumentError(":profile_delay must be positive"))
    buffer = Int(get(d, :profile_buffer, 10_000_000))
    buffer > 0 || throw(ArgumentError(":profile_buffer must be positive"))
    max_depth = Int(get(d, :max_stack_depth, 128))
    max_depth > 0 || throw(ArgumentError(":max_stack_depth must be positive"))
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
        isempty(target_roots) && error("No loaded profiling target found in $(collect(target_names))")
        normalize_source(path) = Sys.iswindows() ? lowercase(normpath(path)) : normpath(path)
        normalized_roots = normalize_source.(target_roots)
        in_target(candidate) = begin
            candidate.line > 0 || return false
            source = String(candidate.file)
            isempty(source) && return false
            normalized = normalize_source(abspath(source))
            any(root -> startswith(normalized, root), normalized_roots)
        end
        frame_label(candidate) = begin
            source = String(candidate.file)
            parts = split(replace(normpath(source), '\\' => '/'), '/')
            short_source = join(last(parts, min(length(parts), 3)), '/')
            "$(candidate.func) ($short_source:$(candidate.line))"
        end

        Profile.clear()
        Profile.init(n = $buffer, delay = $delay)
        Profile.@profile begin
            deadline = time_ns() + round(UInt64, $seconds * 1.0e9)
            while time_ns() < deadline
                $block
            end
        end
        profile_data, line_info = Profile.retrieve(include_meta = false)
        grouped = Dict{Tuple{String, Int, Tuple{Vararg{String}}}, Int}()
        sample_ips = UInt[]
        record_sample! = function (ips)
            isempty(ips) && return
            expanded = Any[]
            for ip in ips
                frames = get(line_info, ip, nothing)
                frames === nothing && continue
                frames isa AbstractVector ? append!(expanded, frames) : push!(expanded, frames)
            end
            filter!(candidate -> candidate.line > 0 && !candidate.from_c &&
                !isempty(String(candidate.file)), expanded)
            isempty(expanded) && return
            target_leaf = findfirst(in_target, expanded)
            target_leaf === nothing && return
            root_frames = reverse(expanded)
            target_root = findfirst(in_target, root_frames)
            target_root === nothing && return
            selected = root_frames[target_root:min(end, target_root + $max_depth - 1)]
            stack = Tuple(frame_label.(selected))
            isempty(stack) && return
            site = expanded[target_leaf]
            key = (abspath(String(site.file)), Int(site.line), stack)
            grouped[key] = get(grouped, key, 0) + 1
            return
        end
        for ip in profile_data
            if ip == 0
                record_sample!(sample_ips)
                empty!(sample_ips)
            else
                push!(sample_ips, ip)
            end
        end
        record_sample!(sample_ips)
        isempty(grouped) && error("CPU profiler found no samples rooted in target source")
        [(samples = count, filename = key[1], line = key[2], stack = collect(key[3]))
         for (key, count) in sort!(collect(grouped); by = item ->
                 (-last(item), first(item)[1], first(item)[2]))]
    end
end

post(d::Dict, ::Val{:profile}) = d[:check_result]

const ProfileSample = @NamedTuple{
    samples::Int, filename::String, line::Int, stack::Vector{String}}

function to_table(records::Vector{ProfileSample})
    return Table(
        samples = [record.samples for record in records],
        filename = [record.filename for record in records],
        line = [record.line for record in records],
        stack = [record.stack for record in records])
end

@testitem "CPU profile records" tags=[:unit, :profile, :flamegraph] begin
    using PerfChecker

    records = PerfChecker.ProfileSample[
        (samples = 7, filename = "src/demo.jl", line = 12,
         stack = ["demo (src/demo.jl:12)", "sin (math.jl:1)"])]
    table = PerfChecker.to_table(records)
    @test table.samples == [7]
    @test table.stack[1][1] == "demo (src/demo.jl:12)"
    @test PerfChecker.default_options(Val(:profile))[:track] == "none"
end
