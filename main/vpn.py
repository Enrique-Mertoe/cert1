#!/usr/bin/env python3
import os
import subprocess
import sys
import tempfile

# !/usr/bin/env python3
import os
import subprocess
import sys
import re
import argparse

import requests


class OpenVPNManager:
    def __init__(self):
        # Base paths used in OpenVPN
        self.base_dir = "/etc/openvpn/server"
        self.easy_rsa_dir = f"{self.base_dir}/easy-rsa"
        self.pki_dir = f"{self.easy_rsa_dir}/pki"
        self.script_dir = os.path.dirname(os.path.realpath(__file__))

        # Check if user has root privileges
        if os.geteuid() != 0:
            print("This script must be run as root.")
            sys.exit(1)

        # Check if OpenVPN is installed
        if not os.path.exists(f"{self.base_dir}/server.conf"):
            print("OpenVPN is not installed. Please install it first.")
            sys.exit(1)

    def get_group_name(self):
        """Get the correct group name based on OS"""
        # Check for Debian/Ubuntu vs CentOS/Fedora/RHEL
        if os.path.exists("/etc/debian_version"):
            return "nogroup"
        else:
            return "nobody"

    def list_clients(self):
        """List all existing clients"""
        if not os.path.exists(f"{self.pki_dir}/index.txt"):
            print("No clients found.")
            return []

        try:
            # Get list of valid certificates from index.txt
            result = subprocess.run(
                f"tail -n +2 {self.pki_dir}/index.txt | grep '^V' | cut -d '=' -f 2",
                shell=True, check=True, text=True, capture_output=True
            )

            clients = result.stdout.strip().split('\n')
            if clients == ['']:
                print("No clients found.")
                return []

            # Print clients with numbers
            print("\nAvailable clients:")
            for i, client in enumerate(clients, 1):
                print(f"{i}) {client}")

            return clients
        except subprocess.CalledProcessError as e:
            print(f"Error listing clients: {e}")
            return []

    def create_client(self, client_name):
        """Create a new OpenVPN client"""
        # Sanitize client name
        sanitized_client = re.sub(r'[^0-9a-zA-Z_-]', '_', client_name)

        if not sanitized_client:
            print("Invalid client name.")
            return False

        # Check if client already exists
        if os.path.exists(f"{self.pki_dir}/issued/{sanitized_client}.crt"):
            print(f"Client '{sanitized_client}' already exists.")
            return False

        try:
            # Change to easy-rsa directory
            # os.chdir(self.easy_rsa_dir)

            # Generate client certificates
            print(f"Creating client '{sanitized_client}'...")
            subprocess.run(
                [
                    "docker", "exec", "host", "/etc/openvpn/server/easy-rsa/easyrsa",
                    "--batch",
                    "--days=3650",
                    "build-client-full",
                    sanitized_client,
                    "nopass"
                ],
                check=True
            )

            # Generate client config file
            self.generate_client_config(sanitized_client)

            print(f"Client '{sanitized_client}' created successfully.")
            print(f"Configuration file saved to: /etc/openvpn/client/{client_name}.ovpn")
            return True
        except subprocess.CalledProcessError as e:
            raise
            print(f"Error creating client: {e}")
            return False

    def generate_client_config(self, client_name):
        """Generate client configuration file"""
        try:
            # Get server protocol and port
            with open(f"{self.base_dir}/server.conf", 'r') as f:
                server_conf = f.read()

            proto_match = re.search(r'^proto\s+(\w+)', server_conf, re.MULTILINE)
            port_match = re.search(r'^port\s+(\d+)', server_conf, re.MULTILINE)
            local_match = re.search(r'^local\s+([^\s]+)', server_conf, re.MULTILINE)

            protocol = proto_match.group(1) if proto_match else "udp"
            port = port_match.group(1) if port_match else "1194"
            ip = requests.get("https://api.ipify.org").text.strip()

            # Create client config file
            client_file = f"/etc/openvpn/client/{client_name}.ovpn"

            with open(client_file, 'w') as f:
                # Common client settings
                f.write(f"client\n")
                f.write(f"dev tun\n")
                f.write(f"proto {protocol}\n")
                f.write(f"remote {ip} {port}\n")
                f.write(f"resolv-retry infinite\n")
                f.write(f"nobind\n")
                f.write(f"persist-key\n")
                f.write(f"persist-tun\n")
                f.write(f"remote-cert-tls server\n")
                f.write(f"auth SHA512\n")
                f.write(f"ignore-unknown-option block-outside-dns\n")
                f.write(f"verb 3\n")
                pki = "/etc/openvpn/easy-rsa/pki"
                # Add CA certificate
                f.write("<ca>\n")
                with open(f"{pki}/ca.crt", 'r') as ca_file:
                    f.write(ca_file.read())
                f.write("</ca>\n")

                # Add client certificate
                f.write("<cert>\n")
                cert_cmd = f"sed -ne '/BEGIN CERTIFICATE/,$ p' {pki}/issued/{client_name}.crt"
                cert_content = subprocess.run(cert_cmd, shell=True, check=True, text=True, capture_output=True).stdout
                f.write(cert_content)
                f.write("</cert>\n")

                # Add client key
                f.write("<key>\n")
                with open(f"{pki}/private/{client_name}.key", 'r') as key_file:
                    f.write(key_file.read())
                f.write("</key>\n")

                # Add TLS key
                f.write("<tls-crypt>\n")
                tls_cmd = f"sed -ne '/BEGIN OpenVPN Static key/,$ p' {self.base_dir}/tc.key"
                tls_content = subprocess.run(tls_cmd, shell=True, check=True, text=True, capture_output=True).stdout
                f.write(tls_content)
                f.write("</tls-crypt>\n")

            # Set permissions
            os.chmod(client_file, 0o600)

            return True
        except Exception as e:
            print(f"Error generating client config: {e}")
            return False

    def revoke_client(self, client_selector):
        """Revoke an existing client certificate"""
        clients = self.list_clients()

        if not clients:
            return False

        # Check if client_selector is a number or name
        client = None
        try:
            # If it's a number
            index = int(client_selector) - 1
            if 0 <= index < len(clients):
                client = clients[index]
            else:
                print(f"Invalid client number: {client_selector}")
                return False
        except ValueError:
            # If it's a name
            if client_selector in clients:
                client = client_selector
            else:
                print(f"Client '{client_selector}' not found.")
                return False

        print(f"Revoking certificate for client '{client}'...")

        try:
            # Change to easy-rsa directory
            os.chdir(self.easy_rsa_dir)

            # Revoke certificate
            subprocess.run(
                f"./easyrsa --batch revoke '{client}'",
                shell=True, check=True
            )

            # Generate new CRL
            subprocess.run(
                f"./easyrsa --batch --days=3650 gen-crl",
                shell=True, check=True
            )

            # Clean up files
            if os.path.exists(f"{self.base_dir}/crl.pem"):
                os.remove(f"{self.base_dir}/crl.pem")

            if os.path.exists(f"{self.pki_dir}/reqs/{client}.req"):
                os.remove(f"{self.pki_dir}/reqs/{client}.req")

            if os.path.exists(f"{self.pki_dir}/private/{client}.key"):
                os.remove(f"{self.pki_dir}/private/{client}.key")

            # Copy new CRL to server directory
            subprocess.run(
                f"cp {self.pki_dir}/crl.pem {self.base_dir}/crl.pem",
                shell=True, check=True
            )

            # Update permissions
            group_name = self.get_group_name()
            subprocess.run(
                f"chown nobody:{group_name} {self.base_dir}/crl.pem",
                shell=True, check=True
            )

            print(f"Client '{client}' revoked successfully.")
            return True
        except subprocess.CalledProcessError as e:
            print(f"Error revoking client: {e}")
            return False

    def restart_service(self):
        """Restart the OpenVPN service"""
        try:
            print("Restarting OpenVPN service...")
            subprocess.run(
                "systemctl restart openvpn-server@server.service",
                shell=True, check=True
            )
            print("OpenVPN service restarted successfully.")
            return True
        except subprocess.CalledProcessError as e:
            print(f"Error restarting OpenVPN service: {e}")
            return False


def main():
    parser = argparse.ArgumentParser(description='OpenVPN Client Manager')
    subparsers = parser.add_subparsers(dest='command', help='Command to run')

    # List clients command
    list_parser = subparsers.add_parser('list', help='List all OpenVPN clients')

    # Create client command
    create_parser = subparsers.add_parser('create', help='Create a new OpenVPN client')
    create_parser.add_argument('name', help='Client name')

    # Revoke client command
    revoke_parser = subparsers.add_parser('revoke', help='Revoke an existing OpenVPN client')
    revoke_parser.add_argument('client', help='Client number or name')

    # Restart service command
    restart_parser = subparsers.add_parser('restart', help='Restart the OpenVPN service')

    args = parser.parse_args()

    # Initialize OpenVPN manager
    manager = OpenVPNManager()

    # Execute command
    if args.command == 'list':
        manager.list_clients()
    elif args.command == 'create':
        manager.create_client(args.name)
    elif args.command == 'revoke':
        manager.revoke_client(args.client)
    elif args.command == 'restart':
        manager.restart_service()
    else:
        parser.print_help()


if __name__ == '__main__':
    main()


def get_vpn_clients():
    """Get list of connected OpenVPN clients and their virtual IPs"""
    # Read from OpenVPN status file
    status_file = "/etc/openvpn/openvpn-status.log"
    clients = {}

    try:
        with open(status_file, 'r') as f:
            lines = f.readlines()
            client_section = False

            for line in lines:
                if line.strip() == "ROUTING TABLE":
                    client_section = False
                    continue

                if client_section and line.strip() and not line.startswith('Common Name'):
                    parts = line.strip().split(',')
                    if len(parts) >= 3:
                        common_name = parts[0]
                        real_ip = parts[1]
                        vpn_ip = parts[2].split(':')[0]
                        clients[common_name] = {
                            'real_ip': real_ip,
                            'vpn_ip': vpn_ip
                        }

                if line.strip() == "CLIENT LIST":
                    client_section = True
    except Exception as e:
        print(f"Error reading VPN status: {e}")

    return clients


def communicate_with_mikrotik(client_name):
    """Send commands to a specific Mikrotik router"""
    clients = get_vpn_clients()

    if client_name not in clients:
        return {"error": "Client not connected to VPN"}

    vpn_ip = clients[client_name]['vpn_ip']

    # Use RouterOS API to communicate with the Mikrotik
    # Example using librouteros
    try:
        import routeros_api
        connection = routeros_api.RouterOsApiPool(
            vpn_ip,
            username='admin',
            password='password',
            port=8728
        )
        api = connection.get_api()

        # Example: Get system resource info
        resource = api.get_resource('/system/resource')
        return resource.get()
    except Exception as e:
        return {"error": f"Failed to communicate with router: {e}"}
    finally:
        if 'connection' in locals():
            connection.disconnect()
