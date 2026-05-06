#!/usr/bin/env bash
# 🚀 Telemt Auto — MTProxy с TLS-маскировкой
# Надёжная версия: без проблем с кодировкой и скрытыми ошибками

# === Настройки ===
# Отключаем строгий выход по ошибке (будем проверять вручную)
set -uo pipefail

# === Локаль для корректного вывода кириллицы ===
export LANG=C.UTF-8
export LC_ALL=C.UTF-8 2>/dev/null || true

# === Цвета (безопасный вывод через %b) ===
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { printf "${GREEN}[✓]${NC} %b\n" "$1"; }
warn() { printf "${YELLOW}[!]${NC} %b\n" "$1"; }
err() { printf "${RED}[✗]${NC} %b\n" "$1"; exit 1; }

WORKDIR="/root/mtproxy-telemt"

# === Заголовок ===
printf "🚀 Telemt Auto — MTProxy за 1 минуту\n"
printf "======================================\n\n"

# === 1. Авто-определение IP ===
log "Определяю публичный IP..."
PUBLIC_IP=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null || \
            curl -s --max-time 5 https://ipinfo.io/ip 2>/dev/null || echo "")
if [[ -z "$PUBLIC_IP" || ! "$PUBLIC_IP" =~ ^[0-9.]+$ ]]; then
    err "Не удалось определить IP. Проверь интернет."
fi
log "Твой IP: $PUBLIC_IP"

# === 2. Ввод домена ===
printf "\n"
read -p "🎭 Введите домен для маскировки (например, example.com): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
    err "Домен не может быть пустым."
fi
log "Маскируемся под: $DOMAIN"

# === 3. Генерация секрета ===
SECRET=$(openssl rand -hex 16)
warn "🔑 Секрет: $SECRET (сохрани!)"

# === 4. Домен в HEX (универсальный способ) ===
# Пробуем xxd, если нет — od, если нет — pure bash
if command -v xxd &>/dev/null; then
    DOMAIN_HEX=$(printf '%s' "$DOMAIN" | xxd -p | tr -d '\n')
elif command -v od &>/dev/null; then
    DOMAIN_HEX=$(printf '%s' "$DOMAIN" | od -An -tx1 | tr -d ' \n')
else
    # Pure bash fallback (медленнее, но работает везде)
    DOMAIN_HEX=""
    for ((i=0; i<${#DOMAIN}; i++)); do
        char="${DOMAIN:$i:1}"
        hex=$(printf '%x' "'$char")
        DOMAIN_HEX+="$hex"
    done
fi

# === 5. Docker ===
if ! command -v docker &>/dev/null; then
    log "Устанавливаю Docker..."
    apt update -qq >/dev/null 2>&1
    apt install -y -qq curl >/dev/null 2>&1
    curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
fi

# Запускаем Docker и игнорируем ошибки, если он уже запущен
systemctl enable --now docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true

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

# === 7. Запуск контейнера ===
log "Запускаю контейнер..."
if ! docker compose pull >/dev/null 2>&1; then
    warn "⚠️  Не удалось обновить образ, пробую запустить локальный..."
fi

if ! docker compose up -d >/dev/null 2>&1; then
    err "Не удалось запустить контейнер. Проверь: docker compose logs"
fi

# Ждём, пока контейнер поднимется
sleep 10

# === 8. Формирование ссылки ===
FULL_SECRET="ee${SECRET}${DOMAIN_HEX}"
PROXY_LINK="tg://proxy?server=${PUBLIC_IP}&port=443&secret=${FULL_SECRET}"

# === 9. Сохранение на сервере ===
echo "$SECRET" > "$WORKDIR/secret.txt"
echo "$PROXY_LINK" > "$WORKDIR/proxy-link.txt"
chmod 600 "$WORKDIR/secret.txt" "$WORKDIR/proxy-link.txt"

# === 10. Итоговый вывод ===
printf "\n"
printf "╔════════════════════════════════════════════╗\n"
printf "║  🎉 Готово!                               ║\n"
printf "╠════════════════════════════════════════════\n"
printf "║  🌐 IP:     %s\n" "$PUBLIC_IP"
printf "║  🎭 Домен:  %s\n" "$DOMAIN"
printf "║                                            ║\n"
printf "║  🔗 Ссылка для Telegram:                  ║\n"
printf "║  %s\n" "$PROXY_LINK"
printf "║                                            ║\n"
printf "║  📁 Файлы сохранены в: %s\n" "$WORKDIR"
printf "║     • secret.txt     — секрет\n"
printf "║     • proxy-link.txt — ссылка\n"
printf "║                                            ║\n"
printf "║  💡 Посмотреть ссылку позже:              ║\n"
printf "║     cat %s/proxy-link.txt\n" "$WORKDIR"
printf "║                                            ║\n"
printf "║  🔄 Автозапуск: включён                   ║\n"
printf "╚════════════════════════════════════════════╝\n"
printf "\n"

# === 11. Проверки ===
log "Проверяю работу..."

# Маскировка
HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    --resolve "${DOMAIN}:443:${PUBLIC_IP}" \
    "https://${DOMAIN}/" 2>/dev/null || echo "000")
if [[ "$HTTP" =~ ^2|3 ]]; then
    log "✅ Маскировка работает (HTTP $HTTP)"
else
    warn "⚠️  HTTP-код: $HTTP (DNS/TLS кэш может обновляться)"
fi

# Порт
if ss -tulpn 2>/dev/null | grep -q ":443 "; then
    log "✅ Порт 443 открыт"
else
    warn "⚠️  Порт 443 не найден. Открой: ufw allow 443/tcp"
fi

printf "\n✅ Всё готово! Подключай прокси в Telegram 🚀\n"
