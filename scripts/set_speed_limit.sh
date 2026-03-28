#!/bin/bash
# set_speed_limit.sh - Uses tc to limit speed for an interface or MAC

IFACE=$1
LIMIT_MBPS=$2

if [ -z "$IFACE" ] || [ -z "$LIMIT_MBPS" ]; then
    echo "Usage: $0 <interface> <limit_mbps>"
    exit 1
fi

echo "Setting speed limit of $LIMIT_MBPS Mbps on $IFACE..."

# Clear existing qdiscs
sudo tc qdisc del dev $IFACE root 2>/dev/null || true

# Add htb qdisc
sudo tc qdisc add dev $IFACE root handle 1: htb default 10
sudo tc class add dev $IFACE parent 1: classid 1:1 htb rate ${LIMIT_MBPS}mbit
sudo tc class add dev $IFACE parent 1:1 classid 1:10 htb rate ${LIMIT_MBPS}mbit

echo "Limit applied."
