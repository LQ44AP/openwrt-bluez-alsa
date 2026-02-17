#!/bin/sh

export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
LOG_TAG="BT_MONITOR"
LAST_STATE="unknown"

# 1. 启动时获取配置
DEVICE_MAC=$(uci -q get bluealsa.settings.mac)

# 2. 如果没有配置 MAC，直接记录日志并退出
if [ -z "$DEVICE_MAC" ]; then
    logger -t $LOG_TAG "错误: 未在 配置目标 MAC 地址。脚本自动退出。"
    exit 0  # 正常退出，避免 procd 认为崩溃而频繁重启
fi

logger -t $LOG_TAG "开始监控设备: $DEVICE_MAC"

while true; do
    # 硬件状态检查
    if ! hciconfig hci0 | grep -q "UP RUNNING"; then
        hciconfig hci0 up
        sleep 2
    fi

    # 获取蓝牙状态
    INFO=$(timeout 5 bluetoothctl info "$DEVICE_MAC" 2>/dev/null)
    
    # 检查 MAC 是否有效（如果填了错误的 MAC，info 会返回空）
    if [ -z "$INFO" ]; then
        logger -t $LOG_TAG "警告: 无法获取设备 $DEVICE_MAC 信息，请检查 MAC 是否正确。"
        sleep 30 # 如果 MAC 错误，降低重试频率
        continue
    fi

    CONNECTED=$(echo "$INFO" | grep -q "Connected: yes" && echo "on" || echo "off")
    RESOLVED=$(echo "$INFO" | grep -q "ServicesResolved: yes" && echo "on" || echo "off")

    if [ "$CONNECTED" = "on" ] && [ "$RESOLVED" = "on" ]; then
        CUR_STATE="connected"
    elif [ "$CONNECTED" = "on" ]; then
        CUR_STATE="handshaking"
    else
        CUR_STATE="disconnected"
    fi

    if [ "$CUR_STATE" != "$LAST_STATE" ]; then
        logger -t $LOG_TAG "状态: $LAST_STATE -> $CUR_STATE"
        LAST_STATE=$CUR_STATE
    fi

    if [ "$CUR_STATE" = "disconnected" ]; then
        printf "connect $DEVICE_MAC\nquit\n" | bluetoothctl >/dev/null 2>&1
        sleep 7
    fi

    sleep 10
done
