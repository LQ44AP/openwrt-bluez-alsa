#!/bin/sh

export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
LOG_TAG="BT_MONITOR"
LAST_STATE="unknown"

# 启动时获取一次配置
DEVICE_MAC=$(uci -q get bluealsa.settings.mac)

if [ -z "$DEVICE_MAC" ]; then
    logger -t $LOG_TAG "错误: 未配置目标 MAC 地址，监控退出。"
    exit 1
fi

logger -t $LOG_TAG "开始监控设备: $DEVICE_MAC"

while true; do
    # 1. 确保蓝牙硬件处于 UP 状态
    if ! hciconfig hci0 | grep -q "UP RUNNING"; then
        hciconfig hci0 up
        sleep 2
    fi

    # 2. 获取当前状态
    INFO=$(bluetoothctl info "$DEVICE_MAC" 2>/dev/null)
    CONNECTED=$(echo "$INFO" | grep -q "Connected: yes" && echo "on" || echo "off")
    RESOLVED=$(echo "$INFO" | grep -q "ServicesResolved: yes" && echo "on" || echo "off")

    if [ "$CONNECTED" = "on" ] && [ "$RESOLVED" = "on" ]; then
        CUR_STATE="connected"
    elif [ "$CONNECTED" = "on" ]; then
        CUR_STATE="handshaking"
    else
        CUR_STATE="disconnected"
    fi

    # 3. 状态变更日志
    if [ "$CUR_STATE" != "$LAST_STATE" ]; then
        logger -t $LOG_TAG "状态切换: $LAST_STATE -> $CUR_STATE"
        LAST_STATE=$CUR_STATE
    fi

    # 4. 只有在断开连接时才尝试执行连接动作
    if [ "$CUR_STATE" = "disconnected" ]; then
        logger -t $LOG_TAG "检测到断开，尝试连接 $DEVICE_MAC ..."
        printf "connect $DEVICE_MAC\nquit\n" | bluetoothctl >/dev/null 2>&1
        # 连接动作后给 5 秒冷却时间，防止操作过快
        sleep 5
    fi

    # 5. 轮询间隔：10秒检查一次状态
    sleep 10
done
