#!/usr/bin/env bash
# Telemt Auto — Автоматическая установка MTProxy с TLS-маскировкой
# Версия: исправленная проверка маскировки + справочник кодов

set -uo pipefail
export LANG=C.UTF-8

# === Цвета и функции вывода ===
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# === Базовые переменные ===
WORKDIR="/root/mtproxy-telemt"
IMAGE="whn0thacked/telemt-docker:latest"

# === Заголовок ===
echo ""
echo -e " ${GREEN}Telemt Auto${NC} — Установка MTProxy"
echo "=================================="

# === 1. Определение IP (локально) ===
log "Определяю IP-адрес сервера..."
PUBLIC_IP=$(hostname -I 2>/dev/null | awk '{print $1}')

if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(ip -4 addr show scope global 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
fi

if [ -z "$PUBLIC_IP" ] || ! echo "$PUBLIC_IP" | grep -qE '^[0-9.]+$'; then
    err "Не удалось определить IP. Проверь сетевые настройки."
fi
log "Твой IP: $PUBLIC_IP"

# === 2. Ввод домена ===
echo ""
read -rp "🎭 Введите домен для маскировки (например, example.com): " DOMAIN
DOMAIN=$(echo "$DOMAIN" | tr -d '\r' | xargs)
if [ -z "$DOMAIN" ]; then
    err "Домен не может быть пустым."
fi
log "Маскируемся под: $DOMAIN"

# === 3. Генерация секрета ===
SECRET=$(openssl rand -hex 16)
warn "🔑 Секрет: $SECRET (обязательно сохрани!)"

# === 4. Конвертация домена в HEX ===
DOMAIN_HEX=$(printf '%s' "$DOMAIN" | od -An -tx1 | tr -d ' \n')

# === 5. Проверка и установка Docker ===
if command -v docker >/dev/null 2>&1; then
    log "Docker уже установлен ($(docker --version | cut -d' ' -f3))"
else
    log "Устанавливаю Docker..."
    if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
        warn "⚠️  dpkg заблокирован. Жду 30 секунд..."
        sleep 30
    fi
    apt update -qq >/dev/null 2>&1
    apt install -y -qq curl >/dev/null 2>&1
    curl -fsSL https://get.docker.com | bash >/dev/null 2>&1
    log "Docker установлен"
fi

# === Проверка и установка docker-compose ===
COMPOSE_INSTALLED=false

if command -v docker-compose >/dev/null 2>&1; then
    log "docker-compose уже установлен ($(docker-compose --version | cut -d' ' -f3))"
    COMPOSE_INSTALLED=true
elif docker compose version >/dev/null 2>&1; then
    log "Docker Compose v2 уже установлен"
    COMPOSE_INSTALLED=true
fi

if [ "$COMPOSE_INSTALLED" = false ]; then
    log "Устанавливаю docker-compose..."
    if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
        warn "⚠️  dpkg заблокирован. Жду 30 секунд..."
        sleep 30
    fi
    timeout 60 apt install -y -qq docker-compose >/dev/null 2>&1 && COMPOSE_INSTALLED=true
    if [ "$COMPOSE_INSTALLED" = false ]; then
        warn "⚠️  Не удалось через apt. Скачиваю бинарник..."
        curl -fsSL "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/bin/docker-compose 2>/dev/null && \
        chmod +x /usr/local/bin/docker-compose && \
        COMPOSE_INSTALLED=true
    fi
    if [ "$COMPOSE_INSTALLED" = true ]; then
        log "docker-compose установлен"
    else
        err "❌ Не удалось установить docker-compose. Установи вручную: apt install docker-compose"
    fi
fi

# Определяем команду
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi
log "Использую: $COMPOSE_CMD"

# Запускаем Docker
systemctl enable --now docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true
sleep 2

# === 6. Создание конфигов ===
log "Создаю конфигурационные файлы..."
mkdir -p "$WORKDIR"
cd "$WORKDIR"

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

cat > docker-compose.yml << 'YML_EOF'
version: '3.8'
services:
  telemt:
    image: whn0thacked/telemt-docker:latest
    container_name: telemt
    restart: unless-stopped
    environment:
      - RUST_LOG=info
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

# === 7. Скачивание образа ===
log "Скачиваю образ прокси..."
docker pull "$IMAGE" >/dev/null 2>&1 || err "❌ Не удалось скачать образ."

# === 8. Запуск контейнера ===
log "Запускаю контейнер..."
if ! $COMPOSE_CMD up -d 2>&1; then
    err "❌ Ошибка запуска. Подробности: $COMPOSE_CMD logs"
fi
sleep 12

# === 9. Формирование ссылки ===
FULL_SECRET="ee${SECRET}${DOMAIN_HEX}"
PROXY_LINK="tg://proxy?server=${PUBLIC_IP}&port=443&secret=${FULL_SECRET}"

echo "$SECRET" > "$WORKDIR/secret.txt"
echo "$PROXY_LINK" > "$WORKDIR/proxy-link.txt"
chmod 600 "$WORKDIR/secret.txt" "$WORKDIR/proxy-link.txt"

# === 10. Итоговый вывод ===
echo ""
echo "════════════════════════════════════════════╗"
echo "║   Готово! MTProxy успешно настроен      "
echo "╠════════════════════════════════════════════╣"
echo "║  🌐 IP:     $PUBLIC_IP"
echo "║  🎭 Домен:  $DOMAIN"
echo "║                                            ║"
echo "║  🔗 Ссылка для Telegram:                  ║"
echo "║  $PROXY_LINK"
echo "║                                            ║"
echo "║  📁 Файлы сохранены в: $WORKDIR"
echo "║     • proxy-link.txt — полная ссылка      ║"
echo "║     • secret.txt     — только секрет      ║"
echo "║                                            "
echo "║  💡 Посмотреть ссылку позже:              ║"
echo "║     cat $WORKDIR/proxy-link.txt           ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# === 11. Проверки (исправленная логика) ===
log "Запускаю проверки..."

# Получаем HTTP-код корректно
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --resolve "${DOMAIN}:443:${PUBLIC_IP}" "https://${DOMAIN}/" 2>/dev/null)
[ -z "$HTTP_CODE" ] && HTTP_CODE="000"
HTTP_CODE=$(echo "$HTTP_CODE" | tr -d '\n\r' | grep -oE '^[0-9]{3}' || echo "000")

# Вывод с пояснением
case "$HTTP_CODE" in
    200) log "✅ Маскировка: сайт отвечает (200 OK)" ;;
    301|302|307) log "✅ Маскировка: редирект (HTTP $HTTP_CODE)" ;;
    400|403) warn "🟡 Маскировка: сайт блокирует прямые запросы ($HTTP_CODE), но прокси работает" ;;
    404|500|502|503) warn "🟡 Маскировка: ошибка сервера ($HTTP_CODE), проверь позже" ;;
    000) warn "🔴 Маскировка: нет соединения (000) — проверь порт 443 и фаервол" ;;
    *) warn "⚠️  Маскировка: необычный ответ ($HTTP_CODE)" ;;
esac

# Проверка порта
if ss -tulpn 2>/dev/null | grep -q ":443 "; then
    log "✅ Порт 443 открыт"
else
    warn "⚠️  Порт 443 не найден. Открой: ufw allow 443/tcp"
fi

# Проверка контейнера
if $COMPOSE_CMD ps 2>/dev/null | grep -q "Up"; then
    log "✅ Контейнер работает"
else
    warn "⚠️  Статус контейнера неизвестен"
fi

# === Справочник кодов (выводим пользователю) ===
echo ""
echo "📋 Справочник кодов маскировки:"
echo "   200    = ✅ Идеально: сайт отвечает нормально"
echo "   301/302/307 = ✅ Отлично: редирект, маскировка работает"
echo "   400/403 = 🟡 Нормально: сайт блокирует прямые запросы, но прокси работает"
echo "   404/5xx = 🟡 Временно: ошибка сервера, попробуй позже"
echo "   000    = 🔴 Проблема: нет соединения (проверь порт/фаервол)"
echo ""
echo "💡 Важно: Даже при 400/403/000 Telegram может подключаться!"
echo "   Главное — контейнер в статусе 'Up' и порт 443 слушается."

echo ""
log "Всё готово! Подключай прокси в Telegram 🚀"
