#!/bin/sh

# =================================================================
# GProxy 隧道管理模块
# 处理 SSH 隧道的建立、端口检测和清理
# 兼容 openssh / dropbear，兼容多种端口检测工具
# =================================================================

# --- 全局变量 ---
LOCAL_PORT=19527
SSH_PID=""
GPROXY_SSH_CLIENT=""
GPROXY_SSH_CMD=""

# --- SSH 客户端检测 ---

# 检测可用的 SSH 客户端（优先使用 OpenSSH）
# NOTE: OpenWrt 默认的 Dropbear dbclient 不支持 -D (SOCKS5动态转发)
# 必须优先检测 OpenSSH，仅在 OpenSSH 不可用时降级到 Dropbear
detect_ssh_client() {
    # 优先级 1: 在常见路径中显式查找 OpenSSH
    # NOTE: OpenWrt 安装 openssh-client 后，ssh 位于 /usr/bin/ssh
    for _ssh_path in /usr/bin/ssh /usr/local/bin/ssh; do
        if [ -x "$_ssh_path" ]; then
            _ver=$("$_ssh_path" -V 2>&1 || true)
            if echo "$_ver" | grep -qi "openssh"; then
                GPROXY_SSH_CLIENT="openssh"
                GPROXY_SSH_CMD="$_ssh_path"
                export GPROXY_SSH_CLIENT GPROXY_SSH_CMD
                return 0
            fi
        fi
    done

    # 优先级 2: 通用 ssh 命令（可能是 openssh 或 dropbear 的 ssh）
    if has_command ssh; then
        _ver=$(ssh -V 2>&1 || true)
        if echo "$_ver" | grep -qi "openssh"; then
            GPROXY_SSH_CLIENT="openssh"
            GPROXY_SSH_CMD="ssh"
            export GPROXY_SSH_CLIENT GPROXY_SSH_CMD
            return 0
        fi
    fi

    # 优先级 3: Dropbear (dbclient 或 dropbear 的 ssh)
    if has_command dbclient; then
        GPROXY_SSH_CLIENT="dropbear"
        GPROXY_SSH_CMD="dbclient"
        export GPROXY_SSH_CLIENT GPROXY_SSH_CMD
        return 0
    fi
    if has_command ssh; then
        GPROXY_SSH_CLIENT="dropbear"
        GPROXY_SSH_CMD="ssh"
        export GPROXY_SSH_CLIENT GPROXY_SSH_CMD
        return 0
    fi

    log_err "未找到 SSH 客户端 (ssh 或 dbclient)"
    return 1
}

# 确保有可用的 SSH 客户端支持 SOCKS5 动态转发
# NOTE: 当只有 Dropbear 时提示安装 openssh-client
ensure_ssh_client() {
    if [ "$GPROXY_SSH_CLIENT" = "openssh" ]; then
        return 0
    fi

    # 只有 Dropbear 可用，Dropbear 不支持 -D (SOCKS5)，必须安装 openssh-client
    log_warn "当前 SSH 客户端为 Dropbear，不支持 SOCKS5 代理 (-D)"

    if has_command opkg; then
        log_info "正在尝试安装 openssh-client..."
        # NOTE: 不再静默输出，让用户看到失败原因
        if opkg update 2>&1 | tail -3 && opkg install openssh-client 2>&1; then
            log_success "openssh-client 安装成功"
            # 重新检测 SSH 客户端
            detect_ssh_client
            return 0
        fi
        log_err "openssh-client 安装失败"
    fi

    log_err "GProxy 需要 OpenSSH 客户端才能正常工作"
    log_err "请手动安装后重试: opkg update && opkg install openssh-client"
    return 1
}

# --- 密钥准备 ---

# 为 Dropbear 准备密钥（如需转换格式）
# NOTE: stdout 仅输出最终可用的密钥路径，所有日志输出到 stderr
prepare_identity_key() {
    _src_key="$1"

    # OpenSSH 直接使用 PEM 格式
    if [ "$GPROXY_SSH_CLIENT" = "openssh" ]; then
        echo "$_src_key"
        return 0
    fi

    # Dropbear 需要检查密钥格式
    _key_basename=$(basename "$_src_key")
    _cache_dir="${HOME}/.config/gproxy"
    _converted_key="${_cache_dir}/${_key_basename}.dropbear"

    # 如果已有转换缓存且比源文件更新，直接复用
    if [ -f "$_converted_key" ] && [ "$_converted_key" -nt "$_src_key" ]; then
        echo "$_converted_key"
        return 0
    fi

    # 检查源密钥是否为 OpenSSH PEM 格式
    if ! head -1 "$_src_key" 2>/dev/null | grep -q "BEGIN"; then
        # 不是 PEM 格式，可能已经是 Dropbear 格式
        echo "$_src_key"
        return 0
    fi

    # PEM 格式 + Dropbear → 需要转换
    if ! has_command dropbearconvert; then
        log_err "密钥格式不兼容：Dropbear 不支持 OpenSSH PEM 格式" >&2
        log_err "解决方案 (任选其一)：" >&2
        log_err "  1. opkg update && opkg install openssh-client" >&2
        log_err "  2. opkg update && opkg install dropbear  (获取 dropbearconvert)" >&2
        return 1
    fi

    # 执行格式转换
    mkdir -p "$_cache_dir"
    log_info "正在转换密钥格式 (PEM → Dropbear)..." >&2
    if dropbearconvert openssh dropbear "$_src_key" "$_converted_key" 2>/dev/null; then
        chmod 600 "$_converted_key"
        log_success "密钥已转换: $_converted_key" >&2
        echo "$_converted_key"
        return 0
    else
        log_err "密钥格式转换失败" >&2
        rm -f "$_converted_key"
        return 1
    fi
}

# --- 端口检测 ---

# 检测本地端口是否在监听
# NOTE: 按可用性依次降级：ss → netstat → /proc/net/tcp
check_port_listening() {
    _port="$1"

    if has_command ss; then
        ss -tln 2>/dev/null | grep -q ":${_port} "
    elif has_command netstat; then
        netstat -tln 2>/dev/null | grep -q ":${_port} "
    elif has_command lsof; then
        lsof -i ":${_port}" -sTCP:LISTEN -t >/dev/null 2>&1
    elif [ -f /proc/net/tcp ]; then
        # /proc/net/tcp 中端口以十六进制存储
        _hex_port=$(printf '%04X' "$_port")
        grep -qi ":${_hex_port} " /proc/net/tcp 2>/dev/null
    else
        # 兜底方案：无可用检测工具时，等待固定时间后假定成功
        log_warn "无端口检测工具可用，将等待 2 秒后继续"
        sleep 2
        return 0
    fi
}

# --- 连接测试 ---

# 快速测试 SSH 连接是否可达（不建立隧道）
# 用于在启动 SOCKS 隧道前验证凭证和网络连通性
test_ssh_connection() {
    _key="$1"
    log_info "正在测试 SSH 连接..."

    if [ "$GPROXY_SSH_CLIENT" = "openssh" ]; then
        # openssh: 用 exit 命令快速测试连通性
        "$GPROXY_SSH_CMD" -i "$_key" -p "$REMOTE_PORT" \
            -o ConnectTimeout=5 \
            -o BatchMode=yes \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            "${REMOTE_USER}@${REMOTE_HOST}" "exit 0" >/dev/null 2>&1
    else
        # dropbear: 使用 -T 选项快速测试（如果可用）
        "$GPROXY_SSH_CMD" -i "$_key" -p "$REMOTE_PORT" \
            -y \
            "${REMOTE_USER}@${REMOTE_HOST}" "exit 0" >/dev/null 2>&1
    fi

    if [ $? -eq 0 ]; then
        log_success "SSH 连接测试通过"
        return 0
    else
        log_err "SSH 连接测试失败"
        log_err "请检查: 1) IP/端口是否正确  2) 私钥是否匹配  3) 网络是否可达"
        return 1
    fi
}

# --- 隧道启动 ---

# 启动 SSH SOCKS5 隧道
start_tunnel() {
    # 准备密钥（Dropbear 可能需要格式转换）
    _actual_key=$(prepare_identity_key "$IDENTITY_FILE") || return 1

    log_info "正在连接 ${REMOTE_HOST}..."

    if [ "$GPROXY_SSH_CLIENT" = "openssh" ]; then
        # openssh 客户端，功能完整
        "$GPROXY_SSH_CMD" -i "$_actual_key" -p "$REMOTE_PORT" \
            -D "$LOCAL_PORT" \
            -N \
            -o ConnectTimeout=5 \
            -o BatchMode=yes \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ServerAliveInterval=60 \
            "${REMOTE_USER}@${REMOTE_HOST}" &

    elif [ "$GPROXY_SSH_CLIENT" = "dropbear" ]; then
        # dropbear 客户端（-D 可能不被支持）
        "$GPROXY_SSH_CMD" -i "$_actual_key" -p "$REMOTE_PORT" \
            -N -y \
            -D "$LOCAL_PORT" \
            "${REMOTE_USER}@${REMOTE_HOST}" &
    fi

    SSH_PID=$!
}

# --- 等待隧道就绪 ---

# 轮询等待隧道端口开始监听
wait_for_tunnel() {
    _timeout="${1:-10}"
    _count=0
    _max="$_timeout"

    while ! check_port_listening "$LOCAL_PORT"; do
        sleep 1
        _count=$(( _count + 1 ))

        # 检查 SSH 进程是否已退出（连接失败的情况）
        if ! kill -0 "$SSH_PID" 2>/dev/null; then
            log_err "SSH 连接失败"
            if [ "$GPROXY_SSH_CLIENT" = "dropbear" ]; then
                log_err "Dropbear 可能不支持 -D (SOCKS5代理)"
                log_err "解决方案: opkg update && opkg install openssh-client"
            else
                log_err "请检查 IP、端口或私钥是否正确"
            fi
            return 1
        fi

        if [ "$_count" -ge "$_max" ]; then
            log_err "连接超时！请检查网络连通性"
            kill "$SSH_PID" 2>/dev/null
            return 1
        fi
    done
}

# --- 设置代理环境变量 ---

setup_proxy_env() {
    export all_proxy="socks5h://127.0.0.1:${LOCAL_PORT}"
    export http_proxy="socks5h://127.0.0.1:${LOCAL_PORT}"
    export https_proxy="socks5h://127.0.0.1:${LOCAL_PORT}"
    # NOTE: 某些工具（如 curl）还会检查大写版本
    export ALL_PROXY="$all_proxy"
    export HTTP_PROXY="$http_proxy"
    export HTTPS_PROXY="$https_proxy"
}

# --- 隧道清理 ---

# 清理函数，关闭 SSH 隧道进程
# NOTE: 注册到 trap 信号，确保脚本异常退出时也能清理
cleanup_tunnel() {
    if [ -n "$SSH_PID" ]; then
        if kill -0 "$SSH_PID" 2>/dev/null; then
            kill "$SSH_PID"
            log_info "隧道已关闭 (PID: $SSH_PID)"
        fi
    fi
}
