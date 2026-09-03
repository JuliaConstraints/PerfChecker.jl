prep(d::Dict, block::Expr, ::Val{:network}) = quote
    $block
    nothing
end

function default_options(::Val{:network})
    return Dict(:threads => 1, :track => "none", :repeat => true,
        :network_repetitions => 5)
end

prep(d::Dict, block::Expr, ::Val{:network_interface}) = quote
    $block
    nothing
end

function default_options(::Val{:network_interface})
    return Dict(:threads => 1, :track => "none", :repeat => true,
        :network_repetitions => 3, :network_interface => "auto")
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
                if payload isa NamedTuple
                    return haskey(payload, name) ? getproperty(payload, name) : default
                end
                return haskey(payload, name) ? payload[name] :
                       haskey(payload, String(name)) ? payload[String(name)] : default
            end
            any(
                name -> haskey(payload, name) ||
                        (payload isa AbstractDict && haskey(payload, String(name))),
                (:bytes_sent, :bytes_received, :operations)) || error(
                "network workloads must report bytes_sent, bytes_received, or operations")
            sent = field(:bytes_sent, 0)
            received = field(:bytes_received, 0)
            operations = field(:operations, 1)
            packets_sent = field(:packets_sent, 0)
            packets_received = field(:packets_received, 0)
            connections = field(:connections, 0)
            retransmissions = field(:retransmissions, 0)
            sent isa Real && sent >= 0 || error("bytes_sent must be non-negative")
            received isa Real && received >= 0 ||
                error("bytes_received must be non-negative")
            operations isa Real && operations >= 0 ||
                error("operations must be non-negative")
            packets_sent isa Real && packets_sent >= 0 ||
                error("packets_sent must be non-negative")
            packets_received isa Real && packets_received >= 0 ||
                error("packets_received must be non-negative")
            connections isa Real && connections >= 0 ||
                error("connections must be non-negative")
            retransmissions isa Real && retransmissions >= 0 ||
                error("retransmissions must be non-negative")
            push!(rows,
                (bytes_sent = Float64(sent),
                    bytes_received = Float64(received), operations = Float64(operations),
                    packets_sent = Float64(packets_sent),
                    packets_received = Float64(packets_received),
                    connections = Float64(connections),
                    retransmissions = Float64(retransmissions),
                    seconds = elapsed,
                    throughput_bytes_per_second = (Float64(sent) + Float64(received)) /
                                                  max(elapsed, eps(Float64)),
                    operations_per_second = Float64(operations) /
                                            max(elapsed, eps(Float64)),
                    capture_layer = String(field(:capture_layer, "application")),
                    attribution_scope = String(field(:attribution_scope, "workload")),
                    interface = String(field(:interface, "")),
                    latency_context = String(field(:latency_context, "end_to_end_informative"))))
        end
        rows
    end
end

post(d::Dict, ::Val{:network}) = NetworkSample[record for record in d[:check_result]]

const NetworkSample = @NamedTuple{
    bytes_sent::Float64, bytes_received::Float64, operations::Float64,
    packets_sent::Float64, packets_received::Float64, connections::Float64,
    retransmissions::Float64,
    seconds::Float64, throughput_bytes_per_second::Float64,
    operations_per_second::Float64, capture_layer::String,
    attribution_scope::String, interface::String, latency_context::String}

function to_table(records::Vector{NetworkSample})
    return Table(
        bytes_sent = [record.bytes_sent for record in records],
        bytes_received = [record.bytes_received for record in records],
        operations = [record.operations for record in records],
        packets_sent = [record.packets_sent for record in records],
        packets_received = [record.packets_received for record in records],
        connections = [record.connections for record in records],
        retransmissions = [record.retransmissions for record in records],
        seconds = [record.seconds for record in records],
        throughput_bytes_per_second = [record.throughput_bytes_per_second
                                       for record in records],
        operations_per_second = [record.operations_per_second for record in records],
        capture_layer = [record.capture_layer for record in records],
        attribution_scope = [record.attribution_scope for record in records],
        interface = [record.interface for record in records],
        latency_context = [record.latency_context for record in records])
end

"Monotonic counters observed on one operating-system network interface."
struct NetworkInterfaceSnapshot
    interface::String
    timestamp_ns::UInt64
    bytes_sent::UInt64
    bytes_received::UInt64
    packets_sent::UInt64
    packets_received::UInt64
    discarded_sent::UInt64
    discarded_received::UInt64
    provider::String
end

const NetworkInterfaceSample = @NamedTuple{
    bytes_sent::Float64, bytes_received::Float64,
    packets_sent::Float64, packets_received::Float64,
    discarded_sent::Float64, discarded_received::Float64,
    seconds::Float64, workload_seconds::Float64,
    capture_layer::String, attribution_scope::String,
    interface::String, latency_context::String}

function network_interface_capabilities()
    supported = Sys.iswindows() || Sys.islinux()
    return Dict{String, Any}(
        "schema_version" => "perfchecker-network-capabilities/1",
        "supported" => supported,
        "provider" =>
            Sys.iswindows() ? "windows-netadapter-statistics" :
            Sys.islinux() ? "linux-sysfs-netdev" : "unavailable",
        "capture_layer" => "interface",
        "counters" =>
            supported ?
            ["bytes_sent", "bytes_received", "packets_sent",
                "packets_received", "discarded_sent", "discarded_received"] : String[],
        "attribution" => "host_interface",
        "requires_isolated_interface_for_package_attribution" => true,
        "latency_semantics" => "workload wall time; informative for remote endpoints",
        "retransmissions" => "unavailable in the portable interface collector")
end

function _windows_network_snapshots()
    script = "Get-NetAdapterStatistics | Select-Object Name,ReceivedBytes,SentBytes,ReceivedUnicastPackets,SentUnicastPackets,ReceivedMulticastPackets,SentMulticastPackets,ReceivedBroadcastPackets,SentBroadcastPackets,ReceivedDiscardedPackets,OutboundDiscardedPackets | ConvertTo-Json -Compress"
    output = read(
        Cmd(["powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive",
            "-Command", script]),
        String)
    parsed = JSON.parse(output)
    rows = parsed isa AbstractVector ? parsed : Any[parsed]
    return [NetworkInterfaceSnapshot(String(row["Name"]), time_ns(),
                UInt64(get(row, "SentBytes", 0)), UInt64(get(row, "ReceivedBytes", 0)),
                UInt64(get(row, "SentUnicastPackets", 0) +
                       get(row, "SentMulticastPackets", 0) +
                       get(row, "SentBroadcastPackets", 0)),
                UInt64(get(row, "ReceivedUnicastPackets", 0) +
                       get(row, "ReceivedMulticastPackets", 0) +
                       get(row, "ReceivedBroadcastPackets", 0)),
                UInt64(get(row, "OutboundDiscardedPackets", 0)),
                UInt64(get(row, "ReceivedDiscardedPackets", 0)),
                "windows-netadapter-statistics") for row in rows]
end

function _linux_network_snapshots()
    root = "/sys/class/net"
    isdir(root) || return NetworkInterfaceSnapshot[]
    counter(interface, name) = parse(UInt64,
        strip(read(joinpath(root, interface, "statistics", name), String)))
    return [NetworkInterfaceSnapshot(interface, time_ns(),
                counter(interface, "tx_bytes"), counter(interface, "rx_bytes"),
                counter(interface, "tx_packets"), counter(interface, "rx_packets"),
                counter(interface, "tx_dropped"), counter(interface, "rx_dropped"),
                "linux-sysfs-netdev")
            for interface in sort!(readdir(root))]
end

function _network_snapshots()
    Sys.iswindows() && return _windows_network_snapshots()
    Sys.islinux() && return _linux_network_snapshots()
    throw(ArgumentError("network interface counters are unavailable on $(Sys.KERNEL)"))
end

"Take a network-interface snapshot. `auto` selects the busiest non-loopback interface."
function network_interface_snapshot(interface::AbstractString = "auto")
    snapshots = _network_snapshots()
    isempty(snapshots) && throw(ErrorException("no network interface counters found"))
    requested = String(interface)
    if lowercase(requested) != "auto"
        index = findfirst(snapshot -> snapshot.interface == requested, snapshots)
        index === nothing && throw(ArgumentError("unknown network interface $requested"))
        return snapshots[index]
    end
    candidates = filter(snapshot -> lowercase(snapshot.interface) ∉ ("lo", "loopback"),
        snapshots)
    isempty(candidates) && (candidates = snapshots)
    return last(sort!(candidates;
        by = snapshot -> snapshot.bytes_sent + snapshot.bytes_received))
end

function _counter_delta(after::UInt64, before::UInt64)
    after >= before || throw(ArgumentError("network interface counter decreased"))
    return Float64(after - before)
end

"Compute counter deltas for two snapshots of the same interface."
function network_interface_delta(before::NetworkInterfaceSnapshot,
        after::NetworkInterfaceSnapshot; workload_seconds::Real =
        Float64(after.timestamp_ns - before.timestamp_ns) / 1.0e9,
        capture_layer::AbstractString = "interface",
        attribution_scope::AbstractString = "host_interface",
        latency_context::AbstractString = "end_to_end_informative")
    before.interface == after.interface || throw(ArgumentError(
        "network snapshots refer to different interfaces"))
    counter_seconds = Float64(after.timestamp_ns - before.timestamp_ns) / 1.0e9
    workload_seconds >= 0 || throw(ArgumentError(
        "network workload duration must be non-negative"))
    return (bytes_sent = _counter_delta(after.bytes_sent, before.bytes_sent),
        bytes_received = _counter_delta(after.bytes_received, before.bytes_received),
        packets_sent = _counter_delta(after.packets_sent, before.packets_sent),
        packets_received = _counter_delta(after.packets_received, before.packets_received),
        discarded_sent = _counter_delta(after.discarded_sent, before.discarded_sent),
        discarded_received = _counter_delta(after.discarded_received,
            before.discarded_received), seconds = counter_seconds,
        workload_seconds = Float64(workload_seconds),
        capture_layer = String(capture_layer), attribution_scope = String(attribution_scope),
        interface = before.interface, latency_context = String(latency_context))
end

"Measure interface counters around a workload. Isolation is required for package attribution."
function measure_network_interface(workload::Function; interface::AbstractString = "auto",
        repetitions::Integer = 1)
    repetitions > 0 || throw(ArgumentError("network repetitions must be positive"))
    samples = NetworkInterfaceSample[]
    selected = String(interface)
    for _ in 1:Int(repetitions)
        before = network_interface_snapshot(selected)
        selected = before.interface
        started = time_ns()
        workload()
        elapsed = (time_ns() - started) / 1.0e9
        after = network_interface_snapshot(selected)
        push!(samples, network_interface_delta(before, after; workload_seconds = elapsed))
    end
    return samples
end

function check(d::Dict, block::Expr, ::Val{:network_interface})
    repetitions = Int(get(d, :network_repetitions, 3))
    interface = String(get(d, :network_interface, "auto"))
    return quote
        function interface_snapshots()
            if Sys.iswindows()
                script = raw"""Get-NetAdapterStatistics | ForEach-Object { @($_.Name,$_.SentBytes,$_.ReceivedBytes,($_.SentUnicastPackets+$_.SentMulticastPackets+$_.SentBroadcastPackets),($_.ReceivedUnicastPackets+$_.ReceivedMulticastPackets+$_.ReceivedBroadcastPackets),$_.OutboundDiscardedPackets,$_.ReceivedDiscardedPackets) -join "`t" }"""
                output = read(
                    Cmd(["powershell.exe", "-NoLogo", "-NoProfile",
                        "-NonInteractive", "-Command", script]),
                    String)
                rows = NamedTuple[]
                for line in split(chomp(output), '\n')
                    isempty(strip(line)) && continue
                    fields = split(chomp(line), '\t'; keepempty = true)
                    length(fields) == 7 || error("invalid Windows adapter counter row")
                    push!(rows,
                        (interface = String(fields[1]), timestamp_ns = time_ns(),
                            bytes_sent = Base.parse(UInt64, fields[2]),
                            bytes_received = Base.parse(UInt64, fields[3]),
                            packets_sent = Base.parse(UInt64, fields[4]),
                            packets_received = Base.parse(UInt64, fields[5]),
                            discarded_sent = Base.parse(UInt64, fields[6]),
                            discarded_received = Base.parse(UInt64, fields[7])))
                end
                return rows
            elseif Sys.islinux()
                root = "/sys/class/net"
                counter(name, field) = Base.parse(UInt64,
                    strip(read(joinpath(root, name, "statistics", field), String)))
                return [(interface = name, timestamp_ns = time_ns(),
                            bytes_sent = counter(name, "tx_bytes"),
                            bytes_received = counter(name, "rx_bytes"),
                            packets_sent = counter(name, "tx_packets"),
                            packets_received = counter(name, "rx_packets"),
                            discarded_sent = counter(name, "tx_dropped"),
                            discarded_received = counter(name, "rx_dropped"))
                        for name in sort!(readdir(root))]
            end
            error("network interface counters are unavailable on " * string(Sys.KERNEL))
        end
        function select_snapshot(requested)
            snapshots = interface_snapshots()
            isempty(snapshots) && error("no network interface counters found")
            if lowercase(requested) != "auto"
                index = findfirst(row -> row.interface == requested, snapshots)
                index === nothing && error("unknown network interface " * requested)
                return snapshots[index]
            end
            candidates = filter(row -> lowercase(row.interface) ∉ ("lo", "loopback"),
                snapshots)
            isempty(candidates) && (candidates = snapshots)
            return last(sort!(candidates;
                by = row -> row.bytes_sent + row.bytes_received))
        end
        let selected_interface = $interface, rows = NamedTuple[]
            for _ in 1:($repetitions)
                before = select_snapshot(selected_interface)
                selected_interface = before.interface
                started = time_ns()
                $block
                workload_seconds = (time_ns() - started) / 1.0e9
                after = select_snapshot(selected_interface)
                delta(name) = begin
                    current = getproperty(after, name)
                    previous = getproperty(before, name)
                    current >= previous || error("network interface counter decreased")
                    Float64(current - previous)
                end
                push!(rows,
                    (bytes_sent = delta(:bytes_sent),
                        bytes_received = delta(:bytes_received),
                        packets_sent = delta(:packets_sent),
                        packets_received = delta(:packets_received),
                        discarded_sent = delta(:discarded_sent),
                        discarded_received = delta(:discarded_received),
                        seconds = Float64(after.timestamp_ns - before.timestamp_ns) / 1.0e9,
                        workload_seconds = workload_seconds,
                        capture_layer = "interface", attribution_scope = "host_interface",
                        interface = selected_interface,
                        latency_context = "end_to_end_informative"))
            end
            rows
        end
    end
end

function post(d::Dict, ::Val{:network_interface})
    NetworkInterfaceSample[record for record in d[:check_result]]
end

function to_table(records::Vector{NetworkInterfaceSample})
    names = propertynames(first(records))
    columns = NamedTuple{names}(Tuple(
        [getproperty(record, name) for record in records] for name in names))
    return Table(columns)
end

@testitem "Explicit low-noise network records" tags=[:unit, :network] begin
    using PerfChecker

    records = PerfChecker.NetworkSample[(bytes_sent = 64.0,
        bytes_received = 128.0, operations = 2.0, packets_sent = 2.0,
        packets_received = 3.0, connections = 1.0, retransmissions = 0.0,
        seconds = 0.01, throughput_bytes_per_second = 19_200.0,
        operations_per_second = 200.0, capture_layer = "application",
        attribution_scope = "workload", interface = "",
        latency_context = "end_to_end_informative")]
    table = PerfChecker.to_table(records)
    @test table.bytes_sent == [64.0]
    @test table.bytes_received == [128.0]
    @test table.throughput_bytes_per_second == [19_200.0]
    @test table.packets_sent == [2.0]
    @test PerfChecker.default_options(Val(:network))[:track] == "none"
end

@testitem "Network interface counter delta" tags=[:unit, :network] begin
    using PerfChecker

    before = NetworkInterfaceSnapshot("fixture", UInt64(1), UInt64(100), UInt64(200),
        UInt64(10), UInt64(20), UInt64(1), UInt64(2), "fixture")
    after = NetworkInterfaceSnapshot("fixture", UInt64(2), UInt64(180), UInt64(260),
        UInt64(14), UInt64(25), UInt64(1), UInt64(3), "fixture")
    delta = network_interface_delta(before, after; workload_seconds = 0.5)
    @test delta.bytes_sent == 80
    @test delta.bytes_received == 60
    @test delta.packets_sent == 4
    @test delta.packets_received == 5
    @test delta.workload_seconds == 0.5
    @test delta.attribution_scope == "host_interface"
    @test network_interface_capabilities()["capture_layer"] == "interface"
end
