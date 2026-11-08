include ../AxsPlayStarBuild.mk
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AxsPlayStarPrefs
AxsPlayStarPrefs_FILES = $(wildcard *.m)
AxsPlayStarPrefs_CFLAGS = -fobjc-arc -I../Sources
AxsPlayStarPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
AxsPlayStarPrefs_PRIVATE_FRAMEWORKS = Preferences
AxsPlayStarPrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup
AxsPlayStarPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
