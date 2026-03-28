#!/bin/bash
# setup_network.sh - Configures network interfaces and IP forwarding

# Exit on error
set -e

# Configuration
WLAN_IF="wlan0"      # Change as needed
ETH_IF="eth0"        # Change as needed
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

# Redirect HTTP to local portal
sudo iptables -t nat -A PREROUTING -i $WLAN_IF -p tcp --dport 80 -j REDIRECT --to-ports 80
# For HTTPS (443), we might need to reject it or redirect, though SSL redirection is tricky.
# Often we just reject it to force the OS to detect a portal via HTTP.
sudo iptables -t nat -A PREROUTING -i $WLAN_IF -p tcp --dport 443 -j REDIRECT --to-ports 80

echo "Network setup complete."
