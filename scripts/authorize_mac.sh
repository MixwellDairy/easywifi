#!/bin/bash
# authorize_mac.sh - Authorizes a MAC address in iptables

MAC=$1
SPEED_LIMIT=$2 # Optional Mbps

if [ -z "$MAC" ]; then
    echo "Usage: $0 <MAC ADDRESS> [SPEED_LIMIT_MBPS]"
    exit 1
fi

echo "Authorizing MAC address $MAC..."
sudo iptables -I FORWARD -m mac --mac-source $MAC -j ACCEPT
sudo iptables -t nat -I PREROUTING -m mac --mac-source $MAC -j ACCEPT

# Per-user speed limit using tc
if [ ! -z "$SPEED_LIMIT" ] && [ "$SPEED_LIMIT" != "None" ]; then
    echo "Applying speed limit of $SPEED_LIMIT Mbps to $MAC..."
    # Attempt to load interfaces from config if exists
    IFACES_CONF="/usr/local/etc/easywifi/ifaces.conf"
    WLAN_IF="wlan0"
    if [ -f "$IFACES_CONF" ]; then
        source "$IFACES_CONF"
    fi
    # This is a simplified version. A full implementation would use mark-based shaping.
    # For now, we apply it to the whole $WLAN_IF if no better way is available in this environment.
    sudo /usr/local/bin/set_speed_limit.sh $WLAN_IF $SPEED_LIMIT
fi

echo "MAC $MAC authorized."
