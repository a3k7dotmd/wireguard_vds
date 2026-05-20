#!/bin/bash
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
WGCTL="${HERE}/../wgctl"

while true; do
    cat <<'EOF'

=== wgctl ===
  1) Установить (полная установка + первый клиент)
  2) Добавить клиента
  3) Удалить клиента
  4) Сбросить настройки и клиентов
  5) Полностью снести WireGuard
  6) Список клиентов
  7) Статус WireGuard
  8) Пересоздать ключи клиента
  9) Экспорт конфига клиента
  q) Выход
EOF
    read -r -p "Выбор: " choice || exit 0
    case "${choice}" in
        1) "${WGCTL}" install ;;
        2) read -r -p "Email: " email || continue; "${WGCTL}" add "${email}" ;;
        3) read -r -p "Email или username: " arg || continue; "${WGCTL}" remove "${arg}" ;;
        4) "${WGCTL}" reset ;;
        5) "${WGCTL}" uninstall ;;
        6) "${WGCTL}" list ;;
        7) "${WGCTL}" status ;;
        8) read -r -p "Email или username: " arg || continue; "${WGCTL}" regenerate "${arg}" ;;
        9) read -r -p "Email или username: " arg || continue; "${WGCTL}" export "${arg}" ;;
        q|Q|"") exit 0 ;;
        *) echo "Неизвестный выбор: ${choice}" ;;
    esac
done
