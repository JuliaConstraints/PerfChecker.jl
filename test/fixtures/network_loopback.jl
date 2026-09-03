using Sockets

payload_size = parse(Int, get(ENV, "PERFCHECKER_FIXTURE_BYTES", "262144"))
payload_size > 0 || error("PERFCHECKER_FIXTURE_BYTES must be positive")
payload = fill(UInt8(0x5a), payload_size)

server = listen(ip"127.0.0.1", 0)
address = getsockname(server)
server_task = @async begin
    socket = accept(server)
    received = read(socket, payload_size)
    received == payload || error("server received a corrupted payload")
    write(socket, received)
    close(socket)
end

client = connect(ip"127.0.0.1", address[2])
write(client, payload)
response = read(client, payload_size)
close(client)
close(server)
wait(server_task)
response == payload || error("client received a corrupted payload")

println("loopback-bytes=", payload_size)
