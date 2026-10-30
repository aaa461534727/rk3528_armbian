include $(TOPDIR)/rules.mk

PKG_NAME:=aic8800
PKG_VERSION:=V4
PKG_RELEASE:=0

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

define KernelPackage/aic8800
  SUBMENU:=Wireless Drivers
  TITLE:=AIC 8800 wireless support
 # DEPENDS:= +kmod-mac80211
  FILES:= \
	$(PKG_BUILD_DIR)/aic8800_bsp/aic8800_bsp.ko \
	$(PKG_BUILD_DIR)/aic8800_fdrv/aic8800_fdrv.ko
#  AUTOLOAD:=$(call AutoProbe,plat_1105 wifi_1105)
endef

define KernelPackage/aic8800/config
	choice
		depends on PACKAGE_kmod-aic8800
		prompt "aic8800 type"
		config AIC8800_PCIE
			bool "aic8800 pcie"
			depends on PACKAGE_kmod-aic8800
			default n
			help
				aic8800 use pcie

		config AIC8800_SDIO
			bool "aic8800 sdio"
			depends on PACKAGE_kmod-aic8800
			default n
			help
				aic8800 use sdio
	endchoice
endef

EXTRA_KCONFIG:= \
	HI110X_DRIVER_SRC_PATH="$(PKG_BUILD_DIR)" 

DRIVER_DIR:=sdio
ifeq ($(CONFIG_AIC8800_PCIE),y)
DRIVER_DIR=pcie
endif

define Build/Prepare
        mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./$(DRIVER_DIR)/aic8800/* $(PKG_BUILD_DIR)/
endef


define Build/Compile
	+$(MAKE) $(PKG_JOBS) -C "$(LINUX_DIR)" \
		KERNEL_DIR="$(LINUX_DIR)" \
		$(KERNEL_MAKE_FLAGS) \
		M="$(PKG_BUILD_DIR)" \
		$(EXTRA_KCONFIG) \
		modules
endef

define KernelPackage/aic8800/install
	$(INSTALL_DIR) $(1)/vendor/etc/firmware
	$(INSTALL_BIN) ./fw/aic8800D80/* $(1)/vendor/etc/firmware
endef

$(eval $(call KernelPackage,aic8800))
