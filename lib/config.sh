#!/bin/sh

# =================================================================
# GProxy 配置管理模块
# 处理配置文件的初始化、加载和重置
# =================================================================

# --- 配置路径 ---
GPROXY_CONFIG_DIR="${HOME}/.config/gproxy"
GPROXY_CONFIG_FILE="${GPROXY_CONFIG_DIR}/config.env"

# --- 密钥自动发现 ---

# 定位 GProxy 安装/项目根目录
# NOTE: 按优先级搜索，安装目录优先于开发目录
find_project_root() {
    # 1. 已安装位置
    if [ -d "/usr/lib/gproxy/config" ]; then
        echo "/usr/lib/gproxy"
        return 0
    fi

    # 2. 脚本所在目录的上级（开发模式）
    _script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
    if [ -d "$_script_dir/../config" ]; then
        echo "$_script_dir/.."
        return 0
    fi

    # 3. 通过 LIB_DIR 反推（已加载的 lib 模块目录）
    if [ -n "$LIB_DIR" ] && [ -d "$LIB_DIR/../config" ]; then
        echo "$LIB_DIR/.."
        return 0
    fi

    return 1
}

# 自动搜索可用的密钥文件
# 搜索顺序：config 目录 → ~/.ssh/ 常用密钥
find_default_key() {
    # 1. 在项目 config 目录中搜索密钥文件
    _root=$(find_project_root 2>/dev/null)
    if [ -n "$_root" ] && [ -d "$_root/config" ]; then
        for _key_file in "$_root/config"/*.pem "$_root/config"/id_rsa "$_root/config"/id_ed25519; do
            if [ -f "$_key_file" ]; then
                echo "$_key_file"
                return 0
            fi
        done
    fi

    # 2. 检查 ~/.ssh/ 下的常用密钥
    for _key_file in "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ed25519"; do
        if [ -f "$_key_file" ]; then
            echo "$_key_file"
            return 0
        fi
    done

    return 1
}

# --- 配置向导 ---

# 交互式配置向导
# NOTE: 使用 printf + read 替代 read -p，兼容 BusyBox ash
init_config() {
    log_info "初次运行，需要配置海外服务器信息..."
    mkdir -p "$GPROXY_CONFIG_DIR"

    printf '%s\n' "----------------------------------------------------"

    printf "🖥️  请输入海外服务器 IP: "
    read -r INPUT_IP
    if [ -z "$INPUT_IP" ]; then
        log_err "服务器 IP 不能为空"
        return 1
    fi

    printf "👤 请输入用户名 (默认 root): "
    read -r INPUT_USER
    INPUT_USER="${INPUT_USER:-root}"

    printf "🚪 请输入 SSH 端口 (默认 22): "
    read -r INPUT_PORT
    INPUT_PORT="${INPUT_PORT:-22}"

    printf '%s\n' "----------------------------------------------------"

    # 尝试自动发现密钥文件
    _auto_key=$(find_default_key 2>/dev/null)
    if [ -n "$_auto_key" ]; then
        log_success "自动发现密钥文件: $_auto_key"
        printf "🔑 使用此密钥？[Y/n] "
        read -r _confirm
        case "$_confirm" in
            n|N|no|NO)
                # 用户拒绝，手动输入
                printf "🔑 请输入私钥路径: "
                read -r INPUT_KEY
                eval INPUT_KEY="$INPUT_KEY"
                ;;
            *)
                INPUT_KEY="$_auto_key"
                ;;
        esac
    else
        # 没有自动发现，手动输入
        log_info "请提供私钥文件路径 (用于免密连接)"
        printf "🔑 私钥路径 (例如 ~/.ssh/id_rsa): "
        read -r INPUT_KEY
        # 展开波浪号 ~
        # NOTE: ash 中 eval 行为与 bash 一致，可以安全使用
        eval INPUT_KEY="$INPUT_KEY"
    fi

    # 验证密钥文件
    if [ ! -f "$INPUT_KEY" ]; then
        log_err "找不到文件: $INPUT_KEY"
        return 1
    fi

    # 修复密钥权限 (SSH 强制要求 600)
    chmod 600 "$INPUT_KEY"
    log_success "密钥权限已修正 (600)"

    # 写入配置文件
    # NOTE: 不用双引号包裹值，避免 ash source 时引号残留在变量中
    cat > "$GPROXY_CONFIG_FILE" <<EOF
REMOTE_HOST=$INPUT_IP
REMOTE_USER=$INPUT_USER
REMOTE_PORT=$INPUT_PORT
IDENTITY_FILE=$INPUT_KEY
EOF

    log_success "配置已保存至: $GPROXY_CONFIG_FILE"
}

# --- 配置加载 ---

# 加载配置文件，若不存在则触发初始化向导
load_config() {
    if [ ! -f "$GPROXY_CONFIG_FILE" ]; then
        init_config || return 1
    fi

    # shellcheck disable=SC1090
    . "$GPROXY_CONFIG_FILE"

    # 验证必要字段
    if [ -z "$REMOTE_HOST" ] || [ -z "$IDENTITY_FILE" ]; then
        log_err "配置文件不完整，请重新配置: gproxy --config"
        return 1
    fi
}

# --- 配置重置 ---

reset_config() {
    if [ -f "$GPROXY_CONFIG_FILE" ]; then
        rm -f "$GPROXY_CONFIG_FILE"
        log_success "旧配置已清除"
    fi
    init_config
}
