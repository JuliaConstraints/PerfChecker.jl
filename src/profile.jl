prep(d::Dict, block::Expr, ::Val{:profile}) = quote
    import Profile
    $block
    nothing
end

function default_options(::Val{:profile})
    return Dict(:threads => 1, :targets => [], :track => "none", :repeat => true,
        :profile_seconds => 0.5, :profile_delay => 0.001,
        :profile_buffer => 10_000_000, :max_stack_depth => 128,
        :max_profile_stacks => 50_000)
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
            error("No loaded profiling target found in $(collect(target_names))")
        function normalize_source(path)
            Sys.iswindows() ? lowercase(normpath(path)) :
            normpath(path)
        end
        normalized_roots = normalize_source.(target_roots)
        function in_target(candidate)
            candidate.line > 0 || return false
            source = String(candidate.file)
            isempty(source) && return false
            normalized = normalize_source(abspath(source))
            any(root -> startswith(normalized, root), normalized_roots)
        end
        function frame_label(candidate)
            source = String(candidate.file)
            parts = split(replace(normpath(source), '\\' => '/'), '/')
            short_source = join(last(parts, min(length(parts), 3)), '/')
            "$(candidate.func) ($short_source:$(candidate.line))"
        end
        function frame_events(frames, index)
            runtime_dispatch = false
            gc_event = false
            child_index = index - 1
            while child_index >= 1 && frames[child_index].from_c
                name = frames[child_index].func
                runtime_dispatch |= name in (:jl_invoke, :jl_apply_generic,
                    :ijl_apply_generic)
                gc_event |= startswith(String(name), "jl_gc_")
                child_index -= 1
            end
            return runtime_dispatch, gc_event
        end
        function frame_inference(candidate)
            isdefined(candidate, :linfo) || return "unknown", ""
            line_info = candidate.linfo
            line_info === nothing && return "unknown", ""
            hasfield(typeof(line_info), :rettype) || return "unknown", ""
            return_type = getfield(line_info, :rettype)
            label = first(string(return_type), 240)
            return_type isa Core.Const && return "concrete", label
            return_type === Union{} && return "concrete", label
            return_type === Any && return "any", label
            return_type isa Union && return "union", label
            return_type isa Type && isconcretetype(return_type) &&
                return "concrete", label
            return "abstract", label
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
        grouped = Dict{Any, Int}()
        sample_ips = UInt[]
        record_sample! = function (ips)
            isempty(ips) && return
            expanded = Any[]
            for ip in ips
                frames = get(line_info, ip, nothing)
                frames === nothing && continue
                frames isa AbstractVector ? append!(expanded, frames) :
                push!(expanded, frames)
            end
            julia_indices = findall(
                candidate -> candidate.line > 0 &&
                                 !candidate.from_c &&
                                 !isempty(String(candidate.file)),
                expanded)
            isempty(julia_indices) && return
            julia_frames = expanded[julia_indices]
            target_leaf = findfirst(in_target, julia_frames)
            target_leaf === nothing && return
            runtime_dispatch = first.(frame_events.(Ref(expanded), julia_indices))
            gc_events = last.(frame_events.(Ref(expanded), julia_indices))
            inference = frame_inference.(julia_frames)
            root_frames = reverse(julia_frames)
            root_runtime_dispatch = reverse(runtime_dispatch)
            root_gc_events = reverse(gc_events)
            root_inference_status = reverse(first.(inference))
            root_inferred_return = reverse(last.(inference))
            target_root = findfirst(in_target, root_frames)
            target_root === nothing && return
            selected_range = target_root:min(length(root_frames),
                target_root + $max_depth - 1)
            selected = root_frames[selected_range]
            stack = Tuple(frame_label.(selected))
            isempty(stack) && return
            site = julia_frames[target_leaf]
            key = (abspath(String(site.file)), Int(site.line), stack,
                Tuple(root_runtime_dispatch[selected_range]),
                Tuple(root_gc_events[selected_range]),
                Tuple(root_inference_status[selected_range]),
                Tuple(root_inferred_return[selected_range]))
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
        ordered = sort!(
            collect(grouped); by = item -> (
                -last(item), first(item)[1], first(item)[2]))
        keep = length(ordered) > $max_stacks ? $max_stacks - 1 : length(ordered)
        output = [(samples = count, filename = key[1], line = key[2],
                      stack = collect(key[3]), runtime_dispatch = collect(key[4]),
                      gc_event = collect(key[5]), inference_status = collect(key[6]),
                      inferred_return_type = collect(key[7]))
                  for (key, count) in first(ordered, keep)]
        if length(ordered) > $max_stacks
            remainder = sum(last, ordered[($max_stacks):end]; init = 0)
            push!(output,
                (samples = remainder, filename = "[other]", line = 0,
                    stack = ["Other sampled stacks"], runtime_dispatch = [false],
                    gc_event = [false], inference_status = ["unknown"],
                    inferred_return_type = [""]))
        end
        output
    end
end

post(d::Dict, ::Val{:profile}) = d[:check_result]

prep(d::Dict, block::Expr, ::Val{:wall_profile}) = prep(d, block, Val(:profile))
default_options(::Val{:wall_profile}) = default_options(Val(:profile))

function _wall_profile_macro(expression)
    expression isa Expr || return expression
    args = Any[_wall_profile_macro(argument) for argument in expression.args]
    if expression.head === :macrocall && !isempty(args) &&
       occursin("@profile", string(args[1]))
        args[1] = GlobalRef(Profile, Symbol("@profile_walltime"))
    end
    return Expr(expression.head, args...)
end

function check(d::Dict, block::Expr, ::Val{:wall_profile})
    VERSION >= v"1.12" || throw(ArgumentError(
        "the wall-time task profiler requires Julia 1.12 or newer"))
    return _wall_profile_macro(check(d, block, Val(:profile)))
end

post(d::Dict, ::Val{:wall_profile}) = d[:check_result]

const ProfileSample = @NamedTuple{
    samples::Int, filename::String, line::Int, stack::Vector{String},
    runtime_dispatch::Vector{Bool}, gc_event::Vector{Bool},
    inference_status::Vector{String}, inferred_return_type::Vector{String}}

function to_table(records::Vector{ProfileSample})
    return Table(
        samples = [record.samples for record in records],
        filename = [record.filename for record in records],
        line = [record.line for record in records],
        stack = [record.stack for record in records],
        runtime_dispatch = [record.runtime_dispatch for record in records],
        gc_event = [record.gc_event for record in records],
        inference_status = [record.inference_status for record in records],
        inferred_return_type = [record.inferred_return_type for record in records])
end

@testitem "CPU profile records" tags=[:unit, :profile, :flamegraph] begin
    using PerfChecker

    records = PerfChecker.ProfileSample[
        (samples = 7, filename = "src/demo.jl", line = 12,
        stack = ["demo (src/demo.jl:12)", "sin (math.jl:1)"],
        runtime_dispatch = [false, true], gc_event = [false, false],
        inference_status = ["concrete", "union"],
        inferred_return_type = ["Float64", "Union{Float64, Int64}"])]
    table = PerfChecker.to_table(records)
    @test table.samples == [7]
    @test table.stack[1][1] == "demo (src/demo.jl:12)"
    @test table.runtime_dispatch[1] == [false, true]
    @test table.inference_status[1] == ["concrete", "union"]
    @test PerfChecker.default_options(Val(:profile))[:track] == "none"
    @test PerfChecker.default_options(Val(:wall_profile))[:track] == "none"
    if VERSION >= v"1.12"
        expression = PerfChecker.check(Dict{Symbol, Any}(), :(sum(1:10)),
            Val(:wall_profile))
        @test occursin("profile_walltime", string(expression))
    end
end
