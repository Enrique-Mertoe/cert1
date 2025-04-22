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