#!/bin/bash

echo "# Reseting..."

cd /etc/wireguard || exit 1

# удалить директории клиентов
rm -rf ./clients

# обнулить счётчик IP в state.env
# shellcheck source=/dev/null
. ./state.env
LAST_USED_IP=1
cat > ./state.env <<EOF
ENDPOINT="${ENDPOINT}"
DNS="${DNS}"
VPN_SUBNET="${VPN_SUBNET}"
LAST_USED_IP=${LAST_USED_IP}
EOF

# восстановить серверный конфиг из шаблона
cp -f wg0.conf.def wg0.conf

systemctl stop wg-quick@wg0
wg-quick down wg0

echo "# Reseted"