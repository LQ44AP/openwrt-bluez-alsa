1. 安装（假定ipk在root目录）


opkg update && opkg install /root/bluez-alsa_4.3.1-1_mipsel_24kc.ipk



2. 停止自动连接脚本


/etc/init.d/bt_monitor stop



3. 使用 bluetoothctl 配对：

bluetoothctl

power on

agent on

default-agent

scan on

#找到蓝牙音箱 MAC 地址后 (例如 41:42:5E:33:5C:32)

pair 41:42:5E:33:5C:32

trust 41:42:5E:33:5C:32

connect 41:42:5E:33:5C:32



4.确认蓝牙音箱连接成功后，修改绑定的蓝牙音箱mac并重启自动连接脚本


uci set bluealsa.settings.mac='新的MAC' && uci commit bluealsa && /etc/init.d/bt_monitor restart




关于编译（需要这个组件）：sudo apt install libglib2.0-dev-bin
