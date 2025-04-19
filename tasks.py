from celery_config import celery
from helper import generate_openvpn_config
from config import Config


@celery.task
def generate_certificate(provision_identity):
    """Generate OpenVPN certificate and configuration for a client."""
    try:
        # Generate OpenVPN configuration
        config_path = f"{Config.VPN_CLIENT_DIR}/{provision_identity}.ovpn"
        generate_openvpn_config(provision_identity, config_path)

        return {
            "status": "success",
            "message": "Certificate generated successfully",
            "provision_identity": provision_identity
        }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e),
            "provision_identity": provision_identity
        }