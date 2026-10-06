#!/bin/sh

export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

# ========================
# 默认配置（可通过 UCI 覆盖）
# ========================
LOG_TAG="BT_MONITOR"
SCAN_DURATION=8
PING_TIMEOUT=2
CONNECT_WAIT_MAX=20
DISCONNECTED_SLEEP=30
CONNECTED_SLEEP=20
CLEAN_OTHER_DEVICES=1

SCAN_PID=""
SCAN_LOG=""

# ========================
# 信号处理：退出时清理临时文件 + 后台扫描
# ========================
cleanup() {
    if [ -n "$SCAN_PID" ] && kill -0 "$SCAN_PID" 2>/dev/null; then
        kill "$SCAN_PID" 2>/dev/null
        wait "$SCAN_PID" 2>/dev/null
    fi
    [ -n "$SCAN_LOG" ] && rm -f "$SCAN_LOG"
    # 确保适配器退出扫描态，避免下一轮冲突
    timeout 3 bluetoothctl scan off >/dev/null 2>&1
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
# 统一包装 bluetoothctl，防止 D-Bus hang 拖死脚本
# ========================
btctl() {
    timeout 8 bluetoothctl "$@"
}

# ========================
# 检查蓝牙适配器是否就绪
# ========================
check_adapter() {
    btctl show 2>/dev/null | grep -q "Powered: yes"
}

# ========================
# 获取当前已连接的所有设备 MAC（大写）
# ========================
get_connected_macs() {
    btctl devices Connected 2>/dev/null | awk '{print $2}' | tr '[:lower:]' '[:upper:]'
}

# ========================
# 检查目标设备是否已连接（精确匹配 MAC）
# ========================
is_target_connected() {
    local target="$1"
    btctl devices Connected 2>/dev/null | awk '{print $2}' | grep -qi "^${target}$"
}

# ========================
# 断开指定设备
# ========================
disconnect_device() {
    local mac="$1"
    log "断开非目标设备 $mac"
    btctl disconnect "$mac" >/dev/null 2>&1
}

# ========================
# 清理所有非目标设备的连接（可选）
# ========================
cleanup_other_devices() {
    local target="$1"
    local mac
    get_connected_macs | while IFS= read -r mac; do
        [ -z "$mac" ] && continue
        [ "$mac" = "$target" ] && continue
        disconnect_device "$mac"
    done
}

# ========================
# 探测目标设备是否在线（l2ping + 短暂扫描）
# ========================
probe_device() {
    local target="$1"

    # 1. l2ping 快速探测
    if command -v l2ping >/dev/null 2>&1; then
        if timeout $((PING_TIMEOUT + 2)) l2ping -c 1 -t "$PING_TIMEOUT" "$target" >/dev/null 2>&1; then
            return 0
        fi
    fi

    # 2. 复位扫描态（避免 "Operation already in progress"）
    btctl scan off >/dev/null 2>&1
    sleep 1

    # 3. 扫描
    SCAN_LOG="/tmp/bt_scan.$$.log"
    : > "$SCAN_LOG"
    btctl scan on > "$SCAN_LOG" 2>&1 &
    SCAN_PID=$!

    sleep "$SCAN_DURATION"

    if [ -n "$SCAN_PID" ] && kill -0 "$SCAN_PID" 2>/dev/null; then
        kill "$SCAN_PID" 2>/dev/null
        wait "$SCAN_PID" 2>/dev/null
    fi
    SCAN_PID=""

    # 4. 显式关扫描（杀进程不保证 D-Bus 层已停）
    btctl scan off >/dev/null 2>&1

    grep -qi "$target" "$SCAN_LOG"
    local result=$?
    rm -f "$SCAN_LOG"
    SCAN_LOG=""
    return $result
}

# ========================
# 尝试连接目标设备，并等待连接确认
# ========================
connect_target() {
    local target="$1"
    log "尝试连接 $target ..."
    btctl connect "$target" >/dev/null 2>&1

    # 轮询间隔 2 秒，最少等一轮
    local waited=0
    while [ "$waited" -lt "$CONNECT_WAIT_MAX" ]; do
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
    if ! command -v timeout >/dev/null 2>&1; then
        log "错误: timeout 未找到，请安装 coreutils-timeout"
        exit 1
    fi
    if ! command -v l2ping >/dev/null 2>&1; then
        log "提示: l2ping 未安装，将仅使用扫描探测（建议安装 bluez-utils-extra）"
    fi
}

# ========================
# 从 UCI 读取配置（带数值校验）
# ========================
uci_get_int() {
    local key="$1" default="$2" val
    val=$(uci -q get "$key")
    case "$val" in
        ''|*[!0-9]*) echo "$default" ;;
        *)           echo "$val" ;;
    esac
}

load_config() {
    local raw_mac
    raw_mac=$(uci -q get bluealsa.settings.mac)
    TARGET_MAC=$(echo "$raw_mac" | grep -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' | tr '[:lower:]' '[:upper:]')
    if [ -z "$TARGET_MAC" ]; then
        log "配置为空或 MAC 地址格式错误，监控脚本退出。"
        exit 0
    fi

    SCAN_DURATION=$(uci_get_int         bluealsa.monitor.scan_duration       "$SCAN_DURATION")
    PING_TIMEOUT=$(uci_get_int          bluealsa.monitor.ping_timeout        "$PING_TIMEOUT")
    CONNECT_WAIT_MAX=$(uci_get_int      bluealsa.monitor.connect_wait_max    "$CONNECT_WAIT_MAX")
    DISCONNECTED_SLEEP=$(uci_get_int    bluealsa.monitor.disconnected_sleep  "$DISCONNECTED_SLEEP")
    CONNECTED_SLEEP=$(uci_get_int       bluealsa.monitor.connected_sleep     "$CONNECTED_SLEEP")
    CLEAN_OTHER_DEVICES=$(uci_get_int   bluealsa.monitor.clean_other_devices "$CLEAN_OTHER_DEVICES")
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
        if ! check_adapter; then
            sleep 10
            continue
        fi

        if is_target_connected "$TARGET_MAC"; then
            if [ "$last_state" != "connected" ]; then
                log "目标设备 $TARGET_MAC 已连接"
                last_state="connected"
            fi
            sleep "$CONNECTED_SLEEP"
        else
            if [ "$last_state" != "disconnected" ]; then
                log "目标设备断开，开始探测..."
                last_state="disconnected"
            fi

            if [ "$CLEAN_OTHER_DEVICES" -eq 1 ]; then
                cleanup_other_devices "$TARGET_MAC"
            fi

            if probe_device "$TARGET_MAC"; then
                log "探测到目标在线"
                if connect_target "$TARGET_MAC"; then
                    # 连接成功后回到主循环重新判定状态
                    last_state="unknown"
                    continue
                fi
            fi
            sleep "$DISCONNECTED_SLEEP"
        fi
    done
}

main
