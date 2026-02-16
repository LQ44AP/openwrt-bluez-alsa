安装（假定ipk在root目录）
opkg update && opkg install /root/bluez-alsa_4.3.1-1_mipsel_24kc.ipk

停止自动连接脚本
/etc/init.d/bt_monitor stop

使用 bluetoothctl 配对：
bluetoothctl

power on

agent on

default-agent

scan on
# 找到音箱 MAC 地址后 (例如 41:42:5E:33:5C:32)

pair 41:42:5E:33:5C:32

trust 41:42:5E:33:5C:32

connect 41:42:5E:33:5C:32

#确认音箱连接成功后

修改绑定的音箱mac并重启自动连接脚本
uci set bluealsa.settings.mac='新的MAC' && uci commit bluealsa && /etc/init.d/bt_monitor restart
