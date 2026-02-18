#!/bin/sh

export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
LOG_TAG="BT_MONITOR"
LAST_STATE="unknown"

while true; do
    # 1. 获取配置
    DEVICE_MAC=$(uci -q get bluealsa.settings.mac | grep -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}')
    [ -z "$DEVICE_MAC" ] && exit 0
	
	if [ -z "$DEVICE_MAC" ]; then
    	logger -t $LOG_TAG "错误：未在 uci 中配置有效的 MAC 地址。脚本自动退出。"
    	exit 0
	fi

    # 2. 【核心修改】检查目标设备是否在“已连接”列表中
    # 这种方式比解析 info 命令更准确
    IS_CONNECTED=$(bluetoothctl devices Connected | grep -i "$DEVICE_MAC")

    if [ -z "$IS_CONNECTED" ]; then
        # --- 状态：未连接 ---
        
        # 冲突清理：如果连了别的设备，先踢掉
        CURRENT_ACTIVE=$(bluetoothctl devices Connected | awk '{print $2}')
        if [ -n "$CURRENT_ACTIVE" ] && [ "$CURRENT_ACTIVE" != "$DEVICE_MAC" ]; then
            logger -t $LOG_TAG "发现非目标设备 $CURRENT_ACTIVE，准备断开..."
            bluetoothctl disconnect "$CURRENT_ACTIVE" >/dev/null 2>&1
            sleep 2
        fi

        logger -t $LOG_TAG "检测到断开，尝试连接 $DEVICE_MAC ..."
        bluetoothctl connect "$DEVICE_MAC" >/dev/null 2>&1
        
        LAST_STATE="disconnected"
        sleep 15
    else
        # --- 状态：已连接 ---
        
        # 只有在状态从“断开”变为“连接”时才发一条日志，不再刷屏
        if [ "$LAST_STATE" != "connected" ]; then
            logger -t $LOG_TAG "目标设备 $DEVICE_MAC 已连接成功"
            LAST_STATE="connected"
        fi
        
        # 已连接状态下，每 10 秒检查一次即可，节省资源
        sleep 10
    fi
done
