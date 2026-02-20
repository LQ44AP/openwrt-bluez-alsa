#!/bin/sh

export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
LOG_TAG="BT_MONITOR"
LAST_STATE="unknown"

while true; do
    # 1. 获取并验证配置
    DEVICE_MAC=$(uci -q get bluealsa.settings.mac | grep -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}')
    
    # 未配置则彻底退出
    if [ -z "$DEVICE_MAC" ]; then
        logger -t $LOG_TAG "配置为空或 MAC 地址格式不正确，监控脚本退出。"
        exit 0
    fi

    # 2. 检查连接状态
    if bluetoothctl devices Connected | grep -iq "$DEVICE_MAC"; then
        # --- 状态：已连接 ---
        if [ "$LAST_STATE" != "connected" ]; then
            logger -t $LOG_TAG "目标设备 $DEVICE_MAC 已就绪"
            LAST_STATE="connected"
        fi
        sleep 20
    else
        # --- 状态：未连接 ---
        if [ "$LAST_STATE" != "disconnected" ]; then
            logger -t $LOG_TAG "目标断开，开始探测 $DEVICE_MAC ..."
            LAST_STATE="disconnected"
        fi

        # 3. 冲突清理
        CURRENT_ACTIVE=$(bluetoothctl devices Connected | awk '{print $2}')
        if [ -n "$CURRENT_ACTIVE" ] && [ "$CURRENT_ACTIVE" != "$DEVICE_MAC" ]; then
            logger -t $LOG_TAG "发现非目标连接 $CURRENT_ACTIVE，正在断开..."
            bluetoothctl disconnect "$CURRENT_ACTIVE" >/dev/null 2>&1
            sleep 2
        fi

        # 4. 核心探测：使用 hcitool info
        # 注意：info 命令在设备不在线时会产生 "I/O error" 的底层日志
        if hcitool info "$DEVICE_MAC" >/dev/null 2>&1; then
            logger -t $LOG_TAG "探测到目标在线，发起连接..."
            bluetoothctl connect "$DEVICE_MAC" >/dev/null 2>&1
            sleep 15
        else
            sleep 30
        fi
    fi
done
