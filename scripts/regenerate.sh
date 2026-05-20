#!/bin/bash
# Пересоздать ключи существующего клиента, сохранив его IP.
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

cd "${WORK_DIR}" || exit 1

# найти [Peer]-блок по email или username (по префиксу до @)
if [[ "${ARG}" == *@* ]]; then
    PEER_LINE=$(grep -F "[Peer] # ${ARG}" wg0.conf || true)
else
    PEER_LINE=$(grep -E "^\[Peer\] # ${ARG}@" wg0.conf || true)
fi

MATCHES=$(echo -n "${PEER_LINE}" | grep -c . || true)
if [[ "${MATCHES}" -eq 0 ]]; then
    echo "[#] Клиент '${ARG}' не найден в wg0.conf. Выход" >&2
    exit 1
fi
if [[ "${MATCHES}" -gt 1 ]]; then
    echo "[#] Найдено несколько клиентов по '${ARG}'. Уточните:" >&2
    echo "${PEER_LINE}" >&2
    exit 1
fi

EMAIL=$(echo "${PEER_LINE}" | awk -F '# ' '{print $2}')
userName=$(echo "${EMAIL}" | awk -F "@" '{print $1}')

# извлечь существующий CLIENT_IP из его [Peer]-блока
CLIENT_IP=$(awk -v target="[Peer] # ${EMAIL}" '
    $0 == target { found = 1; next }
    found && /^AllowedIPs = / { print $3; exit }
    found && /^\[/ { exit }
' wg0.conf)

if [ -z "${CLIENT_IP}" ]; then
    echo "[#] Не удалось извлечь AllowedIPs для ${EMAIL}. Выход" >&2
    exit 1
fi

echo "Пересоздаём ключи для ${userName} (${EMAIL}), сохраняем IP ${CLIENT_IP}"

# shellcheck source=/dev/null
. "${WORK_DIR}/state.env"

# новые ключи
CLIENT_PRESHARED_KEY=$( wg genpsk )
CLIENT_PRIVKEY=$( wg genkey )
CLIENT_PUBLIC_KEY=$( echo "${CLIENT_PRIVKEY}" | wg pubkey )

read -r SERVER_PUBLIC_KEY < ./server.pub

# удалить старый [Peer]-блок
awk -v target="[Peer] # ${EMAIL}" '
    $0 == target { skip = 1; next }
    skip && /^$/ { skip = 0; next }
    skip && /^\[/ { skip = 0; print; next }
    skip { next }
    { print }
' wg0.conf > wg0.conf.tmp && mv wg0.conf.tmp wg0.conf

# добавить новый [Peer]-блок с теми же AllowedIPs
cat >> ./wg0.conf <<_EOF_

[Peer] # ${EMAIL}
PublicKey = ${CLIENT_PUBLIC_KEY}
PresharedKey = ${CLIENT_PRESHARED_KEY}
AllowedIPs = ${CLIENT_IP}
_EOF_

# перезаписать клиентские файлы
mkdir -p "./clients/${userName}"
PRESHARED_KEY=".preshared"
PRIV_KEY=".key"
PUB_KEY=".pub"
ALLOWED_IP="0.0.0.0/0"

echo "${CLIENT_PRESHARED_KEY}" > "./clients/${userName}/${userName}${PRESHARED_KEY}"
echo "${CLIENT_PRIVKEY}" > "./clients/${userName}/${userName}${PRIV_KEY}"
echo "${CLIENT_PUBLIC_KEY}" > "./clients/${userName}/${userName}${PUB_KEY}"

cat > "./clients/${userName}/${userName}.conf" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIVKEY}
Address = ${CLIENT_IP}
DNS = ${DNS}

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
PresharedKey = ${CLIENT_PRESHARED_KEY}
AllowedIPs = ${ALLOWED_IP}
Endpoint = ${ENDPOINT}
PersistentKeepalive=25
EOF

# применить wg0.conf без обрыва активных туннелей
if command -v systemctl >/dev/null && systemctl is-active --quiet wg-quick@wg0; then
    wg syncconf wg0 <(wg-quick strip wg0)
fi

# вывести QR на экран
if command -v qrencode >/dev/null; then
    qrencode -t ansiutf8 < "./clients/${userName}/${userName}.conf"
fi

echo "# Конфиг ${userName}.conf"
cat "./clients/${userName}/${userName}.conf"

# сохранить QR в PNG
if command -v qrencode >/dev/null; then
    qrencode -t png -o "./clients/${userName}/${userName}.png" < "./clients/${userName}/${userName}.conf"
fi
