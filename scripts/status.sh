#!/bin/bash
# Состояние WireGuard-сервиса.
set -euo pipefail

if command -v systemctl >/dev/null && systemctl is-active --quiet wg-quick@wg0; then
    wg show wg0
else
    echo "WireGuard сервис не запущен"
fi
