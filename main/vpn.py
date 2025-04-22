#!/usr/bin/env python3
import os
import subprocess
import sys
import tempfile


class OpenVPNAutomation:
    bash_script = ''

    def __init__(self):
        # Store the bash script in a variable
        self.script_path = '/tmp/openvpn-install.sh'
        #         self. = '''#!/bin/bash
        # # The entire OpenVPN installation script content goes here
        # # This is the Nyr/openvpn-install script
        # '''

        # Check if user has root privileges
        if os.geteuid() != 0:
            print("This script must be run as root.")
            sys.exit(1)

    @classmethod
    def init(cls, file):
        current_dir = os.path.dirname(os.path.abspath(file))

        # Path to the file you want to read
        file_path = os.path.join(current_dir, "w.sh")

        # Read the file
        with open(file_path, "r") as f:
            content = f.read()

        cls.bash_script = content

    def save_script(self):
        """Save the bash script to a temporary file"""
        with open(self.script_path, 'w') as f:
            f.write(self.bash_script)
        # Make the script executable
        os.chmod(self.script_path, 0o755)
        print(f"OpenVPN script saved to {self.script_path}")

    def run_script(self):
        """Run the OpenVPN installation script"""
        try:
            subprocess.run([self.script_path], check=True)
        except subprocess.CalledProcessError as e:
            print(f"Error running OpenVPN script: {e}")
            sys.exit(1)

    def create_client(self, client_name):
        """Create a new OpenVPN client"""
        # Check if OpenVPN is installed
        if not os.path.exists('/etc/openvpn/server/server.conf'):
            print("OpenVPN is not installed. Please install it first.")
            sys.exit(1)

        # Prepare the environment variables for the subprocess
        env = os.environ.copy()

        # Run the script with option 1 (Add a new client)
        process = subprocess.Popen(
            [self.script_path],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            env=env
        )

        # Send '1' to select option 1
        output, error = process.communicate(input='1\n' + client_name + '\n')

        if process.returncode != 0:
            print(f"Error creating client: {error}")
            sys.exit(1)

        print(output)

        # script_dir = os.path.dirname(os.path.realpath(__file__))
        return os.path.join("/etc/openvpn/client", f"{client_name}.ovpn")

    def revoke_client(self, client_number):
        """Revoke an existing OpenVPN client"""
        # Check if OpenVPN is installed
        if not os.path.exists('/etc/openvpn/server/server.conf'):
            print("OpenVPN is not installed. Please install it first.")
            sys.exit(1)

        # Run the script with option 2 (Revoke an existing client)
        process = subprocess.Popen(
            [self.script_path],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True
        )

        # Send '2' to select option 2, then the client number, then 'y' to confirm
        output, error = process.communicate(input='2\n' + str(client_number) + '\ny\n')

        if process.returncode != 0:
            print(f"Error revoking client: {error}")
            sys.exit(1)

        print(output)

    def remove_openvpn(self):
        """Remove OpenVPN installation"""
        # Check if OpenVPN is installed
        if not os.path.exists('/etc/openvpn/server/server.conf'):
            print("OpenVPN is not installed.")
            return

        # Run the script with option 3 (Remove OpenVPN)
        process = subprocess.Popen(
            [self.script_path],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True
        )

        # Send '3' to select option 3, then 'y' to confirm
        output, error = process.communicate(input='3\ny\n')

        if process.returncode != 0:
            print(f"Error removing OpenVPN: {error}")
            sys.exit(1)

        print(output)

    def automate_installation(self, ip, protocol='udp', port='1194', dns='1', client='client'):
        """Automate the OpenVPN installation with predefined answers"""
        # Check if OpenVPN is already installed
        if os.path.exists('/etc/openvpn/server/server.conf'):
            print("OpenVPN is already installed.")
            return

        # Run the install script with automated answers
        process = subprocess.Popen(
            [self.script_path],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True
        )

        # Prepare answers for the script prompts
        # Format: IP, protocol, port, DNS server, client name, any key to continue
        answers = f"{ip}\n{protocol}\n{port}\n{dns}\n{client}\n\n"

        output, error = process.communicate(input=answers)

        if process.returncode != 0:
            print(f"Error during automated installation: {error}")
            sys.exit(1)

        print(output)

        # Return the path to the client config file
        script_dir = os.path.dirname(os.path.realpath(__file__))
        return os.path.join(script_dir, f"{client}.ovpn")


def main():
    # Parse command-line arguments
    import argparse
    parser = argparse.ArgumentParser(description='Automate OpenVPN installation and management')
    parser.add_argument('action', choices=['install', 'add-client', 'revoke-client', 'remove'],
                        help='Action to perform')
    parser.add_argument('--ip', help='Server IP address for installation')
    parser.add_argument('--protocol', default='udp', choices=['udp', 'tcp'],
                        help='Protocol (udp or tcp)')
    parser.add_argument('--port', default='1194', help='Port number')
    parser.add_argument('--dns', default='1', choices=['1', '2', '3', '4', '5', '6', '7'],
                        help='DNS server option')
    parser.add_argument('--client', help='Client name')
    parser.add_argument('--client-number', type=int, help='Client number to revoke')

    args = parser.parse_args()

    openvpn = OpenVPNAutomation()
    openvpn.save_script()

    if args.action == 'install':
        if not args.ip:
            print("IP address is required for installation.")
            sys.exit(1)
        if not args.client:
            args.client = 'client'

        openvpn.automate_installation(
            args.ip,
            args.protocol,
            args.port,
            args.dns,
            args.client
        )

    elif args.action == 'add-client':
        if not args.client:
            print("Client name is required.")
            sys.exit(1)

        openvpn.create_client(args.client)

    elif args.action == 'revoke-client':
        if not args.client_number:
            print("Client number is required.")
            sys.exit(1)

        openvpn.revoke_client(args.client_number)

    elif args.action == 'remove':
        openvpn.remove_openvpn()


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
