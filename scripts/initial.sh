#!/bin/bash
# Полный сценарий первой установки: снести предыдущую установку,
# поставить заново, выдать конфиг первому клиенту.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)

echo "# Installing WireGuard"

"${HERE}/uninstall.sh"
"${HERE}/install.sh"
"${HERE}/add-client.sh"

echo "# WireGuard installed"
