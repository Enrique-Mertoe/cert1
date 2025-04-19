import hashlib
import hmac
from functools import wraps
from flask import request, jsonify
from config import Config


def generate_secret(provision_identity):
    """Generate a secret for a provision identity."""
    message = f"{provision_identity}{Config.SECRET_KEY}".encode()
    return hmac.new(
        Config.SECRET_KEY.encode(),
        message,
        hashlib.sha256
    ).hexdigest()


def validate_provision_identity(provision_identity):
    """Validate a provision identity."""
    if not provision_identity or len(provision_identity) > 32:
        raise ValueError("Invalid provision identity")
    return True


def require_secret(f):
    """Decorator to require a valid secret for a route."""

    @wraps(f)
    def decorated_function(*args, **kwargs):
        secret = kwargs.get('secret')
        provision_identity = kwargs.get('provision_identity')

        if not secret or not provision_identity:
            return jsonify({"error": "Missing secret or provision identity"}), 401

        expected_secret = generate_secret(provision_identity)
        if not hmac.compare_digest(secret, expected_secret):
            return jsonify({"error": "Invalid secret"}), 401

        return f(*args, **kwargs)

    return decorated_function
