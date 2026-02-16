#!/bin/sh

export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
LOG_TAG="BT_MONITOR"
LAST_STATE="unknown"

while true; do
	# 从 UCI 动态读取配置
	DEVICE_MAC=$(uci -q get bluealsa.settings.mac)
	ENABLED=$(uci -q get bluealsa.settings.enabled)

	# 检查开关
	if [ "$ENABLED" != "1" ] || [ -z "$DEVICE_MAC" ]; then
		sleep 60
		continue
	fi

	# 1. 硬件层守护
	if ! hciconfig hci0 | grep -q "UP RUNNING"; then
		hciconfig hci0 up
		sleep 2
	fi

	# 2. 获取当前状态 (Connected & Resolved)
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

	# 4. 状态机动作
	case $CUR_STATE in
		"connected")
			sleep 30
			;;
		"handshaking")
			# 等待协议栈自行解析服务，不在此处刷 connect 指令
			sleep 10
			;;
		"disconnected")
			# 尝试静默连接
			printf "connect $DEVICE_MAC\nquit\n" | bluetoothctl >/dev/null 2>&1
			sleep 40
			;;
	esac
	sleep 5
done