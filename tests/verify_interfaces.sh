#!/bin/bash
# tests/verify_interfaces.sh - Verifies the interface detection logic

# Mocking commands for testing
iw() {
    if [ "$1" == "dev" ]; then
        # Simulate a system with a wlp2s0 WiFi card
        echo "Interface wlp2s0"
        echo "    type managed"
    fi
}
export -f iw

ip() {
    if [ "$1" == "route" ]; then
        # Simulate a system with Ethernet as the default route
        echo "default via 192.168.0.1 dev eth0"
    elif [ "$1" == "-o" ] && [ "$2" == "link" ]; then
        echo "2: eth0: <UP> ..."
        echo "3: wlp2s0: <DOWN> ..."
    fi
}
export -f ip

echo "Running Interface Detection Test..."
echo "------------------------------------"

# Extracting detection logic from install.sh
INTERNET_IF=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)

ALL_WIFI_IFS=$(iw dev | awk '$1=="Interface"{print $2}')

WLAN_IF=""
for iface in $ALL_WIFI_IFS; do
    if [ "$iface" != "$INTERNET_IF" ]; then
        WLAN_IF=$iface
        break
    fi
done

if [ -z "$WLAN_IF" ]; then
    WLAN_IF=$(echo $ALL_WIFI_IFS | awk '{print $1}')
fi
[ -z "$WLAN_IF" ] && WLAN_IF="wlan0"

ETH_IF=$INTERNET_IF
if [ -z "$ETH_IF" ]; then
    ETH_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -v 'lo' | grep -v "$WLAN_IF" | grep -E '^(eth|enp|eno|ens)' | head -n 1)
fi
[ -z "$ETH_IF" ] && ETH_IF="eth0"

echo "Detected WLAN_IF: $WLAN_IF (Expected: wlp2s0)"
echo "Detected ETH_IF: $ETH_IF (Expected: eth0)"

if [ "$WLAN_IF" == "wlp2s0" ] && [ "$ETH_IF" == "eth0" ]; then
    echo "Result: PASS (Case 1: Ethernet + WiFi)"
else
    echo "Result: FAIL (Case 1: Ethernet + WiFi)"
    exit 1
fi

echo ""
echo "Running Two-WiFi Interface Detection Test..."
echo "------------------------------------"

# Scenario: Sharing internet from WiFi 1 (wlan0) to WiFi 2 (wlan1)
iw() {
    if [ "$1" == "dev" ]; then
        echo "Interface wlan0"
        echo "Interface wlan1"
    fi
}
export -f iw

ip() {
    if [ "$1" == "route" ]; then
        echo "default via 192.168.1.1 dev wlan0"
    fi
}
export -f ip

INTERNET_IF=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)
ALL_WIFI_IFS=$(iw dev | awk '$1=="Interface"{print $2}')
WLAN_IF=""
for iface in $ALL_WIFI_IFS; do
    if [ "$iface" != "$INTERNET_IF" ]; then
        WLAN_IF=$iface
        break
    fi
done
[ -z "$WLAN_IF" ] && WLAN_IF="wlan0"
ETH_IF=$INTERNET_IF

echo "Detected WLAN_IF: $WLAN_IF (Expected: wlan1)"
echo "Detected ETH_IF: $ETH_IF (Expected: wlan0)"

if [ "$WLAN_IF" == "wlan1" ] && [ "$ETH_IF" == "wlan0" ]; then
    echo "Result: PASS (Case 2: WiFi + WiFi)"
    exit 0
else
    echo "Result: FAIL (Case 2: WiFi + WiFi)"
    exit 1
fi
