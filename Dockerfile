# Use Python 3.11 as base image
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies (no OpenVPN or EasyRSA install here)
RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python deps
COPY requirements.txt .
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

# Expose app port
EXPOSE 8000

# Run the app with Gunicorn
CMD ["gunicorn", "--config", "gunicorn_config.py", "app:app"]
