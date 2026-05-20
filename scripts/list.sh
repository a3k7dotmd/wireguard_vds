#!/bin/bash
# Список зарегистрированных клиентов (email, IP, public key).
set -euo pipefail

WORK_DIR="${WORK_DIR:-/etc/wireguard}"

cd "${WORK_DIR}" || exit 1

if [ ! -f wg0.conf ]; then
    echo "[#] wg0.conf не найден. WireGuard не установлен?" >&2
    exit 1
fi

awk '
BEGIN {
    printf "%-30s %-18s %s\n", "EMAIL", "IP", "PUBLIC KEY"
    printf "%-30s %-18s %s\n", "─────", "──", "──────────"
}
/^\[Peer\] # / {
    email = substr($0, 10)
    next
}
/^PublicKey = / {
    pubkey = $3
    next
}
/^AllowedIPs = / {
    ip = $3
    if (email != "") {
        printf "%-30s %-18s %s\n", email, ip, pubkey
        email = ""
        pubkey = ""
    }
    next
}
' wg0.conf
