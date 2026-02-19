#!/bin/sh

export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
LOG_TAG="BT_MONITOR"
# 初始化为 unknown，确保第一次运行能有日志
LAST_STATE="unknown"

while true; do
    # 1. 获取配置
    DEVICE_MAC=$(uci -q get bluealsa.settings.mac | grep -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}')
    
    if [ -z "$DEVICE_MAC" ]; then
        logger -t $LOG_TAG "错误：未配置有效 MAC，脚本退出。"
        exit 0
    fi

    # 2. 检查连接状态
    IS_CONNECTED=$(bluetoothctl devices Connected | grep -i "$DEVICE_MAC")

    if [ -z "$IS_CONNECTED" ]; then
        # --- 状态：未连接 (音箱关机或距离远) ---
        
        # 只有在上次是“已连接”或者刚启动时，才打印一次断开日志
        if [ "$LAST_STATE" != "disconnected" ]; then
            logger -t $LOG_TAG "状态变更：目标设备 $DEVICE_MAC 未连接 (音箱可能已关机)"
            LAST_STATE="disconnected"
        fi

        # 冲突清理
        CURRENT_ACTIVE=$(bluetoothctl devices Connected | awk '{print $2}')
        if [ -n "$CURRENT_ACTIVE" ] && [ "$CURRENT_ACTIVE" != "$DEVICE_MAC" ]; then
            logger -t $LOG_TAG "发现非目标设备 $CURRENT_ACTIVE，准备切换..."
            bluetoothctl disconnect "$CURRENT_ACTIVE" >/dev/null 2>&1
            sleep 2
        fi

        # 静默尝试连接
        bluetoothctl connect "$DEVICE_MAC" >/dev/null 2>&1
        
        # 关机期间不必尝试太频繁，建议稍微延长重试间隔
        sleep 20
    else
        # --- 状态：已连接 ---
        
        # 只有在状态从“断开”变为“连接”时才发一条日志
        if [ "$LAST_STATE" != "connected" ]; then
            logger -t $LOG_TAG "状态变更：目标设备 $DEVICE_MAC 已连接成功"
            LAST_STATE="connected"
        fi
        
        sleep 10
    fi
done
