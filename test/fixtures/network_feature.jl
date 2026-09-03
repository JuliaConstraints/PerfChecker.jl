using Sockets

const _fixture_payload = fill(UInt8(0x3c), 131_072)

function perf_workload(state)
    server = listen(ip"127.0.0.1", 0)
    address = getsockname(server)
    server_task = @async begin
        socket = accept(server)
        received = read(socket, length(_fixture_payload))
        write(socket, received)
        close(socket)
    end
    client = connect(ip"127.0.0.1", address[2])
    write(client, _fixture_payload)
    response = read(client, length(_fixture_payload))
    close(client)
    close(server)
    wait(server_task)
    response == _fixture_payload || error("isolated network fixture corruption")
    return nothing
end
