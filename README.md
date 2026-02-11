# 📘 GProxy - SSH 隧道网络加速工具

> **解决国内服务器访问 GitHub、Docker Hub 等海外资源速度慢的问题**

GProxy 是一个基于 SSH 隧道的轻量级网络加速工具。通过海外 VPS 作为跳板，为国内服务器（包括 iStoreOS/OpenWrt 路由器）提供透明的 SOCKS5 代理，加速 `git clone`、`docker pull`、`pip install` 等命令的网络访问。

---

## 🎯 解决什么问题？

### 典型场景

你有一台**国内服务器**或 **iStoreOS 路由器**，在执行以下操作时速度极慢或失败：

```bash
# Git 克隆大型仓库
git clone https://github.com/huggingface/transformers.git
# 速度: 10KB/s 甚至超时 ❌

# Docker 拉取镜像
docker pull alpine:latest
# 速度: 极慢或连接失败 ❌

# Python 包安装
pip install torch
# 速度: 龟速 ❌
```

### GProxy 的解决方案

通过一台**海外 VPS**（如美国、日本、香港）建立 SSH 隧道，所有命令自动走代理：

```bash
# 使用 GProxy 加速
gproxy git clone https://github.com/huggingface/transformers.git
# 速度: 5MB/s+ ✅

gproxy docker pull alpine:latest
# 速度: 快速 ✅

gproxy pip install torch
# 速度: 飞快 ✅
```

---

## ✨ 核心特性

* **零配置代理**：命令前加 `gproxy` 即可，无需修改系统全局代理
* **按需连接**：仅在执行命令时建立隧道，命令结束自动断开
* **智能密钥发现**：自动扫描 `config/` 目录下的 SSH 私钥
* **iStoreOS 完美支持**：自动安装 `openssh-client`，解决 Dropbear 兼容性问题
* **跨平台**：支持标准 Linux（Ubuntu/Debian/CentOS）和 OpenWrt/iStoreOS

---

## 📋 前置要求

### 1. 国内服务器（任选其一）

- **标准 Linux 服务器**：Ubuntu、Debian、CentOS 等
- **iStoreOS/OpenWrt 路由器**：固件版本 >= 21.02

### 2. 海外 VPS

- **地理位置**：美国、日本、香港、新加坡等（网络质量好的地区）
- **SSH 访问**：需要 SSH 登录权限（root 或普通用户）
- **SSH 密钥对**：建议使用密钥认证（更安全、更方便）

> **提示**：如果还没有 SSH 密钥对，参见下方"准备 SSH 密钥"章节。

---

## 🚀 快速开始

### 步骤 1：准备 SSH 密钥（如已有可跳过）

在**国内服务器**上生成 SSH 密钥对：

```bash
# 生成密钥对（一路回车使用默认设置）
ssh-keygen -t rsa -b 4096 -f ~/.ssh/vps_key

# 将公钥复制到海外 VPS
ssh-copy-id -i ~/.ssh/vps_key.pub root@<海外VPS的IP>

# 测试免密登录
ssh -i ~/.ssh/vps_key root@<海外VPS的IP>
```

### 步骤 2：安装 GProxy

#### 标准 Linux

```bash
# 克隆项目
git clone https://github.com/xtianowner/gproxy-tool.git
cd gproxy-tool

# 将 SSH 私钥复制到 config 目录（GProxy 会自动发现）
cp ~/.ssh/vps_key config/

# 安装（需要 sudo 权限）
sudo sh install.sh
```

#### iStoreOS/OpenWrt

```bash
# 方式一：通过 scp 上传项目到路由器
scp -r gproxy-tool/ root@<路由器IP>:/tmp/

# 方式二：在路由器上直接 git clone（如果有 git）
# ssh root@<路由器IP>
# cd /tmp && git clone https://github.com/xtianowner/gproxy-tool.git

# 登录路由器
ssh root@<路由器IP>
cd /tmp/gproxy-tool

# 将 SSH 私钥复制到 config 目录
cp /path/to/vps_key config/

# 安装（iStoreOS 默认是 root，无需 sudo）
sh install.sh
```

> **重要**：iStoreOS 安装时会自动检测并安装 `openssh-client`（Dropbear 不支持 SOCKS5 代理）。如果自动安装失败，请手动执行：
> ```bash
> opkg update && opkg install openssh-client
> ```

### 步骤 3：首次配置

首次运行任何命令时，GProxy 会进入交互式配置向导：

```bash
gproxy curl -I https://www.google.com
```

**配置流程**：

```
[INFO] 初次运行，需要配置海外服务器信息...
----------------------------------------------------
🖥️  请输入海外服务器 IP: 1.2.3.4
👤 请输入用户名 (默认 root): [直接回车]
🚪 请输入 SSH 端口 (默认 22): [直接回车]
----------------------------------------------------
[OK] 自动发现密钥文件: /usr/lib/gproxy/config/vps_key
🔑 使用此密钥？[Y/n] [直接回车]
[OK] 密钥权限已修正 (600)
[OK] 配置已保存至: /root/.config/gproxy/config.env
[INFO] 正在连接 1.2.3.4...
[OK] 代理就绪，执行: curl -I https://www.google.com
```

配置完成后，以后使用无需再次配置。

---

## 💡 使用示例

### 1. Git 加速（最常用）

```bash
# 克隆大型仓库
gproxy git clone https://github.com/huggingface/transformers.git

# 拉取更新
cd transformers
gproxy git pull
```

### 2. Docker 加速

```bash
# 拉取镜像
gproxy docker pull alpine:latest

# 构建镜像（如果 Dockerfile 中有 apt/yum 等需要外网的操作）
gproxy docker build -t myapp .
```

### 3. 包管理器加速

```bash
# Python pip
gproxy pip install openai torch transformers

# Node.js npm
gproxy npm install express

# Ubuntu/Debian apt
gproxy bash -c "apt update && apt install -y vim"

# OpenWrt opkg
gproxy opkg update && gproxy opkg install curl
```

### 4. 下载文件

```bash
# wget 下载
gproxy wget https://github.com/xxx/release.zip

# curl 下载
gproxy curl -O https://example.com/file.tar.gz
```

### 5. 执行安装脚本

对于 `bash <(curl ...)` 这种复合命令，需要用 `bash -c` 包裹：

```bash
# ✅ 正确用法
gproxy bash -c "bash <(curl -sL https://raw.githubusercontent.com/xxx/install.sh)"

# ❌ 错误用法（curl 会在代理启动前执行）
gproxy bash <(curl -sL https://...)
```

---

## 🔧 高级配置

### 重新配置服务器信息

```bash
gproxy --config
```

### 修改本地代理端口

如果默认端口 `19527` 被占用，编辑 `lib/tunnel.sh`：

```bash
sudo vim /usr/lib/gproxy/lib/tunnel.sh
# 修改 LOCAL_PORT=19527 为其他端口
```

### 使用多个海外 VPS

创建不同的配置文件：

```bash
# 配置文件位置
~/.config/gproxy/config.env

# 可以手动编辑切换不同的 VPS
vim ~/.config/gproxy/config.env
```

---

## 🗑️ 卸载

```bash
# 标准 Linux
sudo sh /path/to/gproxy-tool/uninstall.sh

# iStoreOS/OpenWrt
sh /path/to/gproxy-tool/uninstall.sh
```

卸载时会询问是否同时删除配置文件。

---

## ❓ 常见问题

**Q: iStoreOS 上提示 "String too long" 或连接无响应？**

* **A**: iStoreOS 默认的 Dropbear SSH 客户端不支持 SOCKS5 代理功能。GProxy 会自动安装 `openssh-client`。如果自动安装失败，请手动执行：`opkg update && opkg install openssh-client`。

**Q: 提示 "Permission denied (publickey)"？**

* **A**: SSH 密钥认证失败。检查：
  1. 私钥路径是否正确（应在 `config/` 目录下）
  2. 公钥是否已添加到海外 VPS 的 `~/.ssh/authorized_keys`
  3. 私钥权限是否为 600（GProxy 会自动修正）

**Q: 提示 "bind: Address already in use"？**

* **A**: 本地代理端口（默认 19527）被占用。可编辑 `lib/tunnel.sh`，修改 `LOCAL_PORT` 变量。

**Q: 海外 VPS 需要什么配置？**

* **A**: 
  - 最低配置即可（1核1G即可）
  - 需要开放 SSH 端口（默认 22）
  - 网络质量好的地区（美国、日本、香港等）
  - 建议使用 CN2 GIA 或 IPLC 线路的 VPS

**Q: 会消耗海外 VPS 多少流量？**

* **A**: 所有通过 GProxy 执行的命令产生的流量都会走海外 VPS。例如 `git clone` 一个 1GB 的仓库，会消耗海外 VPS 约 1GB 流量。

**Q: 可以用于浏览器上网吗？**

* **A**: GProxy 设计用于命令行工具加速，不适合浏览器。如需浏览器代理，建议使用 V2Ray、Clash 等专业工具。

**Q: 安全性如何？**

* **A**: 
  - 使用 SSH 隧道，流量经过加密
  - 建议使用 SSH 密钥认证而非密码
  - 私钥文件不会被提交到 Git（已在 `.gitignore` 中排除）

---

## 🔍 工作原理

```mermaid
graph LR
    A[国内服务器] -->|SSH 隧道| B[海外 VPS]
    B -->|访问| C[GitHub/Docker Hub]
    
    style A fill:#f9f,stroke:#333
    style B fill:#bbf,stroke:#333
    style C fill:#bfb,stroke:#333
```

1. **建立隧道**：GProxy 通过 SSH 连接到海外 VPS，建立 SOCKS5 动态端口转发
2. **注入环境变量**：设置 `http_proxy`、`https_proxy` 等环境变量指向本地 SOCKS5 端口
3. **执行命令**：在代理环境中执行用户命令（如 `git clone`）
4. **自动清理**：命令结束后自动关闭 SSH 隧道，不残留后台进程

---

## 📁 项目结构

```
gproxy-tool/
├── bin/
│   └── gproxy           # 主入口脚本
├── lib/
│   ├── common.sh        # 公共函数（日志、平台检测）
│   ├── config.sh        # 配置管理（智能密钥发现）
│   └── tunnel.sh        # 隧道管理（OpenSSH 优先、密钥转换）
├── config/
│   └── README.md        # 密钥文件说明（将 SSH 私钥放此目录）
├── install.sh           # 安装脚本
├── uninstall.sh         # 卸载脚本
└── README.md            # 本文档
```

---

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

---

## 📄 许可证

MIT License
