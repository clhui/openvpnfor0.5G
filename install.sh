#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "需要使用 root 运行" >&2
  exit 1
fi

SWAP_SIZE_MB=${SWAP_SIZE_MB:-1024}
PORT=${PORT:-1194}
PROTO=${PROTO:-udp}
VPN_NET=${VPN_NET:-10.8.0.0}
VPN_MASK=${VPN_MASK:-255.255.255.0}
DNS1=${DNS1:-1.1.1.1}
DNS2=${DNS2:-1.0.0.1}

detect_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then echo apt; return; fi
  if command -v dnf >/dev/null 2>&1; then echo dnf; return; fi
  if command -v yum >/dev/null 2>&1; then echo yum; return; fi
  echo none
}

pkg_install() {
  local pkgs=(openvpn easy-rsa iptables curl ca-certificates)
  case "$(detect_pkg_manager)" in
    apt)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y
      apt-get install -y "${pkgs[@]}" >/dev/null
      ;;
    dnf)
      dnf install -y "${pkgs[@]}" >/dev/null
      ;;
    yum)
      yum install -y epel-release >/dev/null || true
      yum install -y "${pkgs[@]}" >/dev/null
      ;;
    *)
      echo "不支持的系统包管理器" >&2
      exit 1
      ;;
  esac
}

ensure_swap() {
  local has_swap
  has_swap=$(free -m | awk '/Swap/ {print $2}')
  if [[ "$has_swap" -eq 0 ]]; then
    fallocate -l "${SWAP_SIZE_MB}M" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count="${SWAP_SIZE_MB}"
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    if ! grep -q '^/swapfile' /etc/fstab; then
      echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    sysctl vm.swappiness=10 >/dev/null || true
  fi
}

disable_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    ufw disable || true
    systemctl stop ufw >/dev/null 2>&1 || true
    systemctl disable ufw >/dev/null 2>&1 || true
  fi
  if systemctl list-unit-files | grep -q '^firewalld'; then
    systemctl stop firewalld >/dev/null 2>&1 || true
    systemctl disable firewalld >/dev/null 2>&1 || true
  fi
}

prepare_easy_rsa() {
  mkdir -p /etc/openvpn/easy-rsa
  if [[ -d /usr/share/easy-rsa/ ]]; then
    rsync -a /usr/share/easy-rsa/ /etc/openvpn/easy-rsa/ 2>/dev/null || cp -r /usr/share/easy-rsa/* /etc/openvpn/easy-rsa/
  fi
  if [[ -d /usr/share/easy-rsa/3/ && ! -f /etc/openvpn/easy-rsa/easyrsa ]]; then
    rsync -a /usr/share/easy-rsa/3/ /etc/openvpn/easy-rsa/ 2>/dev/null || cp -r /usr/share/easy-rsa/3/* /etc/openvpn/easy-rsa/
  fi
  if [[ ! -f /etc/openvpn/easy-rsa/easyrsa ]]; then
    echo "未找到 easy-rsa" >&2
    exit 1
  fi
}

build_pki() {
  cd /etc/openvpn/easy-rsa
  ./easyrsa init-pki
  EASYRSA_BATCH=1 ./easyrsa build-ca nopass
  ./easyrsa gen-dh
  EASYRSA_BATCH=1 ./easyrsa build-server-full server nopass
  EASYRSA_BATCH=1 ./easyrsa build-client-full client nopass
}

install_server_files() {
  mkdir -p /etc/openvpn/server
  cp /etc/openvpn/easy-rsa/pki/ca.crt /etc/openvpn/server/
  cp /etc/openvpn/easy-rsa/pki/issued/server.crt /etc/openvpn/server/
  cp /etc/openvpn/easy-rsa/pki/private/server.key /etc/openvpn/server/
  cp /etc/openvpn/easy-rsa/pki/dh.pem /etc/openvpn/server/
  openvpn --genkey secret /etc/openvpn/server/tls-crypt.key
  local grp
  if getent group nogroup >/dev/null 2>&1; then grp=nogroup; else grp=nobody; fi
  cat >/etc/openvpn/server/server.conf <<EOF
port ${PORT}
proto ${PROTO}
dev tun
user nobody
group ${grp}
persist-key
persist-tun
topology subnet
server ${VPN_NET} ${VPN_MASK}
client-to-client
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS ${DNS1}"
push "dhcp-option DNS ${DNS2}"
keepalive 10 120
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
cipher AES-256-CBC
auth SHA256
verb 3
tls-crypt /etc/openvpn/server/tls-crypt.key
key-direction 0
ca /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/server.crt
key /etc/openvpn/server/server.key
dh /etc/openvpn/server/dh.pem
EOF
}

enable_forwarding() {
  mkdir -p /etc/sysctl.d
  echo 'net.ipv4.ip_forward=1' >/etc/sysctl.d/99-openvpn-forward.conf
  sysctl -p /etc/sysctl.d/99-openvpn-forward.conf >/dev/null
}

setup_iptables() {
  local iface
  iface=$(ip -4 route list default | awk '{print $5}' | head -n1)
  iptables -t nat -A POSTROUTING -s ${VPN_NET}/24 -o "$iface" -j MASQUERADE
  iptables -A INPUT -p ${PROTO} --dport ${PORT} -j ACCEPT
  iptables -A FORWARD -s ${VPN_NET}/24 -j ACCEPT
  iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
  iptables-save >/etc/iptables.rules
  cat >/etc/systemd/system/iptables-restore.service <<EOF
[Unit]
Description=Restore iptables rules
DefaultDependencies=no
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables.rules

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable iptables-restore.service
  systemctl start iptables-restore.service
}

start_openvpn() {
  if systemctl list-unit-files | grep -q '^openvpn-server@'; then
    systemctl enable openvpn-server@server
    systemctl restart openvpn-server@server
  else
    systemctl enable openvpn
    systemctl restart openvpn
  fi
}

generate_client() {
  local name=${1:-client}
  local host_ip
  host_ip=$(curl -4fsSL http://ipinfo.io/ip || curl -4fsSL https://api.ipify.org || echo "SERVER_IP")
  local proto_upper
  proto_upper=$(echo ${PROTO} | tr '[:lower:]' '[:upper:]')
  local ca crt key tc
  ca=$(cat /etc/openvpn/easy-rsa/pki/ca.crt)
  crt=$(cat /etc/openvpn/easy-rsa/pki/issued/${name}.crt)
  key=$(cat /etc/openvpn/easy-rsa/pki/private/${name}.key)
  tc=$(cat /etc/openvpn/server/tls-crypt.key)
  cat >/root/${name}.ovpn <<EOF
client
dev tun
proto ${PROTO}
remote ${host_ip} ${PORT}
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
${ca}
</ca>
<cert>
${crt}
</cert>
<key>
${key}
</key>
<tls-crypt>
${tc}
</tls-crypt>
EOF
}

pkg_install
ensure_swap
disable_firewall
prepare_easy_rsa
build_pki
install_server_files
enable_forwarding
setup_iptables
start_openvpn
generate_client client

echo "安装完成，客户端配置: /root/client.ovpn"