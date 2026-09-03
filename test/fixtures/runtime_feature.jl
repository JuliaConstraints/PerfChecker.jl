function perf_workload(state)
    (
        bytes_sent = 1_024,
        bytes_received = 2_048,
        packets_sent = 4,
        packets_received = 6,
        operations = 1,
        capture_layer = "fixture",
        attribution_scope = "workload"
    )
end
