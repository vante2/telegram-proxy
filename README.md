# 🚀 Telemt Auto — MTProxy для Telegram

Автоматическая установка MTProxy с TLS-маскировкой (Telemt) на твой VPS.
Одна команда — и прокси готов.

## ✨ Особенности
- 🔐 Маскировка под любой сайт — вводишь домен, скрипт делает остальное
- 🤖 Полная автоматизация — сам ставит Docker, генерирует ключи, запускает
- 🌍 Автоопределение IP — не нужно вводить адрес сервера вручную
- 🔄 Автозапуск — прокси переживёт перезагрузку сервера

## 🚀 Установка

Выполни эту команду на своём VPS (под root):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/vante2/telegram-proxy/main/setup.sh)

### 🔑 Как посмотреть ссылку, если забыл

Секрет и полная ссылка сохраняются на сервере:

```bash
# Показать полную ссылку для Telegram
cat /root/mtproxy-telemt/proxy-link.txt

# Показать только секрет
cat /root/mtproxy-telemt/secret.txt

# Или посмотреть логи контейнера
docker compose logs -n 20 | grep -i "proxy"
