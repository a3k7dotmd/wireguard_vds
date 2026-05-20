#!/bin/bash

# рабочая директория
WORK_DIR=/etc/wireguard

# установка wireguard
apt update && \
apt install -y wireguard-dkms wireguard-tools qrencode


# разрешить перенаправление пакетов
IP_FORWARD="net.ipv4.ip_forward=1"
FORWARD_FILE=/etc/sysctl.d/99-ip_forward.conf
echo "${IP_FORWARD}" > "${FORWARD_FILE}" && sysctl -p "${FORWARD_FILE}"

# перейти в рабочую директорию
cd "${WORK_DIR}" || exit 1

# дефолтный umask
umask 077

# сгенерировать серверные ключи


if [[ -e server.pub && -e server.key ]]
  then echo "ключи есть"	
  else
    SERVER_PRIVKEY=$( wg genkey )
    SERVER_PUBKEY=$( echo "${SERVER_PRIVKEY}" | wg pubkey )
    echo "${SERVER_PUBKEY}" > ./server.pub
    echo "${SERVER_PRIVKEY}" > ./server.key
fi


# определить endpoint — внешний IP сервера
WAN_IP=$(curl -fsS -4 https://api.ipify.org)

read -r -p "Enter the endpoint (external ip and port) in format [ipv4:port]. ([ENTER] set ${WAN_IP}:51820): " ENDPOINT
if [ -z "${ENDPOINT}" ]; then
    ENDPOINT="${WAN_IP}:51820"
fi

# адрес сервера в VPN-подсети
if [ -z "${1}" ]
  then
    read -r -p "Enter the server address in the VPN subnet (CIDR format), [ENTER] set to default: 10.8.8.1: " SERVER_IP
    if [ -z "${SERVER_IP}" ]
      then SERVER_IP="10.8.8.1"
    fi
  else SERVER_IP="${1}"
fi

# построить CIDR из выбранного SERVER_IP (например 10.8.8.1 → 10.8.8.0/24)
IFS=. read -r SUBNET_O1 SUBNET_O2 SUBNET_O3 _ <<<"${SERVER_IP}"
VPN_SUBNET="${SUBNET_O1}.${SUBNET_O2}.${SUBNET_O3}.0/24"

read -r -p "Enter the ip address of the server DNS (CIDR format), [ENTER] set to default: 9.9.9.9): " DNS
if [ -z "${DNS}" ]
then DNS="9.9.9.9"
fi
LAST_USED_IP=1

# определить WAN-интерфейс
HERE_INSTALL=$(cd "$(dirname "$0")" && pwd)
WAN_INTERFACE_NAME=$("${HERE_INSTALL}/detect-wan.sh")

SERVER_EXTERNAL_PORT=$(cut -d: -f2 <<<"${ENDPOINT}")
cat > ./wg0.conf.def << EOF
[Interface]
Address = ${SERVER_IP}
SaveConfig = false
PrivateKey = ${SERVER_PRIVKEY}
ListenPort = ${SERVER_EXTERNAL_PORT}
PostUp   = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${WAN_INTERFACE_NAME} -j MASQUERADE;
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${WAN_INTERFACE_NAME} -j MASQUERADE;
EOF

# единый state-файл для последующих скриптов
cat > ./state.env <<EOF
ENDPOINT="${ENDPOINT}"
DNS="${DNS}"
VPN_SUBNET="${VPN_SUBNET}"
LAST_USED_IP=${LAST_USED_IP}
EOF

cp -f ./wg0.conf.def ./wg0.conf

systemctl enable wg-quick@wg0
