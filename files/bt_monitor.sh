#!/bin/sh

export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
LOG_TAG="BT_MONITOR"
LAST_STATE="unknown"

# 1. 启动时即刻检查配置
DEVICE_MAC=$(uci -q get bluealsa.settings.mac | grep -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}')

if [ -z "$DEVICE_MAC" ]; then
    logger -t $LOG_TAG "错误：未配置有效的 MAC 地址。脚本自动退出。"
    exit 0
fi

logger -t $LOG_TAG "监控启动，目标设备: $DEVICE_MAC"

while true; do
    # 2. 检查目标设备是否在【已连接】清单中
    # 使用 grep -i 忽略大小写，确保匹配稳健
    IS_CONNECTED=$(bluetoothctl devices Connected | grep -i "$DEVICE_MAC")

    if [ -z "$IS_CONNECTED" ]; then
        # --- 状态：未连接 ---
        
        # 3. 冲突检测：如果连了别的设备，先断开
        CURRENT_ACTIVE=$(bluetoothctl devices Connected | awk '{print $2}')
        if [ -n "$CURRENT_ACTIVE" ] && [ "$CURRENT_ACTIVE" != "$DEVICE_MAC" ]; then
            logger -t $LOG_TAG "发现非目标设备 $CURRENT_ACTIVE，准备切换..."
            bluetoothctl disconnect "$CURRENT_ACTIVE" >/dev/null 2>&1
            sleep 2
        fi

        # 4. 尝试连接
        logger -t $LOG_TAG "检测到断开，尝试连接 $DEVICE_MAC ..."
        # 仅执行 connect，不重复 pair
        bluetoothctl connect "$DEVICE_MAC" >/dev/null 2>&1
        
        LAST_STATE="disconnected"
        # 连接动作后给较长冷却期，防止蓝牙栈过载
        sleep 15
    else
        # --- 状态：已连接 ---
        
        # 5. 仅在状态切换时打印一次日志
        if [ "$LAST_STATE" != "connected" ]; then
            logger -t $LOG_TAG "目标设备 $DEVICE_MAC 已成功连接并就绪"
            LAST_STATE="connected"
        fi
        
        # 已连接时进入低频监控模式，节省 CPU
        sleep 10
    fi
    
    # 6. 每轮循环末尾再次确认配置是否有变（如果 LuCI 删除了 MAC，则退出）
    DEVICE_MAC_CHECK=$(uci -q get bluealsa.settings.mac)
    if [ -z "$DEVICE_MAC_CHECK" ]; then
        logger -t $LOG_TAG "配置已清空，脚本退出。"
        exit 0
    fi
done
