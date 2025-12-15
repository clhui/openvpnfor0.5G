# OpenVPN Access Server 一键安装脚本（低内存优化）

本项目提供一个 Shell 脚本，用于在低内存（如 512MB）的 Linux 服务器上一键安装 **OpenVPN Access Server**（商业版）。脚本会预先处理 Swap 内存创建和防火墙关闭，然后调用官方安装程序完成安装。

## 特性

- **一键安装**：单个命令完成所有部署工作。
- **官方版本**：安装 OpenVPN Access Server，提供友好的 Web 管理界面。
- **免费授权**：包含 2 个免费的并发连接数，适合个人或小型团队使用。
- **低内存优化**：自动创建并启用 Swap 交换分区，缓解低内存服务器的运行压力。
- **防火墙自动处理**：自动检测并关闭 `ufw` 和 `firewalld`，避免连接问题。

## 安装

### 前提条件

- 一台拥有公网 IP 的 Linux 服务器。
- 使用 `root` 用户执行。

### 一键安装指令

你可以使用以下任何一种方式执行脚本：

**方式一：使用管道 (pipe)**
```bash
curl -fsSL https://raw.githubusercontent.com/clhui/openvpnfor0.5G/main/install.sh | bash
```

**方式二：使用进程替换 (process substitution)**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/clhui/openvpnfor0.5G/main/install.sh)
```

### 自定义 Swap 大小

默认创建 1024MB 的 Swap。你可以通过设置 `SWAP_SIZE_MB` 环境变量来调整大小。

**方式一：使用管道 (pipe)**
```bash
SWAP_SIZE_MB=2048 curl -fsSL https://raw.githubusercontent.com/clhui/openvpnfor0.5G/main/install.sh | bash
```

**方式二：使用进程替换 (process substitution)**
```bash
SWAP_SIZE_MB=2048 bash <(curl -fsSL https://raw.githubusercontent.com/clhui/openvpnfor0.5G/main/install.sh)
```

## 安装后操作

### 1. 获取登录凭据

安装脚本执行完毕后，**请仔细检查终端的输出日志**。官方安装程序会自动生成管理员界面的 URL、默认用户名 `openvpn` 以及一个**随机密码**。

#### 忘记密码或关闭了窗口怎么办？

如果忘记了初始密码或不慎关闭了安装窗口，可以通过查看日志文件来找回：

```bash
cat /usr/local/openvpn_as/init.log
```

该文件包含了完整的初始安装信息，包括随机生成的密码。

输出示例：

```
+++++++++++++++++++++++++++++++++++++++++++++++
Access Server 3.0.2 has been successfully installed in /usr/local/openvpn_as
Configuration log file has been written to /usr/local/openvpn_as/init.log

Access Server Web UIs are available here:
Admin UI: https://<你的IP>:943/admin
Client UI: https://<你的IP>:943

To login please use the "openvpn" account with "RR4ImyhwbFFq" password.
(password can be changed on Admin UI)
+++++++++++++++++++++++++++++++++++++++++++++++
```

### 2. 登录管理后台

使用上一步获取的 URL（例如 `https://<你的IP>:943/admin`）和凭据登录 **Admin UI**。

### 3. 管理用户和下载配置

- **修改管理员密码**：首次登录后，建议立即修改 `openvpn` 用户的密码。
- **添加新用户**：你可以在 Web 界面中直接添加新用户（免费版总共支持 2 个并发连接）。
- **下载客户端配置**：访问 **Client UI**（例如 `https://<你的IP>:943`），使用你创建的普通用户账号登录，即可下载对应的 `.ovpn` 配置文件。

## 安全警告

本脚本为了最大程度地简化安装，会自动禁用 `ufw` 和 `firewalld`。这意味着服务器的防火墙将被关闭。在生产环境中，建议根据实际需求配置更精细的防火墙规则，而不是完全禁用。