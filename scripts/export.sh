#!/bin/bash
# Вывести сохранённый конфиг клиента + QR.
set -euo pipefail

WORK_DIR="${WORK_DIR:-/etc/wireguard}"

if [ -z "${1:-}" ]; then
    read -r -p "Введите email или username клиента: " ARG
    if [ -z "${ARG}" ]; then
        echo "[#] Пустой ввод. Выход" >&2
        exit 1
    fi
else
    ARG="${1}"
fi

# из email достаём local-part
if [[ "${ARG}" == *@* ]]; then
    userName=$(echo "${ARG}" | awk -F "@" '{print $1}')
else
    userName="${ARG}"
fi

cd "${WORK_DIR}" || exit 1

CONF="./clients/${userName}/${userName}.conf"

if [ ! -f "${CONF}" ]; then
    echo "[#] Конфиг ${CONF} не найден" >&2
    exit 1
fi

if command -v qrencode >/dev/null; then
    qrencode -t ansiutf8 < "${CONF}"
fi

echo "# Конфиг ${userName}.conf"
cat "${CONF}"
