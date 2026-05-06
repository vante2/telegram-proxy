#  Telemt Auto — MTProxy для Telegram

Автоматическая установка **MTProxy с TLS-маскировкой** на VPS (работоспособность проверялась для UBUNTU 24.04).

## ✨ Особенности
- 🔐 **Маскировка под любой сайт** — трафик выглядит как обычный HTTPS
- 🤖 **Без ручной настройки** — скрипт сам ставит Docker, генерирует ключи, запускает
- 🔄 **Автозапуск** — переживёт перезагрузку VPS

---

## ⚡ Установка и управление:

```bash
# 1️⃣ УСТАНОВКА (Копируем и вставляем в терминал вашего сервера)
bash <(curl -fsSL https://raw.githubusercontent.com/vante2/telegram-proxy/main/setup.sh)
```
## ОСНОВНОЕ УПРАВЛЕНИЕ
```bash
cd /root/mtproxy-telemt
docker-compose logs -f              # Логи в реальном времени
docker-compose restart              # Перезапуск (после смены конфига)
docker-compose down                 # Остановка
docker-compose up -d                # Запуск после остановки
docker-compose pull && docker-compose up -d  # Обновление до новой версии
```

## ПОЛНОЕ УДАЛЕНИЕ
```bash
(cd /root/mtproxy-telemt && docker-compose down 2>/dev/null || true) && rm -rf /root/mtproxy-telemt && echo "✅ Очистка завершена. Готов к установке."
```
