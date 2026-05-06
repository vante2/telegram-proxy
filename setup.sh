#!/usr/bin/env bash
# 🚀 Telemt Auto — MTProxy с TLS-маскировкой
# Просто введи домен — всё остальное сделает скрипт

set -euo pipefail

# Цвета
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

WORKDIR="/root/mtproxy-telemt"

echo "🚀 Telemt Auto — MTProxy за 1 минуту"
echo "======================================"

# 1. Авто-определение IP
log "Определяю публичный IP..."
PUBLIC_IP=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null || \
            curl -s --max-time 5 https://ipinfo.io/ip 2>/dev/null || echo "")
[[ -z "$PUBLIC_IP" || ! "$PUBLIC_IP" =~ ^[0-9.]+$ ]] && err "Не удалось определить IP"
log "Твой IP: $PUBLIC_IP"

# 2. Ввод домена
echo ""
read -p "🎭 Введите домен для маскировки (например, example.com): " DOMAIN
[[ -z "$DOMAIN" ]] && err "Домен не может быть пустым"
log "Маскируемся под: $DOMAIN"

# 3. Генерация секрета
SECRET=$(openssl rand -hex 16)
warn "🔑 Секрет: $SECRET (СОХРАНИ!)"

# 4. Домен в HEX (для ссылки)
DOMAIN_HEX=$(printf '%s' "$DOMAIN" | od -An -tx1 | tr -d ' \n')

# 5. Docker
if ! command -v docker &>/dev/null; then
    log "Ставлю Docker..."
    apt update -qq && apt install -y -qq curl >/dev/null
    curl -fsSL https://get.docker.com | sh >/dev/null
fi
systemctl enable --now docker >/dev/null 2>&1 || true

# 6. Конфиги
mkdir -p "$WORKDIR" && cd "$WORKDIR"

cat > telemt.toml << EOF
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
EOF

cat > docker-compose.yml << 'EOF'
services:
  telemt:
    image: whn0thacked/telemt-docker:latest
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
EOF

# 7. Запуск
log "Запускаю..."
docker compose pull -q
docker compose up -d
sleep 10

# 8. Ссылка
FULL_SECRET="ee${SECRET}${DOMAIN_HEX}"
PROXY_LINK="tg://proxy?server=${PUBLIC_IP}&port=443&secret=${FULL_SECRET}"

# 9. Итог
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║  🎉 Готово!                               ║"
echo "╠════════════════════════════════════════════"
echo "║  IP:     $PUBLIC_IP"
echo "║  Домен:  $DOMAIN"
echo "║  Ссылка: $PROXY_LINK"
echo "╠════════════════════════════════════════════"
echo "║  Конфиги: $WORKDIR"
echo "║  Автозапуск: включён"
echo "╚════════════════════════════════════════════╝"

# 10. Проверки
HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    --resolve "${DOMAIN}:443:${PUBLIC_IP}" \
    "https://${DOMAIN}/" 2>/dev/null || echo "000")
[[ "$HTTP" =~ ^2|3 ]] && log "✅ Маскировка OK" || warn "⚠️ HTTP $HTTP"
ss -tulpn | grep -q ":443 " && log "✅ Порт 443 открыт" || warn "⚠️ Порт 443 закрыт"
