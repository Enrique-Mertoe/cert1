# app.py
import requests
from flask import Flask, render_template, request, redirect, url_for, session, flash, send_file
import os
import subprocess
import json
import datetime
import secrets
from functools import wraps

# In-memory user store - replace with database later
USERS = {
    "admin": {
        "password": "admin123",  # Change this!
        "role": "admin"
    }
}

# OpenVPN configuration
OPENVPN_DIR = "/etc/openvpn"
CLIENT_DIR = f"{OPENVPN_DIR}/client"
CA_DIR = f"{OPENVPN_DIR}/easy-rsa/pki"
STATUS_FILE = f"/var/log/openvpn/openvpn-status.log"


# Login required decorator
def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'username' not in session:
            flash('Please log in to access this page', 'danger')
            return redirect(url_for('login'))
        return f(*args, **kwargs)

    return decorated_function


def init(app: Flask):
    @app.route('/')
    @login_required
    def index():
        clients = get_client_list()
        connected = get_connected_clients()
        return render_template('index.html', clients=clients, connected=connected)

    @app.route('/login', methods=['GET', 'POST'])
    def login():
        if request.method == 'POST':
            username = request.form.get('username')
            password = request.form.get('password')

            if username in USERS and USERS[username]['password'] == password:
                session['username'] = username
                session['role'] = USERS[username]['role']
                flash('Login successful', 'success')
                return redirect(url_for('index'))
            else:
                flash('Invalid credentials', 'danger')

        return render_template('login.html')

    @app.route('/logout')
    def logout():
        session.clear()
        flash('Logged out successfully', 'success')
        return redirect(url_for('login'))

    @app.route('/client/<client_name>')
    @login_required
    def client_details(client_name):
        # Get client status
        clients = get_client_list()
        connected = get_connected_clients()

        if client_name not in clients:
            flash('Client not found', 'danger')
            return redirect(url_for('index'))

        client_data = {
            'name': client_name,
            'created': clients[client_name].get('created', 'Unknown'),
            'connected': client_name in connected,
            'ip': connected.get(client_name, {}).get('vpn_ip', 'Not connected'),
            'last_seen': connected.get(client_name, {}).get('last_seen', 'Never')
        }

        return render_template('client_details.html', client=client_data)

    @app.route('/create_client', methods=['GET', 'POST'])
    @login_required
    def create_client():
        if request.method == 'POST':
            client_name = request.form.get('client_name')

            if not client_name or not client_name.isalnum():
                flash('Invalid client name. Use only alphanumeric characters.', 'danger')
                return redirect(url_for('create_client'))

            # Check if client already exists
            if os.path.exists(f"{CLIENT_DIR}/{client_name}.ovpn"):
                flash('Client already exists', 'danger')
                return redirect(url_for('create_client'))

            try:
                # Create client certificate and config
                create_client_certificate(client_name)
                flash(f'Client {client_name} created successfully', 'success')
                return redirect(url_for('client_details', client_name=client_name))
            except Exception as e:
                flash(f'Error creating client: {str(e)}', 'danger')
                return redirect(url_for('create_client'))

        return render_template('create_client.html')

    @app.route('/revoke/<client_name>', methods=['POST'])
    @login_required
    def revoke_client(client_name):
        try:
            revoke_client_certificate(client_name)
            flash(f'Client {client_name} revoked successfully', 'success')
        except Exception as e:
            flash(f'Error revoking client: {str(e)}', 'danger')

        return redirect(url_for('index'))

    @app.route('/delete/<client_name>', methods=['POST'])
    @login_required
    def delete_client(client_name):
        try:
            delete_client_files(client_name)
            flash(f'Client {client_name} deleted successfully', 'success')
        except Exception as e:
            flash(f'Error deleting client: {str(e)}', 'danger')

        return redirect(url_for('index'))

    @app.route('/download/<client_name>')
    @login_required
    def download_config(client_name):
        config_path = f"{CLIENT_DIR}/{client_name}.ovpn"

        if not os.path.exists(config_path):
            flash('Client configuration not found', 'danger')
            return redirect(url_for('index'))

        return send_file(config_path, as_attachment=True)


# Helper functions
def get_client_list():
    clients = {}

    # Check client directory
    if os.path.exists(CLIENT_DIR):
        for file in os.listdir(CLIENT_DIR):
            if file.endswith('.ovpn'):
                client_name = file.replace('.ovpn', '')
                stat = os.stat(f"{CLIENT_DIR}/{file}")
                clients[client_name] = {
                    'created': datetime.datetime.fromtimestamp(stat.st_ctime).strftime('%Y-%m-%d %H:%M:%S'),
                    'file_size': stat.st_size
                }

    return clients


def get_connected_clients():
    connected = {}

    if os.path.exists(STATUS_FILE):
        try:
            with open(STATUS_FILE, 'r') as f:
                lines = f.readlines()
                client_section = False

                for line in lines:
                    if line.strip() == "ROUTING TABLE":
                        client_section = False
                        continue

                    if client_section and line.strip() and not line.startswith('Common Name'):
                        parts = line.strip().split(',')
                        if len(parts) >= 3:
                            client_name = parts[0]
                            real_ip = parts[1]
                            vpn_ip = parts[2].split(':')[0]
                            connected_since = parts[3] if len(parts) > 3 else 'Unknown'
                            connected[client_name] = {
                                'real_ip': real_ip,
                                'vpn_ip': vpn_ip,
                                'last_seen': connected_since
                            }

                    if line.strip() == "CLIENT LIST":
                        client_section = True
        except Exception as e:
            print(f"Error reading VPN status: {e}")

    return connected


def read_file(path):
    with open(path, 'r') as f:
        return f.read()


def create_client_certificate(client_name):
    os.makedirs(CLIENT_DIR, exist_ok=True)

    # Generate client certificate and key
    subprocess.run([
        f"{OPENVPN_DIR}/easy-rsa/easyrsa",
        '--batch',
        '--days=3650',
        "build-client-full",
        client_name,
        "nopass"
    ], check=True)

    # Create client config
    server_ip = requests.get("https://api.ipify.org").text.strip()
    common = read_file("/etc/openvpn/server/client-common.txt")
    template = f"""{common}
<ca>
{open(f"{CA_DIR}/ca.crt").read()}
</ca>
<cert>
{open(f"{CA_DIR}/issued/{client_name}.crt").read()}
</cert>
<key>
{open(f"{CA_DIR}/private/{client_name}.key").read()}
</key>

"""
    # < tls - crypt >
    # {open(f"{OPENVPN_DIR}/server/tc.key").read()}
    # < / tls - crypt >
    with open(f"{CLIENT_DIR}/{client_name}.ovpn", "w") as f:
        f.write(template)


def revoke_client_certificate(client_name):
    # Revoke the client certificate
    subprocess.run([
        f"{OPENVPN_DIR}/easy-rsa/easyrsa",
        "revoke",
        client_name
    ], check=True)

    # Update CRL
    subprocess.run([
        f"{OPENVPN_DIR}/easy-rsa/easyrsa",
        "gen-crl"
    ], check=True)

    # Copy CRL to OpenVPN directory
    subprocess.run([
        "cp",
        f"{CA_DIR}/crl.pem",
        f"{OPENVPN_DIR}/crl.pem"
    ], check=True)

    # Restart OpenVPN
    subprocess.run(["systemctl", "restart", "openvpn@server"], check=False)
    subprocess.run(["systemctl", "restart", "openvpn"], check=False)


def delete_client_files(client_name):
    # Remove client config
    if os.path.exists(f"{CLIENT_DIR}/{client_name}.ovpn"):
        os.remove(f"{CLIENT_DIR}/{client_name}.ovpn")

    # Note: This doesn't remove the certificate from PKI,
    # it should be revoked first using revoke_client_certificate()
