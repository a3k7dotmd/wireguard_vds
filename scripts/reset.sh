#!/bin/bash

echo "# Reseting..."

cd /etc/wireguard || exit 1

# удалить директории клиентов
rm -rf ./clients

# обнулить счётчик IP
echo "1" > last_used_ip.var

# восстановить серверный конфиг из шаблона
cp -f wg0.conf.def wg0.conf

systemctl stop wg-quick@wg0
wg-quick down wg0

echo "# Reseted"