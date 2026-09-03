#!/bin/sh
set -u

wrapper=$1
result=$2
interface=$3
limit=$4
external=$5
dns_servers=$6
shift 6

if [ "$external" != "1" ]; then
    exec unshare --user --map-root-user --net \
        sh "$wrapper" "$result" "$interface" "$limit" "$@"
fi

command -v slirp4netns >/dev/null 2>&1 || {
    echo "slirp4netns is required for external connectivity" >&2
    exit 125
}

state=$(mktemp -d)
pid_file="$state/namespace.pid"
start_fifo="$state/start"
ready_fifo="$state/ready"
mkfifo "$start_fifo" "$ready_fifo"

namespace_process=
slirp_process=
cleanup() {
    [ -n "$namespace_process" ] && kill "$namespace_process" >/dev/null 2>&1 || true
    [ -n "$slirp_process" ] && kill "$slirp_process" >/dev/null 2>&1 || true
    rm -rf "$state"
}
trap cleanup EXIT INT TERM

unshare --user --map-root-user --net --mount sh -c '
    pid_file=$1
    start_fifo=$2
    wrapper=$3
    result=$4
    interface=$5
    limit=$6
    dns_servers=$7
    shift 7
    printf "%s\n" "$$" > "$pid_file"
    read -r _ < "$start_fifo"
    if [ "$dns_servers" != "-" ]; then
        resolv=$(mktemp)
        printf "%s\n" "$dns_servers" | tr "," "\n" | sed "s/^/nameserver /" > "$resolv"
        printf "options timeout:2 attempts:2\n" >> "$resolv"
        mount --bind "$resolv" /etc/resolv.conf
    fi
    exec sh "$wrapper" "$result" "$interface" "$limit" "$@"
' sh "$pid_file" "$start_fifo" "$wrapper" "$result" "$interface" "$limit" \
    "$dns_servers" "$@" &
namespace_process=$!

attempt=0
while [ ! -s "$pid_file" ]; do
    kill -0 "$namespace_process" >/dev/null 2>&1 || {
        wait "$namespace_process"
        exit $?
    }
    attempt=$((attempt + 1))
    [ "$attempt" -lt 200 ] || {
        echo "network namespace did not become ready" >&2
        exit 125
    }
    sleep 0.01
done
namespace_pid=$(cat "$pid_file")

# Keep both FIFO ends open so setup cannot deadlock. slirp4netns writes one
# readiness byte after configuring the TAP interface and default route.
exec 3<> "$ready_fifo"
slirp4netns --configure --mtu=65520 --disable-host-loopback \
    --ready-fd=3 "$namespace_pid" "$interface" >&2 &
slirp_process=$!
dd bs=1 count=1 <&3 >/dev/null 2>&1 || {
    wait "$slirp_process"
    exit $?
}
printf 'go\n' > "$start_fifo"

wait "$namespace_process"
status=$?
kill "$slirp_process" >/dev/null 2>&1 || true
wait "$slirp_process" >/dev/null 2>&1 || true
namespace_process=
slirp_process=
exit "$status"
