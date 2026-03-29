# EasyWiFi: Captive Portal for Linux-Ubuntu

EasyWiFi is a lightweight solution to host a WiFi hotspot with a customizable captive portal on Ubuntu. It allows users to connect to a WPA2-secured WiFi network, after which they are redirected to a portal to provide their name and email, and agree to a custom Terms of Service before gaining internet access.

## Features

- **WiFi Hotspot**: Shares your Ethernet internet connection via a WiFi card (using `hostapd` and `dnsmasq`).
- **Captive Portal**: Forces users to register (Name, Email, TOS) before accessing the web.
- **Admin Panel**: Web-based interface to:
  - Change WiFi SSID and Password.
  - Enable/Disable and edit Terms of Service.
  - View a list of registered users and their MAC addresses.
  - Securely access settings via a password.
- **User Persistence**: Remembers users by MAC address so they only have to register once (unless their session is cleared).
- **Data Export**: Saves all user data to a local CSV file.

## Requirements

- Ubuntu (tested on 22.04+)
- An Ethernet connection for internet.
- A WiFi card that supports Access Point (AP) mode.

## Quick Installation

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/MixwellDairy/easywifi.git
    cd easywifi
    ```

    **Alternative: Download Archive** (if `git clone` asks for credentials):
    ```bash
    wget https://github.com/MixwellDairy/easywifi/archive/refs/heads/main.tar.gz
    tar -xzf main.tar.gz
    cd easywifi-main
    ```

2.  **Run the installation script**:
    ```bash
    sudo bash scripts/install.sh
    ```

3.  **Initial Network Setup**:
    Update the interface names (`WLAN_IF` and `ETH_IF`) in `/usr/local/bin/setup_network.sh` to match your system. Then run:
    ```bash
    sudo /usr/local/bin/setup_network.sh
    ```

4.  **Configure WiFi and Admin Password**:
    Open the admin panel by visiting `http://192.168.4.1/admin` on a device connected to the network or the host itself.
    - Default SSID: `EasyWiFi`
    - Default WiFi Password: `password123`
    - Default Admin Password: `admin` (You should change this in the code/config).

## File Structure

- `/var/www/easywifi/`: Flask application files.
- `/var/www/easywifi/data/`:
    - `config.json`: System settings (SSID, TOS, etc.).
    - `users.csv`: Collected name and email data.
    - `sessions.json`: Currently authenticated MAC addresses.
- `/usr/local/bin/`: Network management scripts (`setup_network.sh`, `authorize_mac.sh`).
- `/usr/local/etc/easywifi/`: Configuration templates for `hostapd` and `dnsmasq`.

## How it Works

1.  **Hostapd** creates the WiFi access point.
2.  **Dnsmasq** provides DHCP and DNS, pointing all DNS queries to the local host's IP (`192.168.4.1`).
3.  **Iptables** rules redirect all HTTP traffic from unauthenticated MAC addresses to the Flask app on port 80.
4.  When a user submits the form, the `authorize_mac.sh` script is called to add an `ACCEPT` rule in `iptables` for their MAC address, bypassing the redirection.

## Disclaimer

This tool is for educational purposes. Always ensure you comply with local laws regarding public WiFi hosting and data privacy (GDPR, etc.).
