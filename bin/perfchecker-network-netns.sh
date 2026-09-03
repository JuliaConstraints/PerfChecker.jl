#!/bin/sh
set -u
PATH="$HOME/.juliaup/bin:$PATH"
export PATH

result=$1
interface=$2
limit=$3
shift 3

ip link set "$interface" up
stats=/sys/class/net/$interface/statistics
read_counter() {
    if [ -r "$stats/$1" ]; then
        tr -d '\n' < "$stats/$1"
    else
        printf '0'
    fi
}

nft_capture=0
if command -v nft >/dev/null 2>&1 &&
    nft add table inet perfchecker >/dev/null 2>&1 &&
    nft 'add chain inet perfchecker input { type filter hook input priority -300; policy accept; }' >/dev/null 2>&1 &&
    nft 'add chain inet perfchecker output { type filter hook output priority -300; policy accept; }' >/dev/null 2>&1 &&
    nft add rule inet perfchecker input counter >/dev/null 2>&1 &&
    nft add rule inet perfchecker output counter >/dev/null 2>&1; then
    nft_capture=1
fi

before_ns=$(date +%s%N)
before_tx_bytes=$(read_counter tx_bytes)
before_rx_bytes=$(read_counter rx_bytes)
before_tx_packets=$(read_counter tx_packets)
before_rx_packets=$(read_counter rx_packets)
before_tx_dropped=$(read_counter tx_dropped)
before_rx_dropped=$(read_counter rx_dropped)

PERFCHECKER_NETWORK_ISOLATION=linux-netns-v1 \
    timeout --signal=TERM --kill-after=2s "${limit}s" "$@"
status=$?

after_ns=$(date +%s%N)
after_tx_bytes=$(read_counter tx_bytes)
after_rx_bytes=$(read_counter rx_bytes)
after_tx_packets=$(read_counter tx_packets)
after_rx_packets=$(read_counter rx_packets)
after_tx_dropped=$(read_counter tx_dropped)
after_rx_dropped=$(read_counter rx_dropped)

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    'perfchecker-network-capture/1' "$interface" "$before_ns" "$after_ns" \
    "$before_tx_bytes" "$after_tx_bytes" "$before_rx_bytes" "$after_rx_bytes" \
    "$before_tx_packets" "$after_tx_packets" "$before_rx_packets" \
    "$after_rx_packets" > "$result"
printf '%s\t%s\t%s\t%s\t%s\n' "$before_tx_dropped" "$after_tx_dropped" \
    "$before_rx_dropped" "$after_rx_dropped" "$status" >> "$result"

if [ "$nft_capture" -eq 1 ]; then
    nft -j list table inet perfchecker > "${result}.nft"
fi

exit "$status"
