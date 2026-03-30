#!/bin/sh

export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

# ========================
# 默认配置（可通过 UCI 覆盖）
# ========================
LOG_TAG="BT_MONITOR"
SCAN_DURATION=8          # 扫描持续时间（秒）
PING_TIMEOUT=2           # l2ping 超时（秒）
CONNECT_WAIT_MAX=20      # 连接后等待最大时间（秒）
DISCONNECTED_SLEEP=30    # 未探测到时休眠时间（秒）
CONNECTED_SLEEP=20       # 已连接时休眠时间（秒）
CLEAN_OTHER_DEVICES=1    # 是否断开非目标设备（1=是，0=否）

# ========================
# 信号处理：退出时清理临时文件
# ========================
cleanup() {
    rm -f "/tmp/bt_scan.$$.log"
    exit 0
}
trap cleanup INT TERM

# ========================
# 日志函数
# ========================
log() {
    logger -t "$LOG_TAG" "$1"
}

# ========================
# 检查蓝牙适配器是否就绪
# ========================
check_adapter() {
    if ! bluetoothctl show | grep -q "Powered: yes"; then
        log "蓝牙适配器未就绪或未通电"
        return 1
    fi
    return 0
}

# ========================
# 获取当前已连接的所有设备 MAC（大写）
# ========================
get_connected_macs() {
    bluetoothctl devices Connected | awk '{print $2}' | tr '[:lower:]' '[:upper:]'
}

# ========================
# 检查目标设备是否已连接（精确匹配 MAC）
# ========================
is_target_connected() {
    local target="$1"
    # 精确匹配 MAC 列，避免设备名中包含 MAC 子串导致误判
    bluetoothctl devices Connected | awk '{print $2}' | grep -qi "^$target$"
}

# ========================
# 断开指定设备
# ========================
disconnect_device() {
    local mac="$1"
    log "断开非目标设备 $mac"
    bluetoothctl disconnect "$mac" >/dev/null 2>&1
}

# ========================
# 清理所有非目标设备的连接（可选）
# ========================
cleanup_other_devices() {
    local target="$1"
    local connected
    connected=$(get_connected_macs)
    for mac in $connected; do
        if [ "$mac" != "$target" ]; then
            disconnect_device "$mac"
        fi
    done
}

# ========================
# 探测目标设备是否在线（l2ping + 短暂扫描）
# ========================
probe_device() {
    local target="$1"
    local scan_log="/tmp/bt_scan.$$.log"

    # 1. 如果 l2ping 存在，优先使用（快速且不干扰扫描）
    if command -v l2ping >/dev/null 2>&1; then
        if l2ping -c 1 -t "$PING_TIMEOUT" "$target" >/dev/null 2>&1; then
            return 0
        fi
    else
        log "提示: l2ping 未安装，将仅使用扫描探测（可能较慢）"
    fi

    # 2. 确保没有残留扫描，避免冲突
    bluetoothctl scan off >/dev/null 2>&1
    sleep 1

    # 3. 启动扫描并记录输出
    bluetoothctl scan on > "$scan_log" 2>&1 &
    local scan_pid=$!
    sleep "$SCAN_DURATION"
    kill "$scan_pid" 2>/dev/null
    wait "$scan_pid" 2>/dev/null

    # 4. 关闭扫描（确保适配器回到非扫描状态）
    bluetoothctl scan off >/dev/null 2>&1

    # 5. 检查日志中是否出现目标 MAC
    grep -qi "$target" "$scan_log"
    local result=$?
    rm -f "$scan_log"
    return $result
}

# ========================
# 尝试连接目标设备，并等待连接确认
# ========================
connect_target() {
    local target="$1"
    log "尝试连接 $target ..."
    bluetoothctl connect "$target" >/dev/null 2>&1

    # 轮询等待连接成功
    local waited=0
    while [ $waited -lt "$CONNECT_WAIT_MAX" ]; do
        sleep 2
        waited=$((waited + 2))
        if is_target_connected "$target"; then
            log "连接成功"
            return 0
        fi
    done
    log "连接超时，未能建立连接"
    return 1
}

# ========================
# 检查必要依赖
# ========================
check_dependencies() {
    if ! command -v bluetoothctl >/dev/null 2>&1; then
        log "错误: bluetoothctl 未找到，请安装 bluez-utils"
        exit 1
    fi
    # l2ping 不是必须的，仅提示
    if ! command -v l2ping >/dev/null 2>&1; then
        log "提示: l2ping 未安装，将仅使用扫描探测（建议安装 bluez-utils-extra）"
    fi
}

# ========================
# 从 UCI 读取配置
# ========================
load_config() {
    # 目标 MAC（必须）
    local raw_mac
    raw_mac=$(uci -q get bluealsa.settings.mac)
    TARGET_MAC=$(echo "$raw_mac" | grep -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' | tr '[:lower:]' '[:upper:]')
    if [ -z "$TARGET_MAC" ]; then
        log "配置为空或 MAC 地址格式错误，监控脚本退出。"
        exit 0
    fi

    # 可选参数（如果 UCI 节点存在则覆盖默认值）
    local tmp
    tmp=$(uci -q get bluealsa.monitor.scan_duration)      && [ -n "$tmp" ] && SCAN_DURATION="$tmp"
    tmp=$(uci -q get bluealsa.monitor.ping_timeout)       && [ -n "$tmp" ] && PING_TIMEOUT="$tmp"
    tmp=$(uci -q get bluealsa.monitor.connect_wait_max)   && [ -n "$tmp" ] && CONNECT_WAIT_MAX="$tmp"
    tmp=$(uci -q get bluealsa.monitor.disconnected_sleep) && [ -n "$tmp" ] && DISCONNECTED_SLEEP="$tmp"
    tmp=$(uci -q get bluealsa.monitor.connected_sleep)    && [ -n "$tmp" ] && CONNECTED_SLEEP="$tmp"
    tmp=$(uci -q get bluealsa.monitor.clean_other_devices)&& [ -n "$tmp" ] && CLEAN_OTHER_DEVICES="$tmp"
}

# ========================
# 主循环
# ========================
main() {
    check_dependencies
    load_config
    log "蓝牙监控启动，目标设备: $TARGET_MAC"
    local last_state="unknown"

    while true; do
        # 检查适配器状态
        if ! check_adapter; then
            sleep 10
            continue
        fi

        if is_target_connected "$TARGET_MAC"; then
            # --- 已连接状态 ---
            if [ "$last_state" != "connected" ]; then
                log "目标设备 $TARGET_MAC 已连接"
                last_state="connected"
            fi
            sleep "$CONNECTED_SLEEP"
        else
            # --- 未连接状态 ---
            if [ "$last_state" != "disconnected" ]; then
                log "目标设备断开，开始探测..."
                last_state="disconnected"
            fi

            # 可选：清理其他非目标连接
            if [ "$CLEAN_OTHER_DEVICES" -eq 1 ]; then
                cleanup_other_devices "$TARGET_MAC"
            fi

            # 探测设备是否存在
            if probe_device "$TARGET_MAC"; then
                log "探测到目标在线"
                if connect_target "$TARGET_MAC"; then
                    # 连接成功后立即进入下一轮循环，不必额外等待
                    continue
                fi
            fi
            sleep "$DISCONNECTED_SLEEP"
        fi
    done
}

# 启动脚本
main
