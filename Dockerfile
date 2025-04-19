# Use Python 3.11 as base image
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    openvpn \
    easy-rsa \
    && rm -rf /var/lib/apt/lists/*

# Set up EasyRSA
RUN mkdir -p /etc/openvpn/easy-rsa && \
    cp -r /usr/share/easy-rsa/* /etc/openvpn/easy-rsa && \
    cd /etc/openvpn/easy-rsa && \
    echo 'set_var EASYRSA_REQ_COUNTRY...' > vars && \
    ./easyrsa init-pki && \
    echo 'set_var EASYRSA_REQ_COUNTRY "US"\nset_var EASYRSA_REQ_PROVINCE "California"\nset_var EASYRSA_REQ_CITY "San Francisco"\nset_var EASYRSA_REQ_ORG "My Organization"\nset_var EASYRSA_REQ_EMAIL "admin@example.com"\nset_var EASYRSA_REQ_OU "My Organizational Unit"\nset_var EASYRSA_BATCH "1"' > pki/vars && \
    rm -f vars && \
    ./easyrsa build-ca nopass && \
    ./easyrsa gen-dh && \
    ./easyrsa build-server-full server nopass && \
    cp pki/ca.crt /etc/openvpn/ && \
    cp pki/issued/server.crt /etc/openvpn/ && \
    cp pki/private/server.key /etc/openvpn/ && \
    cp pki/dh.pem /etc/openvpn/ && \
    ln -s /etc/openvpn/easy-rsa/easyrsa /usr/local/bin/

# Create non-root user and set permissions
RUN useradd -m -u 1000 appuser && \
    mkdir -p /app/static /app/templates /app/prometheus \
    /etc/openvpn/client /var/www/templates && \
    chown -R appuser:appuser /app /etc/openvpn/client /var/www/templates && \
    chown -R appuser:appuser /etc/openvpn && \
    chmod -R 777 /etc/openvpn/easy-rsa/pki && \
    chmod -R 777 /etc/openvpn/easy-rsa && \
    chmod -R 755 /etc/openvpn/client

# Copy requirements first to leverage Docker cache
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Set environment variables
ENV FLASK_APP=app.py
ENV FLASK_ENV=production
ENV FLASK_CONFIG=production
ENV PYTHONUNBUFFERED=1
ENV PATH="/etc/openvpn/easy-rsa:${PATH}"
ENV EASYRSA=/etc/openvpn/easy-rsa
ENV EASYRSA_PKI=/etc/openvpn/easy-rsa/pki

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 8000

# Command to run the application
CMD ["gunicorn", "--config", "gunicorn_config.py", "app:app"] 