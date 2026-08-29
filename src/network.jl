prep(d::Dict, block::Expr, ::Val{:network}) = quote
    $block
    nothing
end

function default_options(::Val{:network})
    return Dict(:threads => 1, :track => "none", :repeat => true,
        :network_repetitions => 5)
end

function check(d::Dict, block::Expr, ::Val{:network})
    warmup = get(d, :repeat, true) ? block : nothing
    repetitions = Int(get(d, :network_repetitions, 5))
    repetitions > 0 || throw(ArgumentError(":network_repetitions must be positive"))
    return quote
        $warmup
        rows = NamedTuple[]
        for _ in 1:($repetitions)
            started = time_ns()
            payload = $block
            elapsed = (time_ns() - started) / 1.0e9
            payload isa NamedTuple || payload isa AbstractDict ||
                error(
                    "network workloads must return a NamedTuple or dictionary")
            function field(name, default = nothing)
                haskey(payload, name) ? payload[name] :
                haskey(payload, String(name)) ?
                payload[String(name)] : default
            end
            any(name -> haskey(payload, name) || haskey(payload, String(name)),
                (:bytes_sent, :bytes_received, :operations)) || error(
                "network workloads must report bytes_sent, bytes_received, or operations")
            sent = field(:bytes_sent, 0)
            received = field(:bytes_received, 0)
            operations = field(:operations, 1)
            sent isa Real && sent >= 0 || error("bytes_sent must be non-negative")
            received isa Real && received >= 0 ||
                error("bytes_received must be non-negative")
            operations isa Real && operations >= 0 ||
                error("operations must be non-negative")
            push!(rows,
                (bytes_sent = Float64(sent),
                    bytes_received = Float64(received), operations = Float64(operations),
                    seconds = elapsed,
                    throughput_bytes_per_second = (Float64(sent) + Float64(received)) /
                                                  max(elapsed, eps(Float64)),
                    operations_per_second = Float64(operations) /
                                            max(elapsed, eps(Float64))))
        end
        rows
    end
end

post(d::Dict, ::Val{:network}) = d[:check_result]

const NetworkSample = @NamedTuple{
    bytes_sent::Float64, bytes_received::Float64, operations::Float64,
    seconds::Float64, throughput_bytes_per_second::Float64,
    operations_per_second::Float64}

function to_table(records::Vector{NetworkSample})
    return Table(
        bytes_sent = [record.bytes_sent for record in records],
        bytes_received = [record.bytes_received for record in records],
        operations = [record.operations for record in records],
        seconds = [record.seconds for record in records],
        throughput_bytes_per_second = [record.throughput_bytes_per_second
                                       for record in records],
        operations_per_second = [record.operations_per_second for record in records])
end

@testitem "Explicit low-noise network records" tags=[:unit, :network] begin
    using PerfChecker

    records = PerfChecker.NetworkSample[(bytes_sent = 64.0,
        bytes_received = 128.0, operations = 2.0, seconds = 0.01,
        throughput_bytes_per_second = 19_200.0, operations_per_second = 200.0)]
    table = PerfChecker.to_table(records)
    @test table.bytes_sent == [64.0]
    @test table.bytes_received == [128.0]
    @test table.throughput_bytes_per_second == [19_200.0]
    @test PerfChecker.default_options(Val(:network))[:track] == "none"
end
