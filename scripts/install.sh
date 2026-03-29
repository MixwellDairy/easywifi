#!/bin/bash
# install.sh - Installs and configures EasyWiFi on Ubuntu

set -e

echo "Installing dependencies..."
sudo apt-get update
sudo apt-get install -y hostapd dnsmasq python3-flask iptables net-tools iproute2

# Detect interfaces and save to a config file for later use
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
# We want a WiFi interface that is NOT the internet source, if possible.
WLAN_IF=""
for iface in $ALL_WIFI_IFS; do
    if [ "$iface" != "$INTERNET_IF" ]; then
        WLAN_IF=$iface
        break
    fi
done

# Fallback: if no other WiFi card, use the first one found (or wlan0)
if [ -z "$WLAN_IF" ]; then
    WLAN_IF=$(echo $ALL_WIFI_IFS | awk '{print $1}')
fi
[ -z "$WLAN_IF" ] && WLAN_IF="wlan0"

# 4. Choose ETH_IF (the internet source)
ETH_IF=$INTERNET_IF

# Fallback for ETH_IF: if no default route, look for any non-WLAN ethernet-like interface
if [ -z "$ETH_IF" ]; then
    ETH_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -v 'lo' | grep -v "$WLAN_IF" | grep -E '^(eth|enp|eno|ens)' | head -n 1)
fi
[ -z "$ETH_IF" ] && ETH_IF="eth0"

echo "Selected WLAN_IF: $WLAN_IF"
echo "Selected ETH_IF: $ETH_IF"

# Directory for configuration and scripts
INSTALL_DIR="/usr/local/etc/easywifi"
sudo mkdir -p $INSTALL_DIR
sudo mkdir -p /var/www/easywifi/data

# Save interface info to the config directory
echo "WLAN_IF=$WLAN_IF" | sudo tee $INSTALL_DIR/ifaces.conf > /dev/null
echo "ETH_IF=$ETH_IF" | sudo tee -a $INSTALL_DIR/ifaces.conf > /dev/null

# Copy application files
echo "Copying application files..."
sudo mkdir -p /var/www/easywifi/static/uploads
sudo cp -r app/* /var/www/easywifi/
sudo chown -R www-data:www-data /var/www/easywifi/data
sudo chown -R www-data:www-data /var/www/easywifi/static/uploads

# Copy scripts
echo "Copying scripts..."
sudo cp scripts/*.sh /usr/local/bin/
# Also patch authorize_mac.sh with the detected WLAN_IF
sudo sed -i "s/wlan0/$WLAN_IF/g" /usr/local/bin/authorize_mac.sh
sudo cp scripts/apply_config.py /usr/local/bin/
sudo chmod +x /usr/local/bin/*.sh
sudo cp scripts/*.template $INSTALL_DIR/

# Configure NetworkManager to ignore the WiFi interface if it's running
if systemctl is-active --quiet NetworkManager; then
    echo "Configuring NetworkManager to ignore $WLAN_IF..."
    sudo mkdir -p /etc/NetworkManager/conf.d
    sudo bash -c "cat <<EOF > /etc/NetworkManager/conf.d/easywifi.conf
[keyfile]
unmanaged-devices=interface-name:$WLAN_IF
EOF"
    sudo systemctl reload NetworkManager || true
fi

# Systemd services
echo "Setting up systemd services..."
sudo bash -c 'cat <<EOF > /etc/systemd/system/easywifi-app.service
[Unit]
Description=EasyWiFi Captive Portal App
After=network.target

[Service]
ExecStart=/usr/bin/python3 -u /var/www/easywifi/app.py
WorkingDirectory=/var/www/easywifi
Environment=PYTHONPATH=/var/www/easywifi
StandardOutput=append:/var/log/easywifi-app.log
StandardError=append:/var/log/easywifi-app.log
User=root
Restart=always

[Install]
WantedBy=multi-user.target
EOF'

# Configure hostapd to use our config file
sudo sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd || true

sudo systemctl daemon-reload
sudo systemctl enable easywifi-app
sudo systemctl restart easywifi-app || echo "Warning: easywifi-app failed to start. Check /var/log/easywifi-app.log"

# Apply initial configuration to hostapd and dnsmasq
echo "Applying initial system configuration..."
sudo python3 /usr/local/bin/apply_config.py

echo "Starting services..."
sudo systemctl unmask hostapd || true
sudo systemctl enable hostapd
sudo systemctl enable dnsmasq

# Run network setup automatically to make it plug-and-play
echo "Running network setup..."
sudo /usr/local/bin/setup_network.sh

echo ""
echo "EasyWiFi Installation complete."
echo "------------------------------------------------"
echo "Detected WiFi: $WLAN_IF"
echo "Detected Ethernet: $ETH_IF"
echo "------------------------------------------------"
echo "The 'EasyWiFi' network should now be visible."
