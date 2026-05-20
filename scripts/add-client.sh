#!/bin/bash

# рабочая директория
WORK_DIR=/etc/wireguard

# имя клиента из аргумента или интерактивного ввода
if [ -z "${1}" ]
  then
    read -r -p "Enter VPN user email: " EMAIL
    if [ -z "${EMAIL}" ]
      then
      echo "[#]Empty VPN user email. Exit"
      exit 1;
    fi
  else EMAIL="${1}"
fi
userName=$(echo "${EMAIL}" | awk -F "@" '{print $1}')
echo "Username is ${userName}"

cd "${WORK_DIR}" || exit 1

# shellcheck source=/dev/null
. "${WORK_DIR}/state.env"
PRESHARED_KEY=".preshared"
PRIV_KEY=".key"
PUB_KEY=".pub"
ALLOWED_IP="0.0.0.0/0"

# создать директорию для конфига и ключей клиента
if [ -d ./clients/"${userName}" ]
  then
    cd ./clients/"${userName}" || exit 1
  else mkdir -p ./clients/"${userName}" && \
      cd ./clients/"${userName}" && \
      umask 077
fi


CLIENT_PRESHARED_KEY=$( wg genpsk )
CLIENT_PRIVKEY=$( wg genkey )
CLIENT_PUBLIC_KEY=$( echo "${CLIENT_PRIVKEY}" | wg pubkey )

echo "${CLIENT_PRESHARED_KEY}" > ./"${userName}${PRESHARED_KEY}"
echo "${CLIENT_PRIVKEY}" > ./"${userName}${PRIV_KEY}"
echo "${CLIENT_PUBLIC_KEY}" > ./"${userName}${PUB_KEY}"

read -r SERVER_PUBLIC_KEY < /etc/wireguard/server.pub

# выделить следующий свободный IP в пуле
OCTET_IP="${LAST_USED_IP}"
if [[ "${OCTET_IP}" -ge 254 ]]; then
    echo "Пул исчерпан!"
    exit 1
fi

OCTET_IP=$((OCTET_IP+1))
LAST_USED_IP="${OCTET_IP}"

# извлечь первые три октета из CIDR (например 10.8.8.0/24 → 10.8.8)
IFS=. read -r PREFIX_O1 PREFIX_O2 PREFIX_O3 _ <<<"${VPN_SUBNET%/*}"
CLIENT_IP="${PREFIX_O1}.${PREFIX_O2}.${PREFIX_O3}.${OCTET_IP}/32"

# обновить state.env с новым LAST_USED_IP
cat > "${WORK_DIR}/state.env" <<EOF
ENDPOINT="${ENDPOINT}"
DNS="${DNS}"
VPN_SUBNET="${VPN_SUBNET}"
LAST_USED_IP=${LAST_USED_IP}
EOF

# создать клиентский конфиг
cat > /etc/wireguard/clients/"${userName}"/"${userName}".conf << EOF
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

# дописать [Peer] в wg0.conf
cat >> /etc/wireguard/wg0.conf << _EOF_

[Peer] # ${EMAIL}
PublicKey = ${CLIENT_PUBLIC_KEY}
PresharedKey = ${CLIENT_PRESHARED_KEY}
AllowedIPs = ${CLIENT_IP}
_EOF_

# применить wg0.conf без обрыва активных туннелей
if systemctl is-active --quiet wg-quick@wg0; then
    wg syncconf wg0 <(wg-quick strip wg0)
else
    systemctl start wg-quick@wg0
fi

# вывести QR на экран
qrencode -t ansiutf8 < ./"${userName}".conf

# вывести содержимое конфига
echo "# Display ${userName}.conf"
cat ./"${userName}".conf

# сохранить QR в PNG
qrencode -t png -o ./"${userName}".png < ./"${userName}".conf
