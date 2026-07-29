#!/usr/bin/env bash
set -euo pipefail

CERT_DIR="/etc/ssl/certs"
KEY_DIR="/etc/ssl/private"
CERT_PEM="${CERT_DIR}/ha_proxy_ssl.pem"
CERT_CRT="${CERT_DIR}/ha_proxy_ssl.crt"
CERT_KEY="${KEY_DIR}/ha_proxy_ssl.key"
HAPROXY_CFG="/etc/haproxy/haproxy.cfg"

sudo mkdir -p /etc/haproxy /etc/ssl/certs /etc/ssl/private

if ! command -v haproxy >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y haproxy
fi

sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$CERT_KEY" \
  -out "$CERT_CRT" \
  -subj "/CN=www.holberton.online" >/dev/null 2>&1

sudo bash -c "cat '$CERT_CRT' '$CERT_KEY' > '$CERT_PEM'"
sudo chmod 600 "$CERT_PEM"
sudo chown haproxy:haproxy "$CERT_PEM" 2>/dev/null || true

sudo tee "$HAPROXY_CFG" > /dev/null <<'EOF'
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    ca-base /etc/ssl/certs
    crt-base /etc/ssl/private
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 5000
    timeout client 50000
    timeout server 50000

frontend balancer_http_in
    bind *:80
    redirect scheme https code 301 if !{ ssl_fc }

frontend balancer_https_in
    bind *:443 ssl crt /etc/ssl/certs/ha_proxy_ssl.pem
    option forwardfor
    default_backend balancer_http_out

backend balancer_http_out
    balance roundrobin
    http-response set-header X-Served-By %[srv_name]
    server web-01 18.207.206.213:80 check
    server web-02 54.211.113.26:80 check
EOF

if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    sudo systemctl restart haproxy >/dev/null 2>&1 || true
    sudo systemctl enable haproxy >/dev/null 2>&1 || true
fi

echo "HAProxy SSL deployment script completed."
echo "Verify with: curl -k -I https://<lb-ip>"
