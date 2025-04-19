import os
import subprocess
from config import Config


def generate_openvpn_config(provision_identity, output_path):
    """Generate OpenVPN client configuration file matching the OpenVPN-install script approach."""
    try:
        # Create output directory if it doesn't exist
        os.makedirs(os.path.dirname(output_path), exist_ok=True)

        # Change to the EasyRSA directory
        easyrsa_dir = '/etc/openvpn/server/easy-rsa'
        if not os.path.exists(easyrsa_dir):
            easyrsa_dir = '/etc/openvpn/easy-rsa'  # Fallback to old path
            if not os.path.exists(easyrsa_dir):
                raise Exception(
                    f"EasyRSA directory not found at either /etc/openvpn/server/easy-rsa or /etc/openvpn/easy-rsa")

        os.chdir(easyrsa_dir)
        print(f"dir-------------------- {easyrsa_dir}.........\n")

        # Generate client certificate
        subprocess.run([
            f'./easyrsa', '--batch', '--days=3650', 'build-client-full', provision_identity, 'nopass'
        ], check=True)

        # Define base directory for OpenVPN
        openvpn_dir = '/etc/openvpn/server'
        if not os.path.exists(openvpn_dir):
            openvpn_dir = '/etc/openvpn'  # Fallback to old path

        # Ensure client directory exists
        client_dir = f"{openvpn_dir}/client"
        os.makedirs(client_dir, exist_ok=True)

        # Read the CA certificate
        ca_path = f"{openvpn_dir}/ca.crt"
        try:
            with open(ca_path, 'r') as ca_file:
                ca_cert = ca_file.read()
        except FileNotFoundError:
            raise Exception(f"CA certificate not found at {ca_path}")

        # Read the client certificate
        try:
            cert_cmd = f"sed -ne '/BEGIN CERTIFICATE/,$ p' {easyrsa_dir}/pki/issued/{provision_identity}.crt"
            client_cert = subprocess.check_output(cert_cmd, shell=True).decode('utf-8')
        except subprocess.CalledProcessError:
            # Fallback to simple file read if sed fails
            with open(f"{easyrsa_dir}/pki/issued/{provision_identity}.crt", 'r') as cert_file:
                client_cert = cert_file.read()

        # Read the client key
        try:
            with open(f"{easyrsa_dir}/pki/private/{provision_identity}.key", 'r') as key_file:
                client_key = key_file.read()
        except FileNotFoundError:
            raise Exception(f"Client key not found at {easyrsa_dir}/pki/private/{provision_identity}.key")

        # Read the TLS crypt key if it exists
        tls_crypt = ""
        tc_path = f"{openvpn_dir}/tc.key"
        if os.path.exists(tc_path):
            try:
                tls_crypt = subprocess.check_output(
                    f"sed -ne '/BEGIN OpenVPN Static key/,$ p' {tc_path}",
                    shell=True
                ).decode('utf-8')
                tls_crypt = f"""<tls-crypt>
{tls_crypt}
</tls-crypt>"""
            except subprocess.CalledProcessError:
                # Fallback to simple file read if sed fails
                with open(tc_path, 'r') as tc_file:
                    tls_crypt_content = tc_file.read()
                    tls_crypt = f"""<tls-crypt>
{tls_crypt_content}
</tls-crypt>"""

        # Try to use the common template if it exists
        common_config_path = f"{openvpn_dir}/client-common.txt"
        if os.path.exists(common_config_path):
            with open(common_config_path, 'r') as common_file:
                common_config = common_file.read()
        else:
            # Fallback to hardcoded template if client-common.txt doesn't exist
            common_config = f"""client
dev tun
proto {Config.VPN_PROTO or 'udp'}
remote {Config.VPN_HOST} {Config.VPN_PORT}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA512
cipher AES-256-GCM
ignore-unknown-option block-outside-dns
block-outside-dns
verb 3"""

        # Assemble the complete config
        config = f"""{common_config}
<ca>
{ca_cert}
</ca>
<cert>
{client_cert}
</cert>
<key>
{client_key}
</key>
{tls_crypt}
"""

        # Write configuration to file
        with open(output_path, 'w') as f:
            f.write(config)

        # Also save a copy in the OpenVPN server client directory for easy access
        server_client_path = f"{openvpn_dir}/client/{provision_identity}.ovpn"
        with open(server_client_path, 'w') as f:
            f.write(config)
            print(f"saved on : {server_client_path}")

        return True
    except Exception as e:
        raise Exception(f"Failed to generate OpenVPN configuration: {str(e)}")
