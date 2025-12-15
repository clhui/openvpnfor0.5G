# OpenVPN 一键安装脚本（低内存优化）

本项目提供一个 Shell 脚本，用于在低内存（如 512MB）的 Linux 服务器上一键安装和配置 OpenVPN。脚本会自动处理 Swap 内存创建、防火墙关闭、多发行版依赖安装、证书生成、NAT 转发配置等所有必要步骤。

## 特性

- **一键安装**：单个命令完成所有部署工作。
- **低内存优化**：自动创建并启用 Swap 交换分区，确保 OpenVPN 在 512MB 内存的机器上稳定运行。
- **防火墙自动处理**：自动检测并关闭 `ufw` 和 `firewalld`，避免连接问题。
- **多发行版支持**：兼容 Debian, Ubuntu, CentOS, RHEL, Rocky Linux, AlmaLinux 等主流系统。
- **安全配置**：使用 `tls-crypt` 防护控制通道，数据通道默认 `AES-256-GCM` 加密。
- **客户端管理**：附带独立的脚本，方便快速新增客户端。

## 安装

### 前提条件

- 一台拥有公网 IP 的 Linux 服务器。
- 使用 `root` 用户执行。

### 一键安装指令

curl -fsSL https://raw.githubusercontent.com/clhui/openvpnfor0.5G/main/install.sh | bash

安装完成后，第一个客户端的配置文件会生成在 `/root/client.ovpn`。

### 自定义安装

你可以通过设置环境变量来自定义安装选项：

- `SWAP_SIZE_MB`：要创建的 Swap 大小（MB），默认 `1024`。
- `PORT`：OpenVPN 服务端口，默认 `1194`。
- `PROTO`：使用的协议，`udp` 或 `tcp`，默认 `udp`。
- `DNS1`, `DNS2`：推送给客户端的 DNS，默认 `1.1.1.1` 和 `1.0.0.1`。

**示例：** 使用 2048MB Swap 和 443/tcp 端口进行安装。

```bash
SWAP_SIZE_MB=2048 PORT=443 PROTO=tcp curl -fsSL https://raw.githubusercontent.com/clhui/openvpnfor0.5G/main/install.sh | bash
```

## 新增客户端

如果需要为更多设备生成配置文件，请在服务器上执行以下命令。

将 `alice` 替换为你想要的客户端名称。

```bash
# 下载新增客户端脚本
curl -fsSL https://raw.githubusercontent.com/clhui/openvpnfor0.5G/main/add-client.sh -o add-client.sh
chmod +x add-client.sh

# 执行脚本以创建名为 alice 的客户端
./add-client.sh alice
```

新的配置文件将生成在 `/root/alice.ovpn`。

## 脚本详解

`install.sh` 脚本会自动完成以下任务：

1.  **检查 Root 权限**：确保以 `root` 用户运行。
2.  **开启 Swap**：检查系统是否存在 Swap。如果不存在，则创建一个指定大小的 `/swapfile` 并启用。
3.  **关闭防火墙**：检测并禁用 `ufw` 和 `firewalld` 服务，以简化网络配置。
4.  **安装依赖**：自动检测包管理器 (`apt`, `dnf`, `yum`) 并安装 `openvpn`, `easy-rsa`, `iptables` 等核心组件。
5.  **配置 Easy-RSA**：初始化 PKI 环境，构建 CA、服务器和客户端证书。
6.  **配置 OpenVPN 服务端**：生成 `server.conf`，包含网络拓扑、加密套件、`tls-crypt` 等安全设置。
7.  **启用 IP 转发与 NAT**：修改内核参数以允许 IP 转发，并使用 `iptables` 设置 MASQUERADE 规则实现 NAT。
8.  **设置开机自启**：将 OpenVPN 服务和 `iptables` 规则恢复服务设置为开机自启。
9.  **生成首个客户端**：自动获取服务器公网 IP 并生成第一个客户端配置文件 (`client.ovpn`)。

## 安全警告

本脚本为了最大程度地简化安装，会自动禁用 `ufw` 和 `firewalld`。这意味着服务器的防火墙将被关闭。在生产环境中，建议根据实际需求配置更精细的防火墙规则，而不是完全禁用。脚本已包含允许 OpenVPN 流量的 `iptables` 规则，因此可以修改脚本移除关闭防火墙的步骤，手动管理防火墙。