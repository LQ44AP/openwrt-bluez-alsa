#!/bin/sh

export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
LOG_TAG="BT_MONITOR"
LAST_STATE="unknown"

while true; do
    # 1. 获取配置
    RAW_MAC=$(uci -q get bluealsa.settings.mac)
    DEVICE_MAC=$(echo "$RAW_MAC" | grep -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' | tr '[:lower:]' '[:upper:]')
    
    if [ -z "$DEVICE_MAC" ]; then
        logger -t $LOG_TAG "配置为空或 MAC 地址格式错误，监控脚本退出。"
        exit 0
    fi

    # 2. 检查连接状态
    CONNECTED_MACS=$(bluetoothctl devices Connected | awk '{print $2}' | tr '[:lower:]' '[:upper:]')

    if echo "$CONNECTED_MACS" | grep -q "$DEVICE_MAC"; then
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
        for mac in $CONNECTED_MACS; do
            if [ "$mac" != "$DEVICE_MAC" ]; then
                logger -t $LOG_TAG "发现非目标连接 $mac ，正在断开..."
                bluetoothctl disconnect "$mac" >/dev/null 2>&1
            fi
        done

        # 4. 核心探测
        if l2ping -c 1 -t 2 "$DEVICE_MAC" >/dev/null 2>&1 || \
           (timeout 5 bluetoothctl scan on | grep -iq "$DEVICE_MAC"); then
            logger -t $LOG_TAG "探测到目标在线，尝试连接..."
            bluetoothctl connect "$DEVICE_MAC" >/dev/null 2>&1
            sleep 15
        else
            sleep 30
        fi
    fi
done
