#!/bin/sh

# =================================================================
# GProxy 通用安装脚本
# 兼容标准 Linux 和 iStore (OpenWrt/BusyBox ash)
# =================================================================

set -e

# --- 路径定义 ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_BIN="/usr/bin"
INSTALL_LIB="/usr/lib/gproxy"
SOURCE_BIN="$SCRIPT_DIR/bin/gproxy"
SOURCE_LIB="$SCRIPT_DIR/lib"

# --- 颜色输出 ---
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    RED='\033[0;31m'
    NC='\033[0m'
else
    GREEN='' YELLOW='' RED='' NC=''
fi

log_ok()   { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
log_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
log_err()  { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

# --- 权限检测 ---
need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            log_warn "需要 root 权限，将使用 sudo 重新执行..."
            exec sudo sh "$0" "$@"
        else
            log_err "请以 root 用户身份运行此脚本"
            exit 1
        fi
    fi
}

# --- 安装前检查 ---
preflight_check() {
    if [ ! -f "$SOURCE_BIN" ]; then
        log_err "找不到 $SOURCE_BIN，请在项目根目录运行此脚本"
        exit 1
    fi
    if [ ! -d "$SOURCE_LIB" ]; then
        log_err "找不到 $SOURCE_LIB 目录，请检查项目完整性"
        exit 1
    fi
}

# --- 依赖安装 ---
# NOTE: 在 OpenWrt/iStoreOS 上，必须在安装阶段预装 openssh-client
# 因为运行时 GProxy 本身还未建立代理，opkg 可能无法下载包（鸡生蛋问题）
install_dependencies() {
    # 仅在 OpenWrt 环境下执行
    if [ ! -f /etc/openwrt_release ]; then
        return 0
    fi

    # 检查是否已有 OpenSSH 客户端
    _has_openssh=false
    for _p in /usr/bin/ssh /usr/local/bin/ssh; do
        if [ -x "$_p" ]; then
            _v=$("$_p" -V 2>&1 || true)
            if echo "$_v" | grep -qi "openssh"; then
                _has_openssh=true
                break
            fi
        fi
    done

    if [ "$_has_openssh" = true ]; then
        log_ok "OpenSSH 客户端已就绪"
        return 0
    fi

    # 需要安装 openssh-client
    if ! command -v opkg >/dev/null 2>&1; then
        log_warn "未找到 opkg，请手动安装 openssh-client"
        return 0
    fi

    log_warn "检测到 iStoreOS 环境，需要安装 openssh-client (Dropbear 不支持 SOCKS5 代理)"
    printf "正在更新软件源...\n"
    if ! opkg update 2>&1 | tail -1; then
        log_warn "opkg update 失败，跳过依赖安装"
        log_warn "请稍后手动执行: opkg update && opkg install openssh-client"
        return 0
    fi

    printf "正在安装 openssh-client...\n"
    if opkg install openssh-client 2>&1; then
        log_ok "openssh-client 安装成功"
    else
        log_warn "openssh-client 安装失败"
        log_warn "请稍后手动执行: opkg install openssh-client"
        log_warn "没有 openssh-client，GProxy 将无法正常工作"
    fi
}

# --- 主安装流程 ---
do_install() {
    printf "📦 正在安装 GProxy...\n"
    printf '%s\n' "----------------------------------------------------"

    # 1. 安装 lib 模块
    if [ -d "$INSTALL_LIB" ]; then
        log_warn "检测到已安装的 lib 目录，正在更新..."
        rm -rf "$INSTALL_LIB"
    fi
    mkdir -p "$INSTALL_LIB"
    cp "$SOURCE_LIB"/*.sh "$INSTALL_LIB/"
    chmod 644 "$INSTALL_LIB"/*.sh
    log_ok "lib 模块已安装到 $INSTALL_LIB"

    # 2. 安装 config 目录（密钥文件等）
    if [ -d "$SCRIPT_DIR/config" ]; then
        mkdir -p "$INSTALL_LIB/config"
        cp "$SCRIPT_DIR/config"/* "$INSTALL_LIB/config/" 2>/dev/null || true
        # 密钥文件权限必须为 600
        for _kf in "$INSTALL_LIB/config"/*.pem "$INSTALL_LIB/config"/id_rsa "$INSTALL_LIB/config"/id_ed25519; do
            [ -f "$_kf" ] && chmod 600 "$_kf"
        done
        log_ok "config 目录已安装到 $INSTALL_LIB/config"
    fi

    # 3. 安装主脚本
    if [ -f "$INSTALL_BIN/gproxy" ]; then
        log_warn "检测到已安装的 gproxy，正在更新..."
        rm -f "$INSTALL_BIN/gproxy"
    fi
    cp "$SOURCE_BIN" "$INSTALL_BIN/gproxy"
    chmod 755 "$INSTALL_BIN/gproxy"
    log_ok "主脚本已安装到 $INSTALL_BIN/gproxy"

    # 4. 验证安装
    printf '%s\n' "----------------------------------------------------"
    if command -v gproxy >/dev/null 2>&1; then
        log_ok "安装成功！"
        printf "\n"
        printf "👉 快速开始: gproxy curl -I https://www.google.com\n"
        printf "👉 查看帮助: gproxy --help\n"
        printf "👉 配置服务: gproxy --config\n"
        printf "👉 卸载工具: sh %s/uninstall.sh\n" "$SCRIPT_DIR"
    else
        log_warn "gproxy 已复制但可能不在 PATH 中"
        printf "请手动运行: %s/gproxy --help\n" "$INSTALL_BIN"
    fi
}

# --- 入口 ---
need_root "$@"
preflight_check
install_dependencies
do_install
