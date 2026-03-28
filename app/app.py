import os
import json
import csv
import datetime
import subprocess
from flask import Flask, render_template, request, redirect, url_for, session, make_response, jsonify
from werkzeug.utils import secure_filename

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'default_secret_key')

DATA_DIR = os.environ.get('DATA_DIR', '/var/www/easywifi/data')
CONFIG_FILE = os.path.join(DATA_DIR, 'config.json')
USERS_CSV = os.path.join(DATA_DIR, 'users.csv')
SESSIONS_FILE = os.path.join(DATA_DIR, 'sessions.json')
UPLOAD_FOLDER = 'app/static/uploads'
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}

def allowed_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def load_config():
    if not os.path.exists(CONFIG_FILE):
        default_config = {
            'ssid': 'EasyWiFi',
            'wpa_passphrase': 'password123',
            'tos_text': 'Please agree to our terms of service.',
            'tos_enabled': True,
            'admin_password': 'admin',
            'portal_title': 'Join WiFi',
            'portal_welcome': 'Welcome to our free WiFi!',
            'portal_color': '#007bff',
            'portal_bg_color': '#f4f4f4',
            'portal_button_text': 'Connect',
            'connected_message': 'Successfully connected! You can now browse the internet.',
            'logo_filename': None,
            'blocked_sites': [], # List of dictionaries: {"domain": "...", "header": "..."}
            'global_speed_limit': None, # in Mbps
            'per_user_speed_limit': None, # in Mbps
            'time_limit_minutes': 60,
            'reconnect_delay_hours': 24
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
        try:
            data = json.load(f)
            # handle old list format
            if isinstance(data, list) and len(data) > 0 and isinstance(data[0], str):
                return [{"mac": m, "timestamp": datetime.datetime.now().isoformat()} for m in data]
            return data
        except:
            return []

def cleanup_sessions():
    config = load_config()
    macs = get_authenticated_macs()
    now = datetime.datetime.now()
    valid_macs = []

    for m in macs:
        ts = datetime.datetime.fromisoformat(m['timestamp'])
        diff = now - ts
        if diff.total_seconds() < config['time_limit_minutes'] * 60:
            valid_macs.append(m)
        else:
            # Revoke in iptables
            subprocess.run(['sudo', 'iptables', '-D', 'FORWARD', '-m', 'mac', '--mac-source', m['mac'], '-j', 'ACCEPT'])
            subprocess.run(['sudo', 'iptables', '-t', 'nat', '-D', 'PREROUTING', '-m', 'mac', '--mac-source', m['mac'], '-j', 'ACCEPT'])

    with open(SESSIONS_FILE, 'w') as f:
        json.dump(valid_macs, f)

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
    # macs will now store a dictionary with timestamp
    # check if mac exists
    found = False
    for m in macs:
        if m['mac'] == mac:
            m['timestamp'] = datetime.datetime.now().isoformat()
            found = True
            break

    if not found:
        config = load_config()
        limit = config.get('per_user_speed_limit')
        macs.append({'mac': mac, 'timestamp': datetime.datetime.now().isoformat()})
        # Authorize in iptables
        subprocess.run(['sudo', '/usr/local/bin/authorize_mac.sh', mac, str(limit)])

    with open(SESSIONS_FILE, 'w') as f:
        json.dump(macs, f)

@app.route('/')
def index():
    cleanup_sessions()
    client_ip = request.remote_addr
    mac = get_mac_from_ip(client_ip)
    host_header = request.headers.get('Host')
    config = load_config()

    # Check for website blocking
    for site in config.get('blocked_sites', []):
        if site['domain'] in (host_header or ''):
            return render_template('blocked.html', header=site['header'])

    # Check if already authenticated
    sessions = get_authenticated_macs()
    authenticated_macs = [m['mac'] for m in sessions]

    # In local testing, mac might be None or a mock value
    if client_ip == '127.0.0.1' and not mac:
        mac = 'LOCAL_TEST_MAC'

    if mac and mac in authenticated_macs:
        return render_template('connected.html', config=config)


    # Check for reconnect delay (Optional: could be implemented by checking USERS_CSV)

    return render_template('portal.html', config=config, mac=mac)

@app.route('/login', methods=['POST'])
def login():
    name = request.form.get('name')
    email = request.form.get('email')
    mac = request.form.get('mac')
    if request.remote_addr == '127.0.0.1' and not mac:
        mac = 'LOCAL_TEST_MAC'

    save_user(name, email, mac)
    if mac:
        add_authenticated_mac(mac)

    config = load_config()
    return render_template('connected.html', config=config)

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

            # Styling
            config['portal_title'] = request.form.get('portal_title')
            config['portal_welcome'] = request.form.get('portal_welcome')
            config['portal_color'] = request.form.get('portal_color')
            config['portal_bg_color'] = request.form.get('portal_bg_color')
            config['portal_button_text'] = request.form.get('portal_button_text')
            config['connected_message'] = request.form.get('connected_message')

            # Website Blocking
            blocked_raw = request.form.get('blocked_sites_raw', '')
            blocked_list = []
            for line in blocked_raw.split('\n'):
                if ',' in line:
                    domain, header = line.split(',', 1)
                    blocked_list.append({"domain": domain.strip(), "header": header.strip()})
                elif line.strip():
                    blocked_list.append({"domain": line.strip(), "header": "Policy violation"})
            config['blocked_sites'] = blocked_list

            # Limits
            config['global_speed_limit'] = float(request.form.get('global_speed_limit')) if request.form.get('global_speed_limit') else None
            config['per_user_speed_limit'] = float(request.form.get('per_user_speed_limit')) if request.form.get('per_user_speed_limit') else None
            config['time_limit_minutes'] = int(request.form.get('time_limit_minutes', 60))
            config['reconnect_delay_hours'] = int(request.form.get('reconnect_delay_hours', 24))

            # Logo Upload
            if 'logo' in request.files:
                file = request.files['logo']
                if file and allowed_file(file.filename):
                    filename = secure_filename(file.filename)
                    # Clear old files
                    if config['logo_filename']:
                        old_path = os.path.join(UPLOAD_FOLDER, config['logo_filename'])
                        if os.path.exists(old_path): os.remove(old_path)

                    file.save(os.path.join(UPLOAD_FOLDER, filename))
                    config['logo_filename'] = filename

            save_config(config)
            # Apply config to system files and restart hostapd
            subprocess.run(['python3', '/usr/local/bin/apply_config.py'])
            subprocess.run(['sudo', 'systemctl', 'restart', 'hostapd'])
            # Potentially update dnsmasq for blocking
            subprocess.run(['sudo', 'systemctl', 'restart', 'dnsmasq'])
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

@app.route('/admin/api/traffic')
def admin_api_traffic():
    if not session.get('admin_logged_in'):
        return jsonify([]), 403

    # Mock traffic data for now, will implement real logic in the next step
    # We will parse /var/log/dnsmasq.log and iptables -L -v -n
    traffic = [
        {"mac": "00:11:22:33:44:55", "down": "1.2 MB", "up": "0.1 MB", "domains": ["google.com", "github.com"]},
        {"mac": "66:77:88:99:AA:BB", "down": "0.5 MB", "up": "0.05 MB", "domains": ["example.org"]}
    ]
    return jsonify(traffic)

if __name__ == '__main__':
    if not os.path.exists(DATA_DIR):
        os.makedirs(DATA_DIR)
    port = int(os.environ.get('PORT', 80))
    app.run(host='0.0.0.0', port=port)
