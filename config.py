import os


class Config:
    # Flask configuration
    SECRET_KEY = os.getenv('SECRET_KEY', 'your-secret-key-here')
    JWT_SECRET_KEY = os.getenv('JWT_SECRET_KEY', 'your-jwt-secret-here')

    # OpenVPN configuration
    VPN_HOST = os.getenv('VPN_HOST', '34.45.7.160')
    VPN_PORT = int(os.getenv('VPN_PORT', 1194))
    VPN_PROTO = os.getenv('VPN_PROTO', 'udp')  # UDP is recommended for better performance
    VPN_CLIENT_DIR = os.getenv('VPN_CLIENT_DIR', '/etc/openvpn/client')

    # Hotspot configuration
    HOTSPOT_TEMPLATE_DIR = os.getenv('HOTSPOT_TEMPLATE_DIR', '/var/www/templates')

    # Redis configuration
    REDIS_HOST = os.getenv('REDIS_HOST', 'redis')
    REDIS_PORT = int(os.getenv('REDIS_PORT', 6379))
    REDIS_PASSWORD = os.getenv('REDIS_PASSWORD', None)
    REDIS_DB = int(os.getenv('REDIS_DB', 0))

    # Celery configuration
    CELERY_BROKER_URL = os.getenv('CELERY_BROKER_URL', f'redis://{REDIS_HOST}:{REDIS_PORT}/{REDIS_DB}')
    CELERY_RESULT_BACKEND = os.getenv('CELERY_RESULT_BACKEND', f'redis://{REDIS_HOST}:{REDIS_PORT}/{REDIS_DB}')