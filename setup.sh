```bash
#!/usr/bin/env bash
# 🚀 Telemt Auto — MTProxy с TLS-маскировкой
# Финальная версия: авто-установка, сохранение ссылки, совместимость

set -uo pipefail
export LANG=C.UTF-8
export LC_ALL=C.UTF-8 2>/dev/null || true

# Цвета
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

WORKDIR="/root/mtproxy-telemt"
IMAGE="whn0thacked/telemt-docker:latest"

echo "🚀 Telemt Auto — MTProxy за 1 минуту"
echo "======================================"
echo ""

# === 1. Авто-определение IP ===
log "Определяю публичный IP..."
PUBLIC_IP=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null || \
            curl -s --max-time 5 https://ipinfo.io/ip 2>/dev/null || echo "")
[[ -z "$PUBLIC_IP" || ! "$PUBLIC_IP" =~ ^[0-9.]+$ ]] && err "Не удалось определить IP."
log "Твой IP: $PUBLIC_IP"

# === 2. Ввод домена (чистый ввод) ===
echo ""
read -rp "🎭 Введите домен для маскировки: " DOMAIN
DOMAIN=$(echo "$DOMAIN" | tr -d '\r' | xargs)
[[ -z "$DOMAIN" ]] && err "Домен не может быть пустым."
log "Маскируемся под: $DOMAIN"

# === 3. Генерация секрета ===
SECRET=$(openssl rand -hex 16)
warn "🔑 Секрет: $SECRET (сохрани!)"

# === 4. HEX домена ===
DOMAIN_HEX=$(echo -n "$DOMAIN" | od -An -tx1 | tr -d ' \n')

# === 5. Docker + Compose ===
if ! command -v docker &>/dev/null; then
    log "Устанавливаю Docker..."
    apt update -qq >/dev/null 2>&1
    apt install -y -qq curl >/dev/null 2>&1
    curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
fi

# Устанавливаем docker-compose, если нет ни одной версии
if ! command -v docker-compose &>/dev/null; then
    if ! docker compose version &>/dev/null 2>&1; then
        log "Устанавливаю docker-compose..."
        apt install -y -qq docker-compose >/dev/null 2>&1 || \
        curl -fsSL "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && \
        chmod +x /usr/local/bin/docker-compose
    fi
fi

# Определяем команду
if docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi
log "Использую: $COMPOSE_CMD"

# Запускаем Docker
systemctl enable --now docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true
sleep 2

# === 6. Конфиги ===
log "Создаю конфиги..."
mkdir -p "$WORKDIR"
cd "$WORKDIR"

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

cat > docker-compose.yml << EOF
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
EOF

# === 7. Образ ===
log "Скачиваю образ..."
docker pull "$IMAGE" >/dev/null 2>&1 || err "❌ Не удалось скачать образ"

# === 8. Запуск ===
log "Запускаю контейнер..."
if ! $COMPOSE_CMD up -d 2>&1; then
    echo ""
    err "❌ Не удалось запустить контейнер!"
    echo "Проверь: $COMPOSE_CMD logs"
    exit 1
fi
sleep 12

# === 9. Формирование ссылки ===
FULL_SECRET="ee${SECRET}${DOMAIN_HEX}"
PROXY_LINK="tg://proxy?server=${PUBLIC_IP}&port=443&secret=${FULL_SECRET}"

# === 10. Сохранение на сервере ===
echo "$SECRET" > "$WORKDIR/secret.txt"
echo "$PROXY_LINK" > "$WORKDIR/proxy-link.txt"
chmod 600 "$WORKDIR/secret.txt" "$WORKDIR/proxy-link.txt"

# === 11. Итоговый вывод ===
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║  🎉 Готово!                               ║"
echo "╠════════════════════════════════════════════"
echo "║  🌐 IP:     $PUBLIC_IP"
echo "║  🎭 Домен:  $DOMAIN"
echo "║"
echo "║  🔗 Ссылка для Telegram:"
echo "║  $PROXY_LINK"
echo "║"
echo "║  📁 Файлы сохранены в: $WORKDIR"
echo "║     • proxy-link.txt — полная ссылка"
echo "║     • secret.txt     — секрет"
echo "║"
echo "║  💡 Посмотреть ссылку позже:"
echo "║     cat $WORKDIR/proxy-link.txt"
echo "║"
echo "║  🔄 Автозапуск: включён"
echo "╚════════════════════════════════════════════╝"
echo ""

# === 12. Проверки ===
log "Проверяю..."

HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    --resolve "${DOMAIN}:443:${PUBLIC_IP}" \
    "https://${DOMAIN}/" 2>/dev/null || echo "000")
[[ "$HTTP" =~ ^2|3 ]] && log "✅ Маскировка (HTTP $HTTP)" || warn "⚠️  HTTP $HTTP"

ss -tulpn 2>/dev/null | grep -q ":443 " && log "✅ Порт 443" || warn "⚠️  Порт 443"

$COMPOSE_CMD ps 2>/dev/null | grep -q "Up" && log "✅ Контейнер работает" || warn "⚠️  Контейнер"

echo ""
log "Всё готово! Подключай прокси в Telegram 🚀"
