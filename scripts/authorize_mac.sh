#!/bin/bash
# authorize_mac.sh - Authorizes a MAC address in iptables

MAC=$1

if [ -z "$MAC" ]; then
    echo "Usage: $0 <MAC ADDRESS>"
    exit 1
fi

echo "Authorizing MAC address $MAC..."
sudo iptables -I FORWARD -m mac --mac-source $MAC -j ACCEPT
# Optionally, skip redirection for authorized MACs in nat table:
sudo iptables -t nat -I PREROUTING -m mac --mac-source $MAC -j ACCEPT

echo "MAC $MAC authorized."
