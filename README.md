基于 https://github.com/arkq/bluez-alsa 移植。


关于编译（需要这个组件）：sudo apt install libglib2.0-dev-bin


1.安装（假定ipk在root目录）
opkg update && opkg install /root/bluez-alsa*.ipk

2.使用 bluetoothctl 配对：
bluetoothctl
[bluetooth]# power on
[bluetooth]# agent on
[bluetooth]# default-agent
[bluetooth]# scan on
-- 扫描到蓝牙音箱 MAC 地址后 (例如 41:42:5E:33:5C:32) --
[bluetooth]# pair 41:42:5E:33:5C:32
[bluetooth]# trust 41:42:5E:33:5C:32
[bluetooth]# connect 41:42:5E:33:5C:32
-- 蓝牙音箱提示连接成功后，输入 exit 退出配对 --

3.确认蓝牙音箱连接成功后，将蓝牙音箱mac保存到配置文件并重启程序
uci set bluealsa.settings.mac=音箱的MAC && uci commit bluealsa && /etc/init.d/bluealsa restart

++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

注1：程序体积很小，但是依赖组件很多，需要空间>5MB

注2：ipk用openwrt官方sdk编译，如果运行时提示依赖组件版本不一致，fork项目，修改build.yml为所用固件相近的sdk重新编译。

注3：接收模式只做了简单的开关，并没有相应的调用。有这个需求的参考原项目，自行修改/etc/init.d/bluealsa、/etc/config/bluealsa

注4：ai生成的自动连接监控脚本（ /usr/bin/bt_monitor.sh ），属于可用的水平，请自行优化

++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

播放软件mpd的audio可以这样配置

audio_output {

type "alsa"

name "My BlueALSA"

device "bluealsa" # 这里对应 asound.conf 里的 pcm.bluealsa

mixer_type "software" # 建议用软件调音或者 none

auto_resample "no"

auto_channels "no"

auto_format "no"

}
