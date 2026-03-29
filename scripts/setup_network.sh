#!/bin/bash
# setup_network.sh - Configures network interfaces and IP forwarding

# Exit on error
set -e

# Configuration
# Attempt to load interfaces from config if exists
IFACES_CONF="/usr/local/etc/easywifi/ifaces.conf"
if [ -f "$IFACES_CONF" ]; then
    source "$IFACES_CONF"
fi

# Attempt to detect interfaces if not already set or loaded
if [ -z "$WLAN_IF" ] || [ -z "$ETH_IF" ]; then
    echo "Detecting network interfaces..."

    # 1. Identify the interface with the default route (Internet source)
    INTERNET_IF=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)

    # 2. Identify all WiFi interfaces
    ALL_WIFI_IFS=""
    if command -v iw >/dev/null 2>&1; then
        ALL_WIFI_IFS=$(iw dev | awk '$1=="Interface"{print $2}')
    else
        ALL_WIFI_IFS=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(wlan|wlp|wls)')
    fi

    # 3. Choose WLAN_IF (the one to host the hotspot)
    if [ -z "$WLAN_IF" ]; then
        # We want a WiFi interface that is NOT the internet source, if possible.
        for iface in $ALL_WIFI_IFS; do
            if [ "$iface" != "$INTERNET_IF" ]; then
                WLAN_IF=$iface
                break
            fi
        done
        # Fallback: if no other WiFi card, use the first one found
        if [ -z "$WLAN_IF" ]; then
            WLAN_IF=$(echo $ALL_WIFI_IFS | awk '{print $1}')
        fi
        [ -z "$WLAN_IF" ] && WLAN_IF="wlan0"
    fi

    # 4. Choose ETH_IF (the internet source)
    if [ -z "$ETH_IF" ]; then
        ETH_IF=$INTERNET_IF
        # Fallback for ETH_IF: if no default route, look for any non-WLAN ethernet-like interface
        if [ -z "$ETH_IF" ]; then
            ETH_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -v 'lo' | grep -v "$WLAN_IF" | grep -E '^(eth|enp|eno|ens)' | head -n 1)
        fi
        [ -z "$ETH_IF" ] && ETH_IF="eth0"
    fi
fi

echo "Using WiFi interface: $WLAN_IF"
echo "Using Ethernet interface: $ETH_IF"

WLAN_IP="192.168.4.1"
DHCP_RANGE="192.168.4.2,192.168.4.200,255.255.255.0,24h"

# Enable IP Forwarding
echo "Enabling IPv4 forwarding..."
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null

# Configure WLAN interface
echo "Configuring $WLAN_IF interface..."
sudo ip link set $WLAN_IF down
sudo ip addr flush dev $WLAN_IF
sudo ip addr add $WLAN_IP/24 dev $WLAN_IF
sudo ip link set $WLAN_IF up

# Ensure interface is up
sleep 2

# NAT and Forwarding rules
echo "Setting up NAT and initial iptables rules..."
sudo iptables -F
sudo iptables -X
sudo iptables -t nat -F
sudo iptables -t nat -X

# Allow established connections
sudo iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A FORWARD -i $WLAN_IF -o $ETH_IF -j ACCEPT
sudo iptables -t nat -A POSTROUTING -o $ETH_IF -j MASQUERADE

# Create a chain for unauthenticated users
sudo iptables -N EASYWIFI_AUTH
sudo iptables -A FORWARD -i $WLAN_IF -j EASYWIFI_AUTH

# Initially, redirect all traffic from WLAN to the local captive portal (port 80)
# But we need to allow DNS (port 53)
sudo iptables -t nat -N EASYWIFI_PORTAL
sudo iptables -t nat -A PREROUTING -i $WLAN_IF -p udp --dport 53 -j ACCEPT
sudo iptables -t nat -A PREROUTING -i $WLAN_IF -p tcp --dport 53 -j ACCEPT

# Redirect HTTP to local portal (Flask app on port 5000)
# But don't redirect if it's already going to the portal IP
sudo iptables -t nat -A PREROUTING -i $WLAN_IF -p tcp -d $WLAN_IP --dport 80 -j ACCEPT
sudo iptables -t nat -A PREROUTING -i $WLAN_IF -p tcp --dport 80 -j REDIRECT --to-ports 5000
# For HTTPS (443), we might need to reject it or redirect, though SSL redirection is tricky.
# Often we just reject it to force the OS to detect a portal via HTTP.
sudo iptables -t nat -A PREROUTING -i $WLAN_IF -p tcp --dport 443 -j REDIRECT --to-ports 5000

# Also allow local access to the portal on port 5000
sudo iptables -A INPUT -i $WLAN_IF -p tcp --dport 5000 -j ACCEPT
# Ensure traffic to the gateway itself is always allowed for basic services
sudo iptables -A INPUT -i $WLAN_IF -p udp --dport 67:68 --sport 67:68 -j ACCEPT

echo "Restarting services to apply network changes..."
sudo systemctl restart hostapd
sudo systemctl restart dnsmasq
sudo systemctl restart easywifi-app

echo "Verifying services..."
for service in hostapd dnsmasq easywifi-app; do
    if systemctl is-active --quiet $service; then
        echo "[OK] $service is running."
    else
        echo "[ERROR] $service failed to start. Check 'systemctl status $service' for details."
    fi
done

echo "Network setup complete."
