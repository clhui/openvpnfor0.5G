#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "需要使用 root 运行" >&2
  exit 1
fi

SWAP_SIZE_MB=${SWAP_SIZE_MB:-1024}

ensure_swap() {
  local has_swap
  has_swap=$(free -m | awk '/Swap/ {print $2}')
  if [[ "$has_swap" -eq 0 ]]; then
    echo "正在创建 ${SWAP_SIZE_MB}MB Swap 文件..."
    fallocate -l "${SWAP_SIZE_MB}M" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count="${SWAP_SIZE_MB}"
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    if ! grep -q '^/swapfile' /etc/fstab; then
      echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    sysctl vm.swappiness=10 >/dev/null || true
    echo "Swap 已启用。"
  else
    echo "Swap 已存在，跳过创建。"
  fi
}

disable_firewall() {
  echo "正在禁用防火墙..."
  if command -v ufw >/dev/null 2>&1; then
    ufw disable || true
    systemctl stop ufw >/dev/null 2>&1 || true
    systemctl disable ufw >/dev/null 2>&1 || true
    echo "UFW 已禁用。"
  fi
  if systemctl list-unit-files | grep -q '^firewalld'; then
    systemctl stop firewalld >/dev/null 2>&1 || true
    systemctl disable firewalld >/dev/null 2>&1 || true
    echo "Firewalld 已禁用。"
  fi
  echo "防火墙处理完成。"
}

echo "步骤 1/3: 检查并创建 Swap..."
ensure_swap

echo "步骤 2/3: 禁用防火墙..."
disable_firewall

echo "步骤 3/3: 下载并执行 OpenVPN Access Server 安装脚本..."
bash <(curl -fsSL https://packages.openvpn.net/as/install.sh) --yes

echo ""
echo "----------------------------------------------------------------------"
echo "OpenVPN Access Server 安装完成！"
echo "安装脚本的输出中应包含 Admin UI 地址、用户名 'openvpn' 和一个随机密码。"
echo "请检查上面的日志以获取登录凭据。"
echo "你可以使用这些凭据登录 Admin UI 并开始配置。"
echo "----------------------------------------------------------------------"