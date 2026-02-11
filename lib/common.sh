#!/bin/sh

# =================================================================
# GProxy 公共函数库
# 提供日志输出、平台检测、权限管理等基础功能
# 兼容 bash / ash (BusyBox) / dash 等 POSIX shell
# =================================================================

# --- 颜色定义 ---
# NOTE: 只有在终端支持颜色时才启用，避免日志文件中出现乱码
if [ -t 1 ] && [ -t 2 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# --- 日志函数 ---
# NOTE: 统一使用 printf 替代 echo -e，保证 ash 兼容性

log_info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

log_success() {
    printf "${GREEN}[OK]${NC} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

log_err() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

# --- 平台检测 ---

# 检测当前运行环境（设置全局变量 GPROXY_PLATFORM）
# 返回值: "openwrt" 或 "linux"
detect_platform() {
    if [ -f /etc/openwrt_release ]; then
        GPROXY_PLATFORM="openwrt"
    else
        GPROXY_PLATFORM="linux"
    fi
    export GPROXY_PLATFORM
}

# --- 权限管理 ---

# 以特权身份执行命令
# NOTE: OpenWrt 默认以 root 运行且没有 sudo，需要区分处理
run_privileged() {
    if [ "$(id -u)" -eq 0 ]; then
        # 已经是 root，直接执行
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        log_err "需要 root 权限执行此操作，请使用 root 用户运行"
        return 1
    fi
}

# --- 工具检测 ---

# 检测指定命令是否可用
has_command() {
    command -v "$1" >/dev/null 2>&1
}
