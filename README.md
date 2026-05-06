#  Telemt Auto — MTProxy для Telegram

Автоматическая установка **MTProxy с TLS-маскировкой** на VPS.
Одна команда — приватный прокси готов. Ссылка сохраняется на сервере.

## ✨ Особенности
- 🔐 **Маскировка под любой сайт** — трафик выглядит как обычный HTTPS
- 🤖 **Без ручной настройки** — скрипт сам ставит Docker, генерирует ключи, запускает
- 🌍 **Автоопределение IP** — не нужно вводить адрес сервера
- 🔄 **Автозапуск** — переживёт перезагрузку VPS
- 💾 **Ссылка в файле** — не нужно запоминать секрет

---

## ⚡ Установка и управление (скопируй и вставь в терминал)

```bash
# 1️⃣ УСТАНОВКА (запустить один раз)
bash <(curl -fsSL https://raw.githubusercontent.com/vante2/telegram-proxy/main/setup.sh)

# 2️⃣ ПОЛУЧИТЬ ССЫЛКУ ДЛЯ TELEGRAM
cat /root/mtproxy-telemt/proxy-link.txt

# 3️⃣ ОСНОВНОЕ УПРАВЛЕНИЕ
cd /root/mtproxy-telemt
docker-compose logs -f              # Логи в реальном времени
docker-compose restart              # Перезапуск (после смены конфига)
docker-compose down                 # Остановка
docker-compose up -d                # Запуск после остановки
docker-compose pull && docker-compose up -d  # Обновление до новой версии

# 4️ СМЕНА ДОМЕНА МАСКИРОВКИ
# Останови: docker-compose down
# Открой: nano telemt.toml → замени tls_domain = "новый-домен"
# Пересчитай HEX: echo -n "новый-домен" | od -An -tx1 | tr -d ' \n'
# Собери ссылку: tg://proxy?server=ТВОЙ_IP&port=443&secret=ee[СЕКРЕТ][НОВЫЙ_ХЕКС]
# Запусти: docker-compose up -d

# 5️ СМЕНА СЕКРЕТА
# Сгенерируй: openssl rand -hex 16
# Открой: nano telemt.toml → замени user1 = "новый_секрет"
# Перезапусти: docker-compose restart
# ⚠️ Старая ссылка перестанет работать!

# 6️⃣ ДИАГНОСТИКА
docker-compose ps                   # Статус контейнера (должно быть "Up")
ss -tulpn | grep :443               # Проверка порта 443
curl -s -o /dev/null -w "%{http_code}" --resolve твой-домен:443:твой-ip https://твой-домен/  # Проверка маскировки

# 7️ ПОЛНОЕ УДАЛЕНИЕ
docker-compose down && rm -rf /root/mtproxy-telemt
