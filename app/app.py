import os
import json
import csv
import datetime
import subprocess
from flask import Flask, render_template, request, redirect, url_for, session, make_response

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'default_secret_key')

DATA_DIR = os.environ.get('DATA_DIR', '/var/www/easywifi/data')
CONFIG_FILE = os.path.join(DATA_DIR, 'config.json')
USERS_CSV = os.path.join(DATA_DIR, 'users.csv')
SESSIONS_FILE = os.path.join(DATA_DIR, 'sessions.json')

def load_config():
    if not os.path.exists(CONFIG_FILE):
        default_config = {
            'ssid': 'EasyWiFi',
            'wpa_passphrase': 'password123',
            'tos_text': 'Please agree to our terms of service.',
            'tos_enabled': True,
            'admin_password': 'admin'
        }
        save_config(default_config)
    with open(CONFIG_FILE, 'r') as f:
        return json.load(f)

def save_config(config):
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f, indent=4)

def save_user(name, email, mac):
    with open(USERS_CSV, 'a', newline='') as f:
        writer = csv.writer(f)
        writer.writerow([datetime.datetime.now().isoformat(), name, email, mac])

def get_authenticated_macs():
    if not os.path.exists(SESSIONS_FILE):
        return []
    with open(SESSIONS_FILE, 'r') as f:
        return json.load(f)

def get_mac_from_ip(ip):
    try:
        # Run arp command to find MAC address
        output = subprocess.check_output(['arp', '-n', ip]).decode('utf-8')
        for line in output.split('\n'):
            if ip in line:
                parts = line.split()
                if len(parts) >= 3:
                    return parts[2]
    except Exception:
        pass
    return None

def add_authenticated_mac(mac):
    if not mac: return
    macs = get_authenticated_macs()
    if mac not in macs:
        macs.append(mac)
        with open(SESSIONS_FILE, 'w') as f:
            json.dump(macs, f)
        # Authorize in iptables
        subprocess.run(['sudo', '/usr/local/bin/authorize_mac.sh', mac])

@app.route('/')
def index():
    client_ip = request.remote_addr
    mac = get_mac_from_ip(client_ip)

    # Check if already authenticated
    if mac and mac in get_authenticated_macs():
        return "Already connected! You can now browse the internet."

    config = load_config()
    return render_template('portal.html', config=config, mac=mac)

@app.route('/login', methods=['POST'])
def login():
    name = request.form.get('name')
    email = request.form.get('email')
    mac = request.form.get('mac')

    save_user(name, email, mac)
    if mac:
        add_authenticated_mac(mac)

    return "Successfully connected! You can now browse the internet."

@app.route('/admin', methods=['GET', 'POST'])
def admin():
    config = load_config()
    if request.method == 'POST':
        if session.get('admin_logged_in'):
            # Update settings
            config['ssid'] = request.form.get('ssid')
            config['wpa_passphrase'] = request.form.get('wpa_passphrase')
            config['tos_text'] = request.form.get('tos_text')
            config['tos_enabled'] = 'tos_enabled' in request.form
            save_config(config)
            # Apply config to system files and restart hostapd
            subprocess.run(['python3', '/usr/local/bin/apply_config.py'])
            subprocess.run(['sudo', 'systemctl', 'restart', 'hostapd'])
            return redirect(url_for('admin'))
        else:
            # Check login
            if request.form.get('password') == config['admin_password']:
                session['admin_logged_in'] = True
                return redirect(url_for('admin'))

    if not session.get('admin_logged_in'):
        return render_template('admin_login.html')

    users = []
    if os.path.exists(USERS_CSV):
        with open(USERS_CSV, 'r') as f:
            reader = csv.reader(f)
            users = list(reader)

    return render_template('admin_panel.html', config=config, users=users)

@app.route('/admin/logout')
def admin_logout():
    session.pop('admin_logged_in', None)
    return redirect(url_for('admin'))

if __name__ == '__main__':
    if not os.path.exists(DATA_DIR):
        os.makedirs(DATA_DIR)
    port = int(os.environ.get('PORT', 80))
    app.run(host='0.0.0.0', port=port)
