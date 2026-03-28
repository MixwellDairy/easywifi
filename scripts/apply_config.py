import sys
import json
import os

# Paths to template files and target config files
HOSTAPD_TEMPLATE = '/usr/local/etc/easywifi/hostapd.conf.template'
HOSTAPD_CONF = '/etc/hostapd/hostapd.conf'
DNSMASQ_TEMPLATE = '/usr/local/etc/easywifi/dnsmasq.conf.template'
DNSMASQ_CONF = '/etc/dnsmasq.conf'
CONFIG_JSON = os.environ.get('DATA_DIR', '/var/www/easywifi/data') + '/config.json'

def apply_config():
    if not os.path.exists(CONFIG_JSON):
        return

    with open(CONFIG_JSON, 'r') as f:
        config = json.load(f)

    # Apply hostapd config
    if os.path.exists(HOSTAPD_TEMPLATE):
        with open(HOSTAPD_TEMPLATE, 'r') as f:
            content = f.read()
        content = content.replace('ssid=EasyWiFi', f"ssid={config['ssid']}")
        content = content.replace('wpa_passphrase=password123', f"wpa_passphrase={config['wpa_passphrase']}")
        with open(HOSTAPD_CONF, 'w') as f:
            f.write(content)

if __name__ == "__main__":
    apply_config()
