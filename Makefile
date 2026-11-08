DEBUG = 0
FINALPACKAGE = 1

ARCHS = arm64 arm64e

# Share the SDK and deployment targets with the PreferenceBundle.
include AxsPlayStarBuild.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AxsPlayStar
# 安装后重启两个宿主进程，锁屏卡片才会重新加载插件
INSTALL_TARGET_PROCESSES = MediaRemoteUI SpringBoard
AxsPlayStar_FILES = $(wildcard Hooks/*.xm Sources/*.m)
# iOS 16 的 libobjc 不认 clang 17 给 ObjC 类 ro 指针打的 ptrauth 签名，
# arm64e 注入会在 readClass() 里崩；探测编译器是否支持该开关再决定是否关闭。
AXS_PTRAUTH_CFLAGS := $(shell $(TARGET_CC) -x objective-c -fsyntax-only -fno-ptrauth-objc-class-ro /dev/null >/dev/null 2>&1 && echo -fno-ptrauth-objc-class-ro)

AxsPlayStar_CFLAGS = -fobjc-arc -I./Headers -I./Sources $(AXS_PTRAUTH_CFLAGS)
AxsPlayStar_FRAMEWORKS = UIKit Foundation CoreFoundation
AxsPlayStar_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += AxsPlayStarPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
