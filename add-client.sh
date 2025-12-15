#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "需要使用 root 运行" >&2
  exit 1
fi

NAME=${1:-client2}

if [[ ! -f /etc/openvpn/easy-rsa/easyrsa ]]; then
  echo "未找到 easy-rsa" >&2
  exit 1
fi

cd /etc/openvpn/easy-rsa
EASYRSA_BATCH=1 ./easyrsa build-client-full "$NAME" nopass

PORT=$(awk '/^port /{print $2}' /etc/openvpn/server/server.conf)
PROTO=$(awk '/^proto /{print $2}' /etc/openvpn/server/server.conf)

HOST_IP=$(curl -4fsSL http://ipinfo.io/ip || curl -4fsSL https://api.ipify.org || echo "SERVER_IP")

CA=$(cat /etc/openvpn/easy-rsa/pki/ca.crt)
CRT=$(cat /etc/openvpn/easy-rsa/pki/issued/${NAME}.crt)
KEY=$(cat /etc/openvpn/easy-rsa/pki/private/${NAME}.key)
TC=$(cat /etc/openvpn/server/tls-crypt.key)

cat >/root/${NAME}.ovpn <<EOF
client
dev tun
proto ${PROTO}
remote ${HOST_IP} ${PORT}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
key-direction 1
verb 3
auth SHA256
cipher AES-256-CBC
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
<ca>
${CA}
</ca>
<cert>
${CRT}
</cert>
<key>
${KEY}
</key>
<tls-crypt>
${TC}
</tls-crypt>
EOF

echo "/root/${NAME}.ovpn 生成完成"