"""
This instance is hosted on a VPN server that will help to auto generate or provision new clients.
It returns certs for each client and also stores them for remote connection with Mikrotik
It wil be used by the main site (myisp.com) to generate new vpn clients for mikrotik connection
 and listen for a successful connection as well as sending mikrotik commands to perform specif jobs.
It will also be accessed with Mikrotik to fetch these certs and install them on behalf of the user
"""
import os
from flask import Flask, jsonify, send_file, send_from_directory
import openvpn_api
from celery.result import AsyncResult
from config import Config
from security import generate_secret, require_secret
from tasks import generate_certificate

app = Flask(__name__)
app.config.from_object(Config)

# Initialize OpenVPN API
v = openvpn_api.VPN(Config.VPN_HOST, Config.VPN_PORT)


@app.route('/')
def hello_world():
    # REQUEST_COUNT.labels(method='GET', endpoint='/', status='401').inc()
    return jsonify({"status": "unauthorized"}), 401


@app.route('/mikrotik/openvpn/create_provision/<provision_identity>', methods=["POST"])
def mtk_create_new_provision(provision_identity):
    """Create a new openVPN client with given name.
    provision_identity: its just like name instance  (e.g client1,client2,...)
    """
    # with REQUEST_LATENCY.labels(endpoint='/create_provision').time():
    try:
        # Validate provision identity
        # validate_provision_identity(provision_identity)

        # Check if client already exists
        client_conf_path = f"{Config.VPN_CLIENT_DIR}/{provision_identity}.ovpn"
        if os.path.exists(client_conf_path):
            # REQUEST_COUNT.labels(method='POST', endpoint='/create_provision', status='400').inc()
            return jsonify({"error": "Client already exists"}), 400

        # Start async certificate generation
        task = generate_certificate.delay(provision_identity)

        # Generate and return the secret
        secret = generate_secret(provision_identity)

        # REQUEST_COUNT.labels(method='POST', endpoint='/create_provision', status='202').inc()
        return jsonify({
            "status": "processing",
            "task_id": task.id,
            "provision_identity": provision_identity,
            "secret": secret
        }), 202

    except ValueError as e:
        # REQUEST_COUNT.labels(method='POST', endpoint='/create_provision', status='400').inc()
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        # REQUEST_COUNT.labels(method='POST', endpoint='/create_provision', status='500').inc()
        print(e)
        return jsonify({"error": "Internal server error"}), 500


@app.route('/mikrotik/openvpn/task/<task_id>')
def get_task_status(task_id):
    """Get the status of a certificate generation task."""
    # with REQUEST_LATENCY.labels(endpoint='/task_status').time():
    task_result = AsyncResult(task_id)

    if task_result.ready():
        if task_result.successful():
            result = task_result.get()
            if result['status'] == 'success':
                # REQUEST_COUNT.labels(method='GET', endpoint='/task_status', status='200').inc()
                return jsonify(result), 200
            else:
                # REQUEST_COUNT.labels(method='GET', endpoint='/task_status', status='400').inc()
                return jsonify(result), 400
        else:
            # REQUEST_COUNT.labels(method='GET', endpoint='/task_status', status='500').inc()
            return jsonify({
                "status": "error",
                "message": str(task_result.result)
            }), 500
    else:
        # REQUEST_COUNT.labels(method='GET', endpoint='/task_status', status='202').inc()
        return jsonify({
            "status": "processing",
            "state": task_result.state
        }), 202


@app.route("/mikrotik/openvpn/<provision_identity>/<secret>")
@require_secret
def mtk_openvpn(provision_identity, secret):
    """Returning openVPN client of a given provision_identity"""
    try:
        path = f"{Config.VPN_CLIENT_DIR}/{provision_identity}.ovpn"
        if not os.path.exists(path):
            return jsonify({"error": "Configuration not found"}), 404
        return send_file(path, as_attachment=True)
    except Exception as e:
        return jsonify({"error": "Internal server error"}), 500


@app.route("/mikrotik/hotspot/<provision_identity>/<secret>/<form>")
@require_secret
def mtk_hostpot_ui(provision_identity, secret, form):
    """Returning the hotspot login page.
        @:var form: Either login.html or rlogin.html
    """
    try:
        if form not in ["login.html", "rlogin.html"]:
            return jsonify({"error": "Form not found"}), 404
        return send_from_directory(Config.HOTSPOT_TEMPLATE_DIR, form)
    except Exception as e:
        return jsonify({"error": "Internal server error"}), 500


if __name__ == '__main__':
    app.run(debug=False)  # Set debug=False in production
