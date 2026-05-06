#!/usr/bin/env bash
# Telemt Auto - MTProxy with TLS masking
# Clean version - no backticks, simple syntax

set -uo pipefail
export LANG=C.UTF-8

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err() { echo -e "${RED}[ERR]${NC} $1"; exit 1; }

WORKDIR="/root/mtproxy-telemt"
IMAGE="whn0thacked/telemt-docker:latest"

echo "Telemt Auto - MTProxy setup"
echo "==========================="

# 1. Get public IP
log "Detecting public IP..."
PUBLIC_IP=""
for url in "https://ifconfig.me" "https://ipinfo.io/ip" "https://icanhazip.com"; do
    PUBLIC_IP=$(curl -s --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]') && break
done
if [ -z "$PUBLIC_IP" ] || ! echo "$PUBLIC_IP" | grep -qE '^[0-9.]+$'; then
    err "Could not detect IP. Check internet connection."
fi
log "Your IP: $PUBLIC_IP"

# 2. Get domain
echo ""
read -rp "Enter domain for masking (e.g. example.com): " DOMAIN
DOMAIN=$(echo "$DOMAIN" | tr -d '\r' | xargs)
if [ -z "$DOMAIN" ]; then
    err "Domain cannot be empty."
fi
log "Masking as: $DOMAIN"

# 3. Generate secret
SECRET=$(openssl rand -hex 16)
warn "Secret: $SECRET (SAVE IT!)"

# 4. Domain to hex
DOMAIN_HEX=$(printf '%s' "$DOMAIN" | od -An -tx1 | tr -d ' \n')

# 5. Install Docker if needed
if ! command -v docker >/dev/null 2>&1; then
    log "Installing Docker..."
    apt update -qq >/dev/null 2>&1
    apt install -y -qq curl >/dev/null 2>&1
    curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
fi

# Install docker-compose if needed
if ! command -v docker-compose >/dev/null 2>&1; then
    if ! docker compose version >/dev/null 2>&1; then
        log "Installing docker-compose..."
        apt install -y -qq docker-compose >/dev/null 2>&1 || true
    fi
fi

# Determine compose command
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi
log "Using: $COMPOSE_CMD"

# Start Docker
systemctl enable --now docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true
sleep 2

# 6. Create configs
log "Creating configs..."
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# telemt.toml
cat > telemt.toml << TOML_EOF
show_link = ["user1"]

[general]
prefer_ipv6 = false
fast_mode = true
use_middle_proxy = true

[general.modes]
classic = false
secure = false
tls = true

[server]
port = 443
listen_addr_ipv4 = "0.0.0.0"
listen_addr_ipv6 = "::"

[censorship]
tls_domain = "$DOMAIN"
mask = true
mask_port = 443
fake_cert_len = 2048

[access.users]
user1 = "$SECRET"

[[upstreams]]
type = "direct"
enabled = true
weight = 10
TOML_EOF

# docker-compose.yml
cat > docker-compose.yml << YML_EOF
services:
  telemt:
    image: $IMAGE
    container_name: telemt
    restart: unless-stopped
    environment:
      RUST_LOG: "info"
    volumes:
      - ./telemt.toml:/etc/telemt.toml:ro
    ports:
      - "443:443/tcp"
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    read_only: true
    tmpfs:
      - /tmp:rw,nosuid,nodev,noexec,size=16m
YML_EOF

# 7. Pull image
log "Pulling image..."
docker pull "$IMAGE" >/dev/null 2>&1 || err "Failed to pull image"

# 8. Start container
log "Starting container..."
if ! $COMPOSE_CMD up -d 2>&1; then
    err "Failed to start container. Run: $COMPOSE_CMD logs"
fi
sleep 12

# 9. Build proxy link
FULL_SECRET="ee${SECRET}${DOMAIN_HEX}"
PROXY_LINK="tg://proxy?server=${PUBLIC_IP}&port=443&secret=${FULL_SECRET}"

# 10. Save to files
echo "$SECRET" > "$WORKDIR/secret.txt"
echo "$PROXY_LINK" > "$WORKDIR/proxy-link.txt"
chmod 600 "$WORKDIR/secret.txt" "$WORKDIR/proxy-link.txt"

# 11. Final output
echo ""
echo "========================================"
echo "  DONE! MTProxy is ready"
echo "========================================"
echo "  IP:     $PUBLIC_IP"
echo "  Domain: $DOMAIN"
echo ""
echo "  Telegram link:"
echo "  $PROXY_LINK"
echo ""
echo "  Files saved in: $WORKDIR"
echo "    - proxy-link.txt (full link)"
echo "    - secret.txt (secret only)"
echo ""
echo "  View link later: cat $WORKDIR/proxy-link.txt"
echo "========================================"
echo ""

# 12. Checks
log "Running checks..."

# Masking check
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --resolve "${DOMAIN}:443:${PUBLIC_IP}" "https://${DOMAIN}/" 2>/dev/null || echo "000")
if echo "$HTTP_CODE" | grep -qE '^(2|3)'; then
    log "Masking OK (HTTP $HTTP_CODE)"
else
    warn "Masking: HTTP $HTTP_CODE"
fi

# Port check
if ss -tulpn 2>/dev/null | grep -q ":443 "; then
    log "Port 443 is open"
else
    warn "Port 443 not found"
fi

# Container check
if $COMPOSE_CMD ps 2>/dev/null | grep -q "Up"; then
    log "Container is running"
else
    warn "Container status unknown"
fi

echo ""
log "All done! Connect in Telegram"
