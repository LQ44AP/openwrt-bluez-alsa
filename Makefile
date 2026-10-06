#
# bluez-alsa - Bluetooth Audio ALSA Backend for OpenWrt
#

include $(TOPDIR)/rules.mk

PKG_NAME:=bluez-alsa
PKG_VERSION:=5.0.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/Arkq/bluez-alsa.git
PKG_SOURCE_VERSION:=v$(PKG_VERSION)
PKG_MIRROR_HASH:=skip

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
  TITLE:=Optimized Bluetooth Audio for OpenWrt
  URL:=https://github.com/Arkq/bluez-alsa.git
  DEPENDS:=+alsa-lib +bluez-daemon +glib2 +sbc +dbus +mpg123 \
           +fdk-aac +libspandsp \
           +bluez-utils +bluez-utils-extra \
           +coreutils-timeout +kmod-input-uinput \
           +libbsd
endef

define Package/bluez-alsa/description
  BlueALSA adds full bandwidth bi-directional audio support for Bluetooth
  headsets, speakers, and other audio devices to OpenWrt.

  Includes bluealsad daemon, bluealsa-aplay, bluealsactl, and the ALSA
  PCM/CTL plugins (libasound_module_pcm_bluealsa, libasound_module_ctl_bluealsa).
endef

CONFIGURE_ARGS += \
	--enable-aplay \
	--enable-aac \
	--enable-mpg123 \
	--enable-msbc \
	--enable-ofono \
	--disable-payloadcheck \
	--disable-libav \
	--disable-systemd \
	--with-alsaplugindir=/usr/lib/alsa-lib \
	--with-alsaconfdir=/etc/alsa/conf.d \
	--with-dbusconfdir=/etc/dbus-1/system.d

define Package/bluez-alsa/install
	# 1. 主程序
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/bluealsad      $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/bluealsa-aplay $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/bluealsactl    $(1)/usr/bin/

	# 2. ALSA 插件（--with-alsaplugindir 已钉死路径，这里直接复制）
	$(INSTALL_DIR) $(1)/usr/lib/alsa-lib
	$(CP) $(PKG_INSTALL_DIR)/usr/lib/alsa-lib/libasound_module_*.so \
	      $(1)/usr/lib/alsa-lib/

	# 3. ALSA 默认配置
	$(INSTALL_DIR) $(1)/etc/alsa/conf.d
	echo 'pcm.bluealsa { type bluealsa device "00:00:00:00:00:00" profile "a2dp" }' \
		> $(1)/etc/alsa/conf.d/20-bluealsa.conf
	echo 'ctl.bluealsa { type bluealsa }' \
		>> $(1)/etc/alsa/conf.d/20-bluealsa.conf

	# 4. D-Bus 策略文件（--with-dbusconfdir 已钉死路径）
	$(INSTALL_DIR) $(1)/etc/dbus-1/system.d
	$(INSTALL_DATA) $(PKG_INSTALL_DIR)/etc/dbus-1/system.d/org.bluealsa.conf \
	                $(1)/etc/dbus-1/system.d/org.bluealsa.conf

	# 5. init 脚本
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/bluealsa.init $(1)/etc/init.d/bluealsa

	# 6. 蓝牙监控脚本
	$(INSTALL_BIN) ./files/bt_monitor.sh $(1)/usr/bin/bt_monitor.sh

	# 7. UCI 配置
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/bluealsa.config $(1)/etc/config/bluealsa
endef

define Package/bluez-alsa/postrm
#!/bin/sh
[ -f "$${IPKG_INSTROOT}/etc/init.d/bluealsa" ] && \
	"$${IPKG_INSTROOT}/etc/init.d/bluealsa" stop 2>/dev/null || true
rm -f "$${IPKG_INSTROOT}/var/run/bluealsad.pid"
rm -f "$${IPKG_INSTROOT}/var/run/bt_monitor.state"
exit 0
endef

$(eval $(call BuildPackage,bluez-alsa))
