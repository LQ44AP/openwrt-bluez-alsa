#!/bin/sh

export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
LOG_TAG="BT_MONITOR"
LAST_STATE="unknown"

# 从 UCI 获取一次 MAC 地址即可
DEVICE_MAC=$(uci -q get bluealsa.settings.mac)

if [ -z "$DEVICE_MAC" ]; then
    logger -t $LOG_TAG "错误: 未配置目标 MAC 地址，退出。"
    exit 1
fi

while true; do
	# 1. 硬件层守护 (确保蓝牙适配器是开启状态)
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
		logger -t $LOG_TAG "Status: $LAST_STATE -> $CUR_STATE"
		LAST_STATE=$CUR_STATE
	fi

	# 4. 执行自动连接动作 (如果是断开状态)
	if [ "$CUR_STATE" = "disconnected" ]; then
		logger -t $LOG_TAG "尝试连接设备: $DEVICE_MAC ..."
		printf "connect $DEVICE_MAC\nquit\n" | bluetoothctl >/dev/null 2>&1
		sleep 5 # 连接动作后的冷却时间
	fi

	sleep 10 # 轮询间隔
done
