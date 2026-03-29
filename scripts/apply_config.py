import sys
import json
import os
import subprocess

# Paths to template files and target config files
HOSTAPD_TEMPLATE = '/usr/local/etc/easywifi/hostapd.conf.template'
HOSTAPD_CONF = '/etc/hostapd/hostapd.conf'
DNSMASQ_TEMPLATE = '/usr/local/etc/easywifi/dnsmasq.conf.template'
DNSMASQ_CONF = '/etc/dnsmasq.conf'
IFACES_CONF = '/usr/local/etc/easywifi/ifaces.conf'
CONFIG_JSON = os.environ.get('DATA_DIR', '/var/www/easywifi/data') + '/config.json'

def get_interfaces():
    wlan_if = "wlan0"
    if os.path.exists(IFACES_CONF):
        with open(IFACES_CONF, 'r') as f:
            for line in f:
                if line.startswith('WLAN_IF='):
                    wlan_if = line.split('=')[1].strip()
    return wlan_if

def apply_config():
    wlan_if = get_interfaces()
    if not os.path.exists(CONFIG_JSON):
        return

    with open(CONFIG_JSON, 'r') as f:
        config = json.load(f)

    # Apply hostapd config
    if os.path.exists(HOSTAPD_TEMPLATE):
        with open(HOSTAPD_TEMPLATE, 'r') as f:
            content = f.read()
        content = content.replace('interface=wlan0', f"interface={wlan_if}")
        content = content.replace('ssid=EasyWiFi', f"ssid={config['ssid']}")
        content = content.replace('wpa_passphrase=password123', f"wpa_passphrase={config['wpa_passphrase']}")
        with open(HOSTAPD_CONF, 'w') as f:
            f.write(content)

    # Apply dnsmasq config for blocking
    if os.path.exists(DNSMASQ_TEMPLATE):
        with open(DNSMASQ_TEMPLATE, 'r') as f:
            dns_content = f.read()
        dns_content = dns_content.replace('interface=wlan0', f"interface={wlan_if}")

        # Add blocking: address=/domain/192.168.4.1
        # This will redirect blocked domains to the local portal
        block_rules = ""
        for site in config.get('blocked_sites', []):
            block_rules += f"address=/{site['domain']}/192.168.4.1\n"

        with open(DNSMASQ_CONF, 'w') as f:
            f.write(dns_content + "\n" + block_rules)

    # Apply global speed limit
    limit = config.get('global_speed_limit')
    if limit:
        subprocess.run(['sudo', '/usr/local/bin/set_speed_limit.sh', wlan_if, str(limit)])
    else:
        subprocess.run(['sudo', '/usr/local/bin/set_speed_limit.sh', wlan_if, '0'])

if __name__ == "__main__":
    apply_config()
