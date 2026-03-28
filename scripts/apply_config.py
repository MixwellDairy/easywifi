import sys
import json
import os
import subprocess

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

    # Apply dnsmasq config for blocking
    if os.path.exists(DNSMASQ_TEMPLATE):
        with open(DNSMASQ_TEMPLATE, 'r') as f:
            dns_content = f.read()

        # Add blocking: address=/domain/192.168.4.1
        # This will redirect blocked domains to the local portal
        block_rules = ""
        for site in config.get('blocked_sites', []):
            block_rules += f"address=/{site['domain']}/192.168.4.1\n"

        with open(DNSMASQ_CONF, 'w') as f:
            f.write(dns_content + "\n" + block_rules)

    # Apply global speed limit
    if config.get('global_speed_limit'):
        subprocess.run(['sudo', '/usr/local/bin/set_speed_limit.sh', 'wlan0', str(config['global_speed_limit'])])

if __name__ == "__main__":
    apply_config()
