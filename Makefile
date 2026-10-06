#
# bluez-alsa - Optimized Bluetooth Audio for OpenWrt
#
# This is free software, licensed under the GNU General Public License v2.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=bluez-alsa
PKG_VERSION:=4.3.1
PKG_RELEASE:=2

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/Arkq/bluez-alsa.git
PKG_SOURCE_VERSION:=v$(PKG_VERSION)
PKG_MIRROR_HASH:=skip

# === 24.10 / 25.12 / APK 打包必填 ===
PKG_MAINTAINER:=Your Name <you@example.com>
PKG_LICENSE:=LGPL-2.1-or-later
PKG_LICENSE_FILES:=COPYING

PKG_FIXUP:=autoreconf
PKG_INSTALL:=1
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/bluez-alsa
  SECTION:=sound
  CATEGORY:=Sound
  DEPENDS:=+alsa-lib +bluez-daemon +glib2 +sbc +dbus +mpg123 \
           +fdk-aac +libspandsp \
           +kmod-input-uinput +coreutils-timeout
  TITLE:=Optimized Bluetooth Audio for OpenWrt
  URL:=https://github.com/Arkq/bluez-alsa.git
endef

define Package/bluez-alsa/description
  BlueALSA adds full bandwidth bi-directional audio support for Bluetooth
  headsets, speakers, and other audio devices to OpenWrt.

  Includes bluealsa daemon, bluealsa-aplay, bluealsa-cli, and the ALSA
  PCM/CTL plugins (libasound_module_pcm_bluealsa, libasound_module_ctl_bluealsa).
endef

CONFIGURE_ARGS += \
	--enable-aplay \
	--enable-cli \
	--enable-aac \
	--enable-mpg123 \
	--enable-msbc \
	--enable-ofono \
	--disable-payloadcheck \
	--disable-libav

define Package/bluez-alsa/install
	# 1. 主程序
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/bluealsa       $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/bluealsa-aplay $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/bluealsa-cli   $(1)/usr/bin/

	# 2. ALSA 插件
	#    注意：不能写成 $(PKG_INSTALL_DIR)$(STAGING_DIR)/... —— 两个绝对路径拼接会
	#    产生不存在的路径，导致插件静默丢失。PKG_INSTALL:=1 时插件已经在
	#    $(PKG_INSTALL_DIR)/usr/lib/alsa-lib/ 下。
	$(INSTALL_DIR) $(1)/usr/lib/alsa-lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/alsa-lib/libasound_module_*.so \
	      $(1)/usr/lib/alsa-lib/

	# 3. ALSA 默认配置（自动寻找模式）
	$(INSTALL_DIR) $(1)/etc/alsa/conf.d
	echo 'pcm.bluealsa { type bluealsa device "00:00:00:00:00:00" profile "a2dp" }' \
		> $(1)/etc/alsa/conf.d/20-bluealsa.conf
	echo 'ctl.bluealsa { type bluealsa }' \
		>> $(1)/etc/alsa/conf.d/20-bluealsa.conf

	# 4. D-Bus 策略文件（不同版本安装位置不同，逐个探测）
	$(INSTALL_DIR) $(1)/etc/dbus-1/system.d
	for f in \
	    $(PKG_INSTALL_DIR)/usr/share/dbus-1/system.d/bluealsa.conf \
	    $(PKG_BUILD_DIR)/src/bluealsa-dbus.conf \
	    $(PKG_BUILD_DIR)/src/bluealsa.conf ; do \
		if [ -f "$$f" ]; then \
			$(INSTALL_DATA) "$$f" $(1)/etc/dbus-1/system.d/bluealsa.conf ; \
			break ; \
		fi ; \
	done

	# 5. init 脚本
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/bluealsa.init $(1)/etc/init.d/bluealsa

	# 6. 蓝牙监控脚本
	$(INSTALL_BIN) ./files/bt_monitor.sh $(1)/usr/bin/bt_monitor.sh

	# 7. UCI 配置
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/bluealsa.config $(1)/etc/config/bluealsa
endef

# 卸载时清理运行时状态（避免残留 pid/socket 让新装实例判定"已在运行"）
define Package/bluez-alsa/postrm
#!/bin/sh
[ -f "$${IPKG_INSTROOT}/etc/init.d/bluealsa" ] && \
	"$${IPKG_INSTROOT}/etc/init.d/bluealsa" stop 2>/dev/null || true
rm -f "$${IPKG_INSTROOT}/var/run/bluealsa.pid"
exit 0
endef

$(eval $(call BuildPackage,bluez-alsa))
