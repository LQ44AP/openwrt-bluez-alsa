include $(TOPDIR)/rules.mk

PKG_NAME:=bluez-alsa
PKG_VERSION:=4.3.1
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/Arkq/bluez-alsa.git
PKG_SOURCE_VERSION:=v4.3.1
PKG_MIRROR_HASH:=skip

PKG_FIXUP:=autoreconf
PKG_INSTALL:=1

include $(INCLUDE_DIR)/package.mk

define Package/bluez-alsa
  SECTION:=sound
  CATEGORY:=Sound
  DEPENDS:=+alsa-lib +bluez-daemon +glib2 +sbc +fdk-aac +dbus +mpg123 +libspandsp +kmod-input-uinput
  TITLE:=Optimized Bluetooth Audio for OpenWrt
  URL:=https://github.com/Arkq/bluez-alsa.git
endef

# 针对音频编解码进行性能优化
TARGET_CFLAGS += -O3 -fomit-frame-pointe

CONFIGURE_ARGS += \
    --enable-aplay \
    --enable-aac \
    --enable-mpg123 \
    --enable-msbc \
    --disable-payloadcheck \
    --with-libav-no \
    --with-alsalibdir=/usr/lib/alsa-lib \
	--enable-ofono \
	--enable-cli

define Package/bluez-alsa/install
	# 1. 创建所有目标目录
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_DIR) $(1)/usr/lib/alsa-lib
	$(INSTALL_DIR) $(1)/usr/lib
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/etc/dbus-1/system.d

	# 2. 安装主程序
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/bluealsa $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/bluealsa-aplay $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/bluealsa-cli $(1)/usr/bin/

	# 3. 安装 ALSA 插件
	# 如果 $(STAGING_DIR) 是绝对路径，有的环境需要去掉开头的斜杠
	$(CP) $(PKG_INSTALL_DIR)$(STAGING_DIR)/usr/lib/alsa-lib/libasound_module_*.so $(1)/usr/lib/alsa-lib/

	# 4. 路径修复补丁：建立软链接，让 aplay 不再报错
	ln -sf alsa-lib/libasound_module_pcm_bluealsa.so $(1)/usr/lib/libasound_module_pcm_bluealsa.so
	ln -sf alsa-lib/libasound_module_ctl_bluealsa.so $(1)/usr/lib/libasound_module_ctl_bluealsa.so

	# 5. 安装 D-Bus 配置文件
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/src/bluealsa-dbus.conf $(1)/etc/dbus-1/system.d/bluealsa.conf 2>/dev/null || \
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/src/bluealsa.conf $(1)/etc/dbus-1/system.d/bluealsa.conf

	# 6. 安装启动脚本
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/bluealsa.init $(1)/etc/init.d/bluealsa
	
	# 7. 安装监控脚本
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/bt_monitor.sh $(1)/usr/bin/bt_monitor.sh

	# 8. 安装配置文件
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./files/bluealsa.config $(1)/etc/config/bluealsa

	# 9. 写入动态 asound.conf (自动寻找模式)
	$(INSTALL_DIR) $(1)/etc/alsa/conf.d
	@echo 'pcm.bluealsa { type bluealsa device "00:00:00:00:00:00" profile "a2dp" }' > $(1)/etc/alsa/conf.d/20-bluealsa.conf
	@echo 'ctl.bluealsa { type bluealsa }' >> $(1)/etc/alsa/conf.d/20-bluealsa.conf
endef

$(eval $(call BuildPackage,bluez-alsa))
