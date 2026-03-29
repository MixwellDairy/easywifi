#!/bin/bash
# install.sh - Installs and configures EasyWiFi on Ubuntu

set -e

echo "Installing dependencies..."
sudo apt-get update
sudo apt-get install -y hostapd dnsmasq python3-flask iptables net-tools iproute2

# Detect interfaces and save to a config file for later use
WLAN_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(wlan|wlp|wls)' | head -n 1)
[ -z "$WLAN_IF" ] && WLAN_IF="wlan0"
ETH_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|enp|eno|ens)' | head -n 1)
[ -z "$ETH_IF" ] && ETH_IF="eth0"

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
# Source interface config into the setup scripts during copying
sudo cp scripts/*.sh /usr/local/bin/
# Patch the setup_network script with the detected interfaces for convenience
sudo sed -i "s/^WLAN_IF=.*/WLAN_IF=\"$WLAN_IF\"/" /usr/local/bin/setup_network.sh
sudo sed -i "s/^ETH_IF=.*/ETH_IF=\"$ETH_IF\"/" /usr/local/bin/setup_network.sh
sudo cp scripts/apply_config.py /usr/local/bin/
sudo chmod +x /usr/local/bin/*.sh
sudo cp scripts/*.template $INSTALL_DIR/

# Systemd services
echo "Setting up systemd services..."
sudo bash -c 'cat <<EOF > /etc/systemd/system/easywifi-app.service
[Unit]
Description=EasyWiFi Captive Portal App
After=network.target

[Service]
ExecStart=/usr/bin/python3 /var/www/easywifi/app.py
WorkingDirectory=/var/www/easywifi
Environment=PYTHONPATH=/var/www/easywifi
User=root
Restart=always

[Install]
WantedBy=multi-user.target
EOF'

# Configure hostapd to use our config file
sudo sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd || true

sudo systemctl daemon-reload
sudo systemctl enable easywifi-app
sudo systemctl unmask hostapd || true
sudo systemctl enable hostapd

echo "Installation complete. Please run 'sudo /usr/local/bin/setup_network.sh' once to initialize network rules."
