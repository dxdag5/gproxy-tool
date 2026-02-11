#!/bin/sh

# =================================================================
# GProxy 卸载脚本
# 清理安装的文件和（可选）配置
# =================================================================

set -e

INSTALL_BIN="/usr/bin/gproxy"
INSTALL_LIB="/usr/lib/gproxy"
CONFIG_DIR="${HOME}/.config/gproxy"

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
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        log_warn "需要 root 权限，将使用 sudo 重新执行..."
        exec sudo sh "$0" "$@"
    else
        log_err "请以 root 用户身份运行此脚本"
        exit 1
    fi
fi

# --- 卸载流程 ---
printf "🗑️  正在卸载 GProxy...\n"
printf '%s\n' "----------------------------------------------------"

# 1. 删除主脚本
if [ -f "$INSTALL_BIN" ] || [ -L "$INSTALL_BIN" ]; then
    rm -f "$INSTALL_BIN"
    log_ok "已删除 $INSTALL_BIN"
else
    log_warn "$INSTALL_BIN 不存在，跳过"
fi

# 2. 删除 lib 目录
if [ -d "$INSTALL_LIB" ]; then
    rm -rf "$INSTALL_LIB"
    log_ok "已删除 $INSTALL_LIB"
else
    log_warn "$INSTALL_LIB 不存在，跳过"
fi

# 3. 询问是否删除配置文件
printf '%s\n' "----------------------------------------------------"
if [ -d "$CONFIG_DIR" ]; then
    printf '是否同时删除配置文件 (%s)? [y/N] ' "$CONFIG_DIR"
    read -r REPLY
    case "$REPLY" in
        y|Y|yes|YES)
            rm -rf "$CONFIG_DIR"
            log_ok "配置文件已删除"
            ;;
        *)
            log_ok "保留配置文件"
            ;;
    esac
else
    log_ok "无配置文件需要清理"
fi

printf '%s\n' "----------------------------------------------------"
log_ok "GProxy 卸载完成"
