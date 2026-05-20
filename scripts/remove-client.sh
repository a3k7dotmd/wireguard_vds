#!/bin/bash

WORK_DIR="${WORK_DIR:-/etc/wireguard}"

if [ -z "${1}" ]; then
    read -r -p "Enter VPN user email or username to remove: " ARG
    if [ -z "${ARG}" ]; then
        echo "[#] Empty input. Exit"
        exit 1
    fi
else
    ARG="${1}"
fi

cd "${WORK_DIR}" || exit 1

# найти [Peer]-блок по email или username (по префиксу до @)
if [[ "${ARG}" == *@* ]]; then
    PEER_LINE=$(grep -F "[Peer] # ${ARG}" wg0.conf)
else
    PEER_LINE=$(grep -E "^\[Peer\] # ${ARG}@" wg0.conf)
fi

MATCHES=$(echo -n "${PEER_LINE}" | grep -c .)
if [[ "${MATCHES}" -eq 0 ]]; then
    echo "[#] No peer matching '${ARG}' found in wg0.conf. Exit"
    exit 1
fi
if [[ "${MATCHES}" -gt 1 ]]; then
    echo "[#] Multiple peers matching '${ARG}'. Be more specific:"
    echo "${PEER_LINE}"
    exit 1
fi

EMAIL=$(echo "${PEER_LINE}" | awk -F '# ' '{print $2}')
userName=$(echo "${EMAIL}" | awk -F "@" '{print $1}')
echo "Removing client ${userName} (${EMAIL})"

awk -v target="[Peer] # ${EMAIL}" '
    $0 == target { skip = 1; next }
    skip && /^$/ { skip = 0; next }
    skip && /^\[/ { skip = 0; print; next }
    skip { next }
    { print }
' wg0.conf > wg0.conf.tmp && mv wg0.conf.tmp wg0.conf

rm -rf "./clients/${userName}"

if command -v systemctl >/dev/null && systemctl is-active --quiet wg-quick@wg0; then
    wg syncconf wg0 <(wg-quick strip wg0)
fi

echo "# Client ${userName} removed"
