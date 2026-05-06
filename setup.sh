#!/usr/bin/env bash
# 🚀 Telemt Auto — MTProxy с TLS-маскировкой
# Простая версия: минимум магии, максимум надёжности

# Не выходим при первой ошибке — будем проверять вручную
set -uo pipefail

# Локаль для кириллицы
export LANG=C.UTF-8
export LC_ALL=C.UTF-8 2>/dev/null || true

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Простые функции вывода (без %b, чтобы не ломать ввод пользователя)
log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

WORKDIR="/root/mtproxy-telemt"

echo "🚀 Telemt Auto — MTProxy за 1 минуту"
echo "======================================"
echo ""

# === 1. IP ===
log "Определяю публичный IP..."
PUBLIC_IP=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null || \
            curl -s --max-time 5 https://ipinfo.io/ip 2>/dev/null || echo "")
if [[ -z "$PUBLIC_IP" || ! "$PUBLIC_IP" =~ ^[0-9.]+$ ]]; then
    err "Не удалось определить IP. Проверь интернет."
fi
log "Твой IP: $PUBLIC_IP"

# === 2. Домен (простой read без лишних символов) ===
echo ""
read -rp "🎭 Введите домен для маскировки: " DOMAIN
# Убираем возможные пробелы и спецсимволы по краям
DOMAIN=$(echo "$DOMAIN" | tr -d '\r' | xargs)
if [[ -z "$DOMAIN" ]]; then
    err "Домен не может быть пустым."
fi
log "Маскируемся под: $DOMAIN"

# === 3. Секрет ===
SECRET=$(openssl rand -hex 16)
warn "🔑 Секрет: $SECRET (сохрани!)"

# === 4. HEX домена (простой способ через od) ===
DOMAIN_HEX=$(echo -n "$DOMAIN" | od -An -tx1 | tr -d ' \n')

# === 5. Docker ===
if ! command -v docker &>/dev/null; then
    log "Устанавливаю Docker..."
    apt update -qq >/dev/null 2>&1
    apt install -y -qq curl >/dev/null 2>&1
    curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
fi

# Проверяем, запущен ли Docker
if ! systemctl is-active --quiet docker 2>/dev/null; then
    log "Запускаю Docker..."
    systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
    sleep 2
fi

# === 6. Конфиги ===
log "Создаю конфиги..."
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# telemt.toml
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

# docker-compose.yml
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

# === 7. Запуск ===
log "Скачиваю образ..."
if ! docker compose pull 2>&1; then
    warn "⚠️  Не удалось скачать образ. Пробую запустить без обновления..."
fi

log "Запускаю контейнер..."
if ! docker compose up -d 2>&1; then
    echo ""
    err "❌ Не удалось запустить контейнер!"
    echo ""
    echo "Возможные причины:"
    echo "  • Порт 443 уже занят: ss -tulpn | grep :443"
    echo "  • Docker не работает: systemctl status docker"
    echo "  • Нет места: df -h"
    echo ""
    echo "Логи ошибки:"
    docker compose logs --tail=10 2>/dev/null || echo "(нет логов)"
    exit 1
fi

# Ждём запуска
sleep 12

# === 8. Ссылка ===
FULL_SECRET="ee${SECRET}${DOMAIN_HEX}"
PROXY_LINK="tg://proxy?server=${PUBLIC_IP}&port=443&secret=${FULL_SECRET}"

# === 9. Сохранение ===
echo "$SECRET" > "$WORKDIR/secret.txt"
echo "$PROXY_LINK" > "$WORKDIR/proxy-link.txt"
chmod 600 "$WORKDIR/secret.txt" "$WORKDIR/proxy-link.txt"

# === 10. Итог ===
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║  🎉 Готово!                               ║"
echo "╠════════════════════════════════════════════"
echo "║  IP:     $PUBLIC_IP"
echo "║  Домен:  $DOMAIN"
echo "║"
echo "║  🔗 Ссылка для Telegram:"
echo "║  $PROXY_LINK"
echo "║"
echo "║  📁 Файлы в: $WORKDIR"
echo "║     • secret.txt     — секрет"
echo "║     • proxy-link.txt — ссылка"
echo "║"
echo "║  💡 Посмотреть ссылку позже:"
echo "║     cat $WORKDIR/proxy-link.txt"
echo "║"
echo "║  🔄 Автозапуск: включён"
echo "╚════════════════════════════════════════════╝"
echo ""

# === 11. Проверки ===
log "Проверяю..."

# Маскировка
HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    --resolve "${DOMAIN}:443:${PUBLIC_IP}" \
    "https://${DOMAIN}/" 2>/dev/null || echo "000")
if [[ "$HTTP" =~ ^2|3 ]]; then
    log "✅ Маскировка работает (HTTP $HTTP)"
else
    warn "⚠️  HTTP: $HTTP (DNS/TLS кэш может обновляться)"
fi

# Порт
if ss -tulpn 2>/dev/null | grep -q ":443 "; then
    log "✅ Порт 443 открыт"
else
    warn "⚠️  Порт 443 не найден. Открой: ufw allow 443/tcp"
fi

# Статус контейнера
if docker compose ps 2>/dev/null | grep -q "Up"; then
    log "✅ Контейнер работает"
else
    warn "⚠️  Контейнер не в статусе Up. Проверь: docker compose logs"
fi

echo ""
log "Всё готово! Подключай прокси в Telegram 🚀"
